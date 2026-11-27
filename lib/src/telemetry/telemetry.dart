// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math';

import 'telemetry_config.dart';
import 'telemetry_encoder.dart';
import 'telemetry_rules.dart';

/// The ids an event is attributed to.
typedef TelemetryIdentity = ({String? userId, String? organizationId});

/// Reads who the current user and organization are.
typedef TelemetryIdentityReader = Future<TelemetryIdentity> Function();

/// Sends one encoded request body. A failure is dropped.
typedef TelemetrySender = Future<void> Function(String body);

/// The auth events the SDK reports.
enum TelemetryAuthAction {
  signIn('sign-in'),
  signInFailed('sign-in-failed'),
  signOut('sign-out'),
  sessionExpired('session-expired');

  final String code;

  const TelemetryAuthAction(this.code);
}

/// The response header in which an API names the event for a call, such as `application.share`.
const String telemetryEventHeader = 'x-telemetry-event';

/// The name an API gave a call in its [telemetryEventHeader] response header, matched without
/// regard to case, or `null`.
String? telemetryEventFromHeaders(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == telemetryEventHeader) return entry.value.trim();
  }
  return null;
}

/// An event reported but not yet attributed to a user and organization.
typedef _Incoming = ({
  TelemetryEventKind kind,
  String name,
  String? route,
  Map<String, String> data,
  String timestamp,
  Future<TelemetryIdentity> identity,
});

const TelemetryIdentity _unattributed = (userId: null, organizationId: null);

/// A batch is sent when it reaches this many events, or after [_flushInterval].
const int _batchSize = 20;
const Duration _flushInterval = Duration(seconds: 5);

/// At most this many events wait for consent; the oldest are dropped first.
const int _maxWaiting = 200;

/// How long an event waits for its identity before it is sent without one.
const Duration _defaultIdentityTimeout = Duration(seconds: 5);

/// Reports what people do in an app: screen views, API events, auth events, links that leave the
/// app and the app's own [track] calls. Events are batched and sent in the background; a failure
/// is dropped and never reaches the app.
class Telemetry {
  final TelemetryConfig config;
  final TelemetryIdentityReader _identity;
  final TelemetrySender _send;
  final TelemetryOs? _os;
  final TelemetryEncoder _encoder;
  final TelemetryApiRules _apiRules;
  final DateTime Function() _now;
  final Duration _identityTimeout;
  final Random _random = Random.secure();

  List<TelemetryEvent> _queue = [];

  /// Events reported but not yet attributed. They count toward [_maxWaiting] before any wait on
  /// the identity or on a send, so a stalled read or send cannot grow memory without bound.
  final List<_Incoming> _incoming = [];
  Timer? _timer;
  Future<void> _pending = Future.value();

  /// Whether a drain of [_incoming] is scheduled or running. One drain serves every event reported
  /// meanwhile, so the work waiting on a stalled read is bounded by [_maxWaiting], not by reports.
  bool _draining = false;
  bool _disposed = false;

  Telemetry(
    this.config, {
    required List<String> apiBases,
    required TelemetryIdentityReader identity,
    required TelemetrySender send,
    TelemetryOs? os,
    DateTime Function()? now,
    Duration identityTimeout = _defaultIdentityTimeout,
  })  : _identity = identity,
        _send = send,
        _os = os,
        _now = now ?? DateTime.now,
        _identityTimeout = identityTimeout,
        _encoder = TelemetryEncoder(config.format, config.mapping),
        _apiRules = TelemetryApiRules(
          [...apiBases, ...config.apiEvents.apis],
          parentActions: config.apiEvents.parentActions,
          kinds: config.apiEvents.kinds,
          addressWords: config.apiEvents.addressWords,
          actions: config.apiEvents.actions,
        );

  /// Reports a screen view from its route pattern, such as `/applications/:id`.
  void page(String pattern) {
    final pages = config.pages;
    if (!pages.enabled || TelemetryNames.matchesAny(pattern, pages.exclude)) return;
    _add(TelemetryEventKind.page, pages.names[pattern] ?? TelemetryNames.pageName(pattern), route: pattern);
  }

