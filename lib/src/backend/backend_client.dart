// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../channel/thunderid_channel.dart';
import '../models/backend.dart';
import '../models/http_request.dart';
import '../models/thunderid_error.dart';
import '../models/user.dart';
import 'http_transport.dart';
import 'resolve_backend_endpoints.dart';

/// Header that carries the session handle on every backend call.
const String sessionHandleHeader = 'X-Session-Handle';

/// Secure-store key of the session handle. Brand-free: the store itself is namespaced by vendor.
const String _handleKey = 'backend_session_handle';

/// Secure-store key of the access token for bypassed requests.
const String _tokenKey = 'backend_access_token';

/// The stored token is requested again once it is this close to expiring.
const Duration _tokenRenewalMargin = Duration(seconds: 30);

/// A check on returning to the foreground is skipped when the last one is more recent than this.
const Duration _foregroundCheckThrottle = Duration(seconds: 5);

/// Reads the backend's `error` from a `401` body, such as `session_expired` or `login_required`.
String? backendErrorOf(HttpResponseData response) {
  if (response.statusCode != 401) return null;
  final data = response.data;
  if (data is! Map) return null;
  final error = data['error'];
  return error is String ? error : null;
}

/// Talks to the app's backend when sign-in runs there: starts the session from the sign-in's
/// one-time code, reads, refreshes, and ends it, and gets the access token for bypassed requests.
/// The backend keeps the OAuth tokens; the app holds only an opaque session handle, in the native
/// secure store (Keychain on iOS, EncryptedSharedPreferences on Android).
class BackendClient {
  final ResolvedBackendEndpoints endpoints;
  final ThunderIDChannel _channel;
  final String _vendor;
  final HttpTransport _transport;
  final DateTime Function() _now;
  final void Function() _onSignedOut;

  Future<BackendSession>? _session;
  Future<bool>? _refreshing;
  Future<String>? _tokenRequest;
  bool _hasLoadedSession = false;

  /// Whether the session last seen was signed in, so a later read can tell it has ended.
  bool _wasSignedIn = false;

  String? _handle;
  bool _handleLoaded = false;

  /// The PKCE verifier of the sign-in in progress. Held only in memory, and cleared as soon as a
  /// callback arrives.
  String? _codeVerifier;

  DateTime? _lastCheck;

  BackendClient(
    this.endpoints, {
    required ThunderIDChannel channel,
    required String vendor,
    required HttpTransport transport,
    required DateTime Function() now,
    required void Function() onSignedOut,
  })  : _channel = channel,
        _vendor = vendor,
        _transport = transport,
        _now = now,
        _onSignedOut = onSignedOut;

  /// Whether the first session read is still in flight, so it is not yet known whether the user is
  /// signed in.
  bool isLoading() => !_hasLoadedSession;

  // ── Session ───────────────────────────────────────────────────────────────

  /// Returns the session. The result is cached until a sign-in, sign-out, or refresh changes it,
  /// so repeated sign-in checks do not reach the backend each time.
  Future<BackendSession> getSession({bool reload = false}) {
    if (reload) _session = null;
    return _session ??= _readSession();
  }

  Future<BackendSession> _readSession() async {
    try {
      return await _loadSession();
    } catch (_) {
      // A failed read is not cached, so the next one tries again.
      _session = null;
      rethrow;
    } finally {
      _hasLoadedSession = true;
    }
  }

  /// Records that the session has ended: forgets the handle and the stored access token, and tells
  /// the listener when it had been signed in.
  void markSignedOut() {
    _session = Future.value(const BackendSession.signedOut());
    _hasLoadedSession = true;
    unawaited(_clearStoredState());
    if (_wasSignedIn) {
      _wasSignedIn = false;
      _onSignedOut();
    }
  }

  /// Refreshes the session once, sharing one request between concurrent callers.
  ///
  /// Returns whether the session was refreshed. When it was not, the session is now signed out.
  Future<bool> refresh() {
    return _refreshing ??= _send('POST', endpoints.refresh).then((response) {
      if (response.ok) {
        _session = null;
      } else {
        markSignedOut();
      }
      return response.ok;
    }).whenComplete(() => _refreshing = null);
  }

