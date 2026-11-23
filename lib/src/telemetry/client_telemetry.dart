// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import '../backend/http_transport.dart';
import '../management/management_transport.dart';
import '../models/http_request.dart';
import '../models/user.dart';
import 'telemetry.dart';
import 'telemetry_config.dart';

/// Reads and writes one value in the platform's secure store.
typedef TelemetryStore = ({
  Future<String?> Function(String key) read,
  Future<void> Function(String key, String? value) write,
});

/// How long a send may take before it is abandoned.
const Duration _sendTimeout = Duration(seconds: 10);

/// How long a read of the user or of the secure store may take before telemetry goes on without it.
const Duration _readTimeout = Duration(seconds: 5);

/// Where the last reported sign-in is kept, so a token refresh or a restart is not reported again.
const String _signInKey = 'telemetry_sign_in';

/// The client's telemetry: sends over the SDK's HTTP transport with the token rules, attributes
/// events to the signed-in user, reports a sign-in once per sign-in session, and observes the
/// management calls.
class ClientTelemetry {
  final Telemetry telemetry;
  final TelemetryConfig _config;
  final Future<User?> Function() _currentUser;
  final TelemetryStore _store;
  final Uri? _base;
  TelemetryIdentity? _identity;

  /// Bumped whenever the cached identity is cleared, so a read that started before cannot restore it.
  int _identityGeneration = 0;

  /// The sign-in check in progress, if any. Each check starts after the one before it, so
  /// overlapping calls cannot both find the sign-in unreported.
  Future<void>? _signIns;

  ClientTelemetry._(this.telemetry, this._config, this._currentUser, this._store, this._base);

  /// Builds the telemetry for a configuration, or returns `null` when it is off or its endpoint
  /// cannot be used: events go only over HTTPS (or to a loopback address when [allowLoopback]).
  /// [identityTimeout] bounds the identity read for each event, and [sendTimeout] each send.
  static ClientTelemetry? create(
    TelemetryConfig? config, {
    required String baseUrl,
    required bool backend,
    required bool allowLoopback,
    required HttpTransport transport,
    required Future<String> Function() accessToken,
    required Future<User?> Function() currentUser,
    required TelemetryStore store,
    Duration? identityTimeout,
    Duration? sendTimeout,
  }) {
    if (config == null || !config.isEnabled) return null;
    final endpoint = Uri.tryParse(config.endpoint!.trim());
    if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) return null;
    final loopback = endpoint.host == 'localhost' || endpoint.host == '127.0.0.1' || endpoint.host == '::1';
    if (endpoint.scheme != 'https' && !(allowLoopback && loopback)) return null;