  /// Reports an API call the app made through the SDK, when the rules name it. A [status] of
  /// `null` or `0` means the server could not be reached. [event] is the name the API gave the call
  /// in its [telemetryEventHeader] response header, if any; `none` means the call is not reported.
  /// The request body is read only for `skipWhen` and `names` conditions, and the response body only
  /// for a failure's error code; neither is sent.
  void api(
    String method,
    Uri url,
    String? requestBody, {
    required bool ok,
    int? status,
    String? responseBody,
    String? event,
  }) {
    final apiEvents = config.apiEvents;
    if (!apiEvents.enabled) return;
    if (apiEvents.skipWhen.any((field) => TelemetryApiRules.sets(requestBody, field))) return;
    final call = _apiRules.classify(method, url);
    final path = _apiRules.path(url);
    final literal = _apiRules.literalPath(url);
    if (call == null || path == null || literal == null || event == 'none') return;
    final named = _apiName(call, path, method.toUpperCase(), requestBody, event);
    // Checked before `-failed` is added, so an excluded name also stops its failures.
    final exclude = apiEvents.exclude;
    final where = '${url.scheme}://${url.authority}${url.path}';
    if (TelemetryNames.matchesAny(where, exclude) ||
        TelemetryNames.matchesAny(literal, exclude) ||
        TelemetryNames.matchesAny(path, exclude) ||
        TelemetryNames.matchesAny(call.name, exclude) ||
        TelemetryNames.matchesAny(named.name, exclude)) {
      return;
    }
    if (ok) {
      _add(TelemetryEventKind.api, named.name, route: named.route, data: call.data);
    } else {
      _add(
        TelemetryEventKind.api,
        '${named.name}-failed',
        route: named.route,
        data: {...call.data, ...TelemetryApiRules.failureData(status, responseBody)},
      );
    }
  }

  /// The name of an API event and its route, from the first that applies: a configured name for its
  /// method and path, optionally with a body field it must set (`POST /promotions ?origin`), which
  /// names the route too, with each `*` as `{id}`; a configured rename of the rules' name; the name
  /// the API gave in its response header, itself renamed when configured; or the rules' name.
  /// Configuration always comes before the header.
  ({String name, String route}) _apiName(
    TelemetryApiCall call,
    String path,
    String method,
    String? body,
    String? event,
  ) {
    final names = config.apiEvents.names;
    // A key with a body condition is more specific, so it is tried first.
    final keys = [
      ...names.entries.where((entry) => entry.key.contains(' ?')),
      ...names.entries.where((entry) => !entry.key.contains(' ?')),
    ];
    for (final entry in keys) {
      final parts = entry.key.split(' ');
      if (parts.length < 2) continue;
      final condition = parts.length > 2 ? parts[2] : null;
      final field = condition != null && condition.startsWith('?') ? condition.substring(1) : null;
      if (parts[0].toUpperCase() == method &&
          TelemetryNames.matches(path, parts[1]) &&
          (field == null || TelemetryApiRules.sets(body, field))) {
        return (name: entry.value, route: parts[1].replaceAll(RegExp(r'\*\*?'), '{id}'));
      }
    }
    final renamed = names[call.name];
    if (renamed != null) return (name: renamed, route: call.route);
    if (event != null && TelemetryNames.isValidName(event)) return (name: names[event] ?? event, route: call.route);
    return (name: call.name, route: call.route);
  }

  /// Reports an auth event, with codes such as an error code for a failed sign-in.
  void auth(TelemetryAuthAction action, [Map<String, String> data = const {}]) {
    final authEvents = config.authEvents;
    if (!authEvents.enabled || authEvents.exclude.contains(action.code)) return;
    _add(TelemetryEventKind.auth, authEvents.names[action.code] ?? 'auth.${action.code}', data: data);
  }

  /// Reports a link that leaves the app, with its host and path only.
  void link(Uri target) {
    final links = config.links;
    if (!links.enabled || (target.scheme != 'https' && target.scheme != 'http') || target.host.isEmpty) return;
    final where = '${target.scheme}://${target.host}${target.hasPort ? ':${target.port}' : ''}${target.path}';
    if (TelemetryNames.matchesAny(where, links.exclude)) return;
    String? renamed;
    for (final entry in links.names.entries) {
      if (TelemetryNames.matches(where, entry.key)) {
        renamed = entry.value;
        break;
      }
    }
    _add(
      TelemetryEventKind.link,
      renamed ?? 'link.open',
      data: {'host': target.host, 'path': TelemetryNames.linkPath(target.path)},
    );
  }

  /// Reports an event the app names, for what is neither a screen, an API call nor a link. A name
  /// that is not lower-case `<type>.<action>` drops the event, and a [data] value that could be
  /// personal (an email address, a URL, free text) is dropped.
  void track(String name, [Map<String, String> data = const {}]) {
    if (!TelemetryNames.isValidName(name)) return;
    _add(TelemetryEventKind.custom, name, data: TelemetryNames.safeData(data));
  }