  /// Asks the backend whether the session is still live. The check neither refreshes the session
  /// nor counts as activity, so it can be polled without keeping an idle session alive.
  ///
  /// Returns whether the session is live. A failed check reports the last known state.
  Future<bool> checkSession() async {
    _lastCheck = _now();
    if (await _readHandle() == null) return false;
    try {
      final response = await _send('GET', endpoints.checkSession);
      if (backendErrorOf(response) == 'login_required') {
        markSignedOut();
        return false;
      }
      final data = response.data;
      if (!response.ok || data is! Map) return _wasSignedIn;
      final isSignedIn = data['isSignedIn'] == true;
      if (!isSignedIn) markSignedOut();
      return isSignedIn;
    } on IAMException {
      return _wasSignedIn;
    }
  }

  /// Watches for the session ending while the app runs: checks it whenever the app comes back to
  /// the foreground, and every [pollSeconds] when that is positive.
  ///
  /// Returns a function that stops watching.
  void Function() watch(int pollSeconds) {
    void checkIfSignedIn() {
      if (_wasSignedIn) unawaited(checkSession());
    }

    final binding = WidgetsFlutterBinding.ensureInitialized();
    final lifecycle = AppLifecycleListener(
      binding: binding,
      onResume: () {
        final last = _lastCheck;
        if (last == null || _now().difference(last) >= _foregroundCheckThrottle) checkIfSignedIn();
      },
    );
    final timer = pollSeconds > 0 ? Timer.periodic(Duration(seconds: pollSeconds), (_) => checkIfSignedIn()) : null;

    return () {
      lifecycle.dispose();
      timer?.cancel();
    };
  }

  // ── Sign-in and sign-out ──────────────────────────────────────────────────

  /// Builds the URL that starts sign-in at the backend, binding it to a new PKCE pair. Open it in
  /// a system browser session; the backend returns to the redirect URI with a one-time
  /// `session_code`, which [handleRedirectCallback] exchanges.
  Future<String> buildSignInUrl() async {
    final pkce = await _channel.invokeMap('generatePkce');
    final verifier = pkce['verifier'];
    final challenge = pkce['challenge'];
    if (verifier is! String || challenge is! String || verifier.isEmpty || challenge.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.unknownError, 'Could not generate a PKCE pair');
    }
    _codeVerifier = verifier;
    return endpoints.signIn.replace(
      queryParameters: {
        ...endpoints.signIn.queryParameters,
        'redirect_uri': endpoints.redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    ).toString();
  }

  /// Completes sign-in from the backend's callback: posts its `session_code` with the verifier
  /// this client generated to the session endpoint, and keeps the handle that comes back.
  ///
  /// A callback with no code, for another redirect URI, or for a sign-in this client did not
  /// start is refused.
  Future<User> handleRedirectCallback(String url) async {
    final verifier = _codeVerifier;
    _codeVerifier = null;
    if (verifier == null) {
      throw const IAMException(ThunderIDErrorCode.invalidGrant, 'No sign-in was started for this callback');
    }

    final callback = Uri.tryParse(url);
    final expected = Uri.parse(endpoints.redirectUri);
    if (callback == null ||
        callback.scheme != expected.scheme ||
        callback.host != expected.host ||
        callback.path != expected.path) {
      throw const IAMException(
        ThunderIDErrorCode.invalidRedirectUri,
        'The callback does not match the configured redirect URI',
      );
    }
    final error = callback.queryParameters['error'];
    if (error != null) {
      throw IAMException(ThunderIDErrorCode.authenticationFailed, 'The backend did not sign the user in: $error');
    }
    final code = callback.queryParameters['session_code'];
    if (code == null || code.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.invalidGrant, 'The callback carries no session code');
    }

    final response = await _send(
      'POST',
      endpoints.session,
      body: jsonEncode({'session_code': code, 'code_verifier': verifier}),
      attachHandle: false,
    );
    final data = response.data;
    if (!response.ok || data is! Map) {
      throw IAMException(
        ThunderIDErrorCode.authenticationFailed,
        'The backend session endpoint returned ${response.statusCode}',
      );
    }
    final Object? handle = data['handle'];
    final session = BackendSession.fromMap(data.cast<String, dynamic>());
    if (handle is! String || handle.isEmpty || !session.isSignedIn) {
      throw const IAMException(ThunderIDErrorCode.authenticationFailed, 'The backend did not start a session');
    }