    final base = Uri.tryParse(baseUrl);
    var sending = false;
    late final ClientTelemetry client;
    final telemetry = Telemetry(
      config,
      apiBases: [baseUrl],
      os: _os(),
      identity: () => client._readIdentity(),
      identityTimeout: identityTimeout ?? _readTimeout,
      send: (body) async {
        // At most one send is open: while an abandoned send is still open, a new batch is dropped,
        // so an endpoint that never answers cannot accumulate requests. The marker is set before the
        // first wait, and the time limit covers the token lookup as well as the request. A send
        // whose time ran out while the token was looked up is abandoned before the request starts.
        if (sending) return;
        sending = true;
        var expired = false;
        final request = () async {
          try {
            final headers = {'Content-Type': 'application/json'};
            final token = await _token(config.token, endpoint, base, backend, accessToken);
            if (expired) return;
            if (token != null) headers['Authorization'] = 'Bearer $token';
            await transport('POST', endpoint, headers, body);
          } finally {
            sending = false;
          }
        }();
        unawaited(request.then<void>((_) {}, onError: (Object _) {}));
        await request.timeout(
          sendTimeout ?? _sendTimeout,
          onTimeout: () {
            expired = true;
          },
        );
      },
    );
    client = ClientTelemetry._(telemetry, config, currentUser, store, base);
    return client;
  }

  /// The token the endpoint gets: a configured token only; none when disabled or when sign-in runs
  /// on a backend; the app's own token for an endpoint on the origin of `baseUrl`; else none.
  static Future<String?> _token(
    TelemetryToken setting,
    Uri endpoint,
    Uri? base,
    bool backend,
    Future<String> Function() accessToken,
  ) async {
    if (setting is TelemetryTokenValue) return setting.token.isEmpty ? null : setting.token;
    if (setting == TelemetryToken.none || backend || base == null) return null;
    final sameOrigin = endpoint.scheme == base.scheme && endpoint.host == base.host && endpoint.port == base.port;
    if (!sameOrigin) return null;
    try {
      final token = await accessToken();
      return token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }

  static TelemetryOs? _os() {
    try {
      return (name: Platform.operatingSystem, version: Platform.operatingSystemVersion);
    } catch (_) {
      return null;
    }
  }

  /// Reports a sign-in once per sign-in session, keyed on the user and `auth_time` or `sid`. The
  /// cached identity is cleared at once; the check of the reported sign-in runs after any earlier
  /// call's check has finished.
  Future<void> signedIn([User? user]) {
    _clearIdentity();
    final previous = _signIns;
    final check = previous == null ? _reportSignIn(user) : previous.then((_) => _reportSignIn(user));
    final settled = check.then<void>((_) {}, onError: (Object _) {});
    _signIns = settled;
    unawaited(
      settled.then((_) {
        if (identical(_signIns, settled)) _signIns = null;
      }),
    );
    return check;
  }

  Future<void> _reportSignIn(User? user) async {
    final claims = (user ?? await _safeCurrentUser())?.claims;
    final subject = claims?[_config.userClaim];
    if (subject is! String) return;
    final session = claims?['auth_time'] ?? claims?['sid'] ?? '';
    final key = '$subject:$session';
    try {
      if (await _store.read(_signInKey).timeout(_readTimeout) == key) return;
      await _store.write(_signInKey, key).timeout(_readTimeout);
    } catch (_) {
      // Without the store, a restart may report the sign-in again.
    }
    telemetry.auth(TelemetryAuthAction.signIn);
  }

  /// Reports a sign-out or an ended session, and forgets the reported sign-in. The cached identity
  /// is kept until the event is sent, so it stays attributed after the session is gone. Every wait
  /// is bounded: the identity read and the store by the read time limit, the send by the send time
  /// limit, so a sign-out always goes on to clear the session.
  Future<void> signedOut({bool expired = false}) async {
    telemetry.auth(expired ? TelemetryAuthAction.sessionExpired : TelemetryAuthAction.signOut);
    try {
      await _store.write(_signInKey, null).timeout(_readTimeout);
    } catch (_) {
      // Nothing to forget.
    }
    await telemetry.flush();
    _clearIdentity();
  }

  void _clearIdentity() {
    _identity = null;
    _identityGeneration++;
  }

  /// A fetcher that reports what each management call changes, and otherwise behaves as [inner].
  /// Only the API's own name for the call is read from the response headers; the body is read only
  /// for a failure's error code. A request that opts out with [ManagementRequest.observe], such
  /// as a flow execution, is passed through unreported.
  ManagementFetcher observe(ManagementFetcher inner) => (request) async {
        if (!request.observe) return inner(request);
        final ManagementResponse response;
        try {
          response = await inner(request);
        } catch (error) {
          _safely(() => telemetry.api(request.method, request.url, request.body, ok: false));
          rethrow;
        }
        _safely(
          () => telemetry.api(
            request.method,
            request.url,
            request.body,
            ok: response.ok,
            status: response.statusCode,
            responseBody: response.ok ? null : response.body,
            event: telemetryEventFromHeaders(response.headers),
          ),
        );
        return response;
      };

  /// Reports a request sent through the backend's HTTP client. A failure here never replaces the
  /// request's own outcome.
  void observeHttp(HttpRequestConfig request, {HttpResponseData? response}) =>
      _safely(() => _observeHttp(request, response));

  void _observeHttp(HttpRequestConfig request, HttpResponseData? response) {
    final parsed = Uri.tryParse(request.url);
    // A path goes under `baseUrl`, as the backend's HTTP client sends it.
    final base = _base;
    final url = parsed != null && !parsed.hasScheme && base != null
        ? Uri.tryParse('${base.toString().replaceAll(RegExp(r'/+$'), '')}${request.url}')
        : parsed;
    if (url == null) return;
    final data = request.data;
    final body = data == null ? null : (data is String ? data : jsonEncode(data));
    final status = response?.statusCode;
    final ok = status != null && status >= 200 && status < 300;
    telemetry.api(
      request.method,
      url,
      body,
      ok: ok,
      status: status,
      responseBody: ok ? null : response?.body,
      event: response == null ? null : telemetryEventFromHeaders(response.headers),
    );
  }

  /// Runs a telemetry step; a failure is dropped, so it never reaches the app.
  static void _safely(void Function() step) {
    try {
      step();
    } catch (_) {
      // Telemetry never affects the app.
    }
  }

  Future<User?> _safeCurrentUser() async {
    try {
      return await _currentUser().timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<TelemetryIdentity> _readIdentity() async {
    final cached = _identity;
    if (cached != null) return cached;
    final generation = _identityGeneration;
    final claims = (await _safeCurrentUser())?.claims;
    final user = claims?[_config.userClaim];
    final organization = claims?[_config.organizationClaim];
    final identity = (
      userId: user is String ? user : null,
      organizationId: organization is String ? organization : null,
    );
    if (identity.userId != null && generation == _identityGeneration) _identity = identity;
    return identity;
  }
}