  /// Sends what is waiting now.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _pending = _pending.then((_) => _sendQueue());
    return _pending;
  }

  /// Stops the timer, sending what is waiting when consent allows; otherwise the waiting events are
  /// dropped. Nothing is sent after this.
  Future<void> dispose() {
    _disposed = true;
    return flush().then((_) {
      _timer?.cancel();
      _timer = null;
      _queue = [];
      _incoming.clear();
    });
  }

  void _add(TelemetryEventKind kind, String name, {String? route, Map<String, String> data = const {}}) {
    if (_disposed) return;
    _incoming.add(
      (
        kind: kind,
        name: name,
        route: route,
        data: data,
        timestamp: _isoMillis(_now().toUtc()),
        identity: _readIdentity(),
      ),
    );
    _trim();
    if (_draining) return;
    _draining = true;
    _pending = _pending.then((_) => _drain());
  }

  /// Attributes the waiting events, in order, to the user and organization read when each was
  /// recorded, and queues them. Events reported while it waits are taken by the same drain. An
  /// event stays in [_incoming] while its identity is awaited, so [_trim] can still drop it. A
  /// failure drops the event: telemetry never affects the app.
  Future<void> _drain() async {
    try {
      while (_incoming.isNotEmpty) {
        final event = _incoming.first;
        TelemetryIdentity identity;
        try {
          identity = await event.identity;
        } catch (_) {
          identity = _unattributed;
        }
        // Dropped by [_trim] while its identity was read.
        if (_incoming.isEmpty || _incoming.first != event) continue;
        _incoming.removeAt(0);
        try {
          _queue.add(
            TelemetryEvent(
              id: _newId(),
              name: config.prefix == null || config.prefix!.isEmpty ? event.name : '${config.prefix}.${event.name}',
              kind: event.kind,
              timestamp: event.timestamp,
              data: event.data,
              route: event.route,
              userId: identity.userId,
              organizationId: identity.organizationId,
              os: _os,
              context: config.context,
            ),
          );
        } catch (_) {
          // Dropped.
        }
        _trim();
      }
    } finally {
      _draining = false;
    }
    if (_queue.length >= _batchSize && _consented()) {
      unawaited(flush());
    } else {
      _schedule();
    }
  }

  /// The identity for an event, read when the event is recorded. A failed read, or one that does
  /// not settle within the identity time limit, leaves the event unattributed, which is still worth
  /// having; the limit keeps a stalled read from holding back the events after it, or a sign-out.
  Future<TelemetryIdentity> _readIdentity() {
    try {
      // Typed here first: a reader's future may have a narrower record type than the fallback.
      return _identity()
          .then<TelemetryIdentity>((identity) => identity, onError: (Object _) => _unattributed)
          .timeout(_identityTimeout, onTimeout: () => _unattributed);
    } catch (_) {
      return Future.value(_unattributed);
    }
  }

  /// Keeps at most [_maxWaiting] events, dropping the oldest first.
  void _trim() {
    var excess = _queue.length + _incoming.length - _maxWaiting;
    if (excess <= 0) return;
    final fromQueue = min(excess, _queue.length);
    _queue = _queue.sublist(fromQueue);
    excess -= fromQueue;
    if (excess > 0) _incoming.removeRange(0, excess);
  }

  void _schedule() {
    if (_disposed) return;
    _timer ??= Timer(_flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> _sendQueue() async {
    if (_queue.isEmpty) return;
    if (!_consented()) {
      _schedule();
      return;
    }
    final batch = _queue;
    _queue = [];
    final List<String> bodies;
    try {
      bodies = _encoder.encode(batch);
    } catch (_) {
      // A batch that cannot be encoded is dropped.
      return;
    }
    // One body at a time, so at most one request is open. Consent is checked again before each
    // request after the first, as it may be withdrawn while one is open.
    for (var index = 0; index < bodies.length; index++) {
      if (index > 0 && !_consented()) {
        // Several bodies come only from a mapping that sends each event alone, one body per event.
        _retain(batch.sublist(index));
        return;
      }
      try {
        await _send(bodies[index]);
      } catch (_) {
        // A failure is dropped: telemetry never affects the app.
      }
    }
  }

  /// Puts events that were not sent back in front of the queue, to wait for consent under the
  /// [_maxWaiting] limit, or drops them once telemetry is disposed.
  void _retain(List<TelemetryEvent> unsent) {
    if (_disposed) return;
    _queue = [...unsent, ..._queue];
    _trim();
    _schedule();
  }

  bool _consented() {
    try {
      return config.consent == null || config.consent!();
    } catch (_) {
      return false;
    }
  }

  /// An ISO 8601 time in UTC with milliseconds, such as `2026-01-02T03:04:05.000Z`.
  static String _isoMillis(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-${two(time.day)}'
        'T${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${time.millisecond.toString().padLeft(3, '0')}Z';
  }

  String _newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