    // A token from an earlier session must not outlive it.
    await _channel.invoke<void>('deleteSecureValue', _storeArgs(_tokenKey));
    await _channel.invoke<void>('writeSecureValue', _storeArgs(_handleKey, handle));
    _handle = handle;
    _handleLoaded = true;
    _wasSignedIn = true;
    _session = Future.value(session);
    _hasLoadedSession = true;
    return User(session.user ?? const {});
  }

  /// Ends the backend session. Local state is cleared first, so the app is signed out even when
  /// the backend cannot be reached; that failure is still reported.
  ///
  /// Returns the URL that ends the session at the authorization server, or `null` when there was
  /// no session or the backend sent none.
  Future<String?> signOut() async {
    final handle = await _readHandle();
    // Signing out here is not news to anyone, so the listener is not told.
    _wasSignedIn = false;
    _session = Future.value(const BackendSession.signedOut());
    _hasLoadedSession = true;
    await _clearStoredState();
    if (handle == null) return null;

    final response = await _transport('POST', endpoints.signOut, _headers(handle), null);
    if (!response.ok) {
      throw IAMException(
        ThunderIDErrorCode.serverError,
        'The backend sign-out endpoint returned ${response.statusCode}',
      );
    }
    final data = response.data;
    final redirectUrl = data is Map ? data['redirectUrl'] : null;
    return redirectUrl is String && redirectUrl.isNotEmpty ? redirectUrl : null;
  }

  /// Forgets the session on this device without calling the backend.
  Future<void> clearLocalSession() async {
    _wasSignedIn = false;
    _session = Future.value(const BackendSession.signedOut());
    _hasLoadedSession = true;
    await _clearStoredState();
  }

  // ── Access token for bypassed requests ────────────────────────────────────

  /// The access token for requests under `bypass`. Like a client credentials token it has no
  /// refresh token: it is kept in the secure store with the time it was issued, reused until 30
  /// seconds before it expires, then requested again. Concurrent callers share one request.
  ///
  /// [renew] requests a new token even when the stored one is still valid.
  Future<String> getAccessToken({bool renew = false}) async {
    if (!renew) {
      final stored = await _readStoredToken();
      if (stored != null) return stored;
    }
    return _tokenRequest ??= _requestAccessToken().whenComplete(() => _tokenRequest = null);
  }

  Future<String?> _readStoredToken() async {
    final raw = await _channel.invoke<String>('readSecureValue', _storeArgs(_tokenKey));
    if (raw == null) return null;
    try {
      final Object? data = jsonDecode(raw);
      if (data is! Map) return null;
      final token = data['access_token'];
      final createdAt = data['created_at'];
      final expiresIn = data['expires_in'];
      if (token is! String || createdAt is! num || expiresIn is! num) return null;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(createdAt.toInt() + (expiresIn * 1000).toInt());
      return expiresAt.subtract(_tokenRenewalMargin).isAfter(_now()) ? token : null;
    } on FormatException {
      return null;
    }
  }

  Future<String> _requestAccessToken() async {
    if (await _readHandle() == null) {
      throw const IAMException(ThunderIDErrorCode.sessionExpired, 'There is no backend session to get a token for');
    }

    var response = await _send('POST', endpoints.token);
    if (backendErrorOf(response) == 'session_expired' && await refresh()) {
      response = await _send('POST', endpoints.token);
      // A second failure means signed out.
      if (backendErrorOf(response) == 'session_expired') markSignedOut();
    }
    if (backendErrorOf(response) == 'login_required') markSignedOut();

    final data = response.data;
    if (response.statusCode == 401) {
      throw const IAMException(ThunderIDErrorCode.sessionExpired, 'The backend token endpoint returned 401');
    }
    if (!response.ok || data is! Map) {
      throw IAMException(
        ThunderIDErrorCode.serverError,
        'The backend token endpoint returned ${response.statusCode}',
      );
    }
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.serverError, 'The backend token endpoint returned no access token');
    }
    final expiresIn = data['expires_in'];
    // Only what the token response is allowed to carry is kept; a refresh or ID token is dropped.
    final stored = {
      'access_token': token,
      'token_type': data['token_type'],
      'expires_in': expiresIn is num ? expiresIn : num.tryParse('$expiresIn') ?? 0,
      'scope': data['scope'],
      'created_at': _now().millisecondsSinceEpoch,
    };
    await _channel.invoke<void>('writeSecureValue', _storeArgs(_tokenKey, jsonEncode(stored)));
    return token;
  }

  // ── Proxy and bypass ──────────────────────────────────────────────────────

  /// Maps an API URL to its backend proxy URL.
  ///
  /// Returns `null` when the URL is not under the API base, and so cannot be sent with the
  /// session's credentials.
  Uri? toProxyUrl(String url) {
    final apiBaseUrl = endpoints.apiBaseUrl;
    final String rest;
    if (url == apiBaseUrl || url.startsWith('$apiBaseUrl/') || url.startsWith('$apiBaseUrl?')) {
      rest = url.substring(apiBaseUrl.length);
    } else if (url.startsWith('/') && !url.startsWith('//')) {
      rest = url;
    } else {
      return null;
    }
    return Uri.parse('${endpoints.proxy}${rest.startsWith('/') ? rest : '/$rest'}');
  }

  /// Whether a request to this URL skips the proxy and goes straight from the app.
  bool isBypassed(String url) => endpoints.bypassUrls.any(
        (base) => url == base || url.startsWith('$base/') || url.startsWith('$base?'),
      );

  /// Sends a request through the proxy with the session handle.
  Future<HttpResponseData> sendThroughProxy(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    final handle = await _readHandle();
    return _transport(method, url, {...headers, if (handle != null) sessionHandleHeader: handle}, body);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<BackendSession> _loadSession() async {
    if (await _readHandle() == null) return const BackendSession.signedOut();

    var response = await _send('GET', endpoints.session);
    if (backendErrorOf(response) == 'session_expired' && await refresh()) {
      response = await _send('GET', endpoints.session);
    }
    if (response.statusCode == 401) return _signedOutSession();

    final data = response.data;
    if (!response.ok || data is! Map) {
      throw IAMException(
        ThunderIDErrorCode.serverError,
        'The backend session endpoint returned ${response.statusCode}',
      );
    }
    final session = BackendSession.fromMap(data.cast<String, dynamic>());
    if (!session.isSignedIn) return _signedOutSession();
    _wasSignedIn = true;
    return session;
  }

  BackendSession _signedOutSession() {
    if (_wasSignedIn) {
      // Deferred, so the listener sees this read's result in the cache rather than racing it.
      scheduleMicrotask(markSignedOut);
    } else {
      // A handle left from an earlier run whose session has since ended.
      unawaited(_clearStoredState());
    }
    return const BackendSession.signedOut();
  }

  Future<String?> _readHandle() async {
    if (!_handleLoaded) {
      _handle = await _channel.invoke<String>('readSecureValue', _storeArgs(_handleKey));
      _handleLoaded = true;
    }
    return _handle;
  }

  Future<void> _clearStoredState() async {
    _handle = null;
    _handleLoaded = true;
    await _channel.invoke<void>('deleteSecureValue', _storeArgs(_handleKey));
    await _channel.invoke<void>('deleteSecureValue', _storeArgs(_tokenKey));
  }

  Future<HttpResponseData> _send(String method, Uri url, {String? body, bool attachHandle = true}) async {
    final handle = attachHandle ? await _readHandle() : null;
    return _transport(method, url, _headers(handle, hasBody: body != null), body);
  }

  Map<String, String> _headers(String? handle, {bool hasBody = false}) => {
        'Accept': 'application/json',
        if (hasBody) 'Content-Type': 'application/json',
        if (handle != null) sessionHandleHeader: handle,
      };

  Map<String, dynamic> _storeArgs(String key, [String? value]) => {
        'vendor': _vendor,
        'key': key,
        if (value != null) 'value': value,
      };
}
