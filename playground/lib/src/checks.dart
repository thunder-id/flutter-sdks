// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'config.dart';
import 'event_log.dart';

enum CheckStatus { idle, running, pass, fail, unavailable }

/// Outcome of a single check run.
class CheckResult {
  final bool passed;
  final String note;

  const CheckResult.pass(this.note) : passed = true;
  const CheckResult.fail(this.note) : passed = false;
}

/// Thrown by a check when its preconditions are not met.
class CheckSkipped implements Exception {
  final String reason;

  const CheckSkipped(this.reason);
}

typedef CheckRunner = Future<CheckResult> Function(ThunderIDState sdk, PlaygroundConfig config);

class CheckDef {
  final String id;
  final String section;
  final String name;

  /// The thunderid_flutter API the check drives.
  final String api;

  /// Set when the SDK has no API for this capability; the check is never run.
  final String? unavailableReason;
  final CheckRunner? run;

  /// Destructive checks (sign out) run last in "Run all".
  final bool runsLast;

  const CheckDef({
    required this.id,
    required this.section,
    required this.name,
    required this.api,
    this.run,
    this.unavailableReason,
    this.runsLast = false,
  });
}

class CheckState {
  final CheckStatus status;
  final String note;

  const CheckState(this.status, [this.note = '']);
}

/// Runs the capability checks against the real SDK and tracks their state.
class ChecksController extends ChangeNotifier {
  final PlaygroundConfig config;
  final Map<String, CheckState> _states = {};

  ChecksController(this.config) {
    for (final def in checkDefs) {
      _states[def.id] = def.unavailableReason != null
          ? CheckState(CheckStatus.unavailable, def.unavailableReason!)
          : const CheckState(CheckStatus.idle);
    }
  }

  bool _runningAll = false;
  bool get runningAll => _runningAll;

  CheckState stateOf(String id) => _states[id]!;

  int get passCount => _states.values.where((s) => s.status == CheckStatus.pass).length;
  int get unavailableCount => _states.values.where((s) => s.status == CheckStatus.unavailable).length;
  int get runnableCount => _states.length - unavailableCount;

  Future<void> runOne(ThunderIDState sdk, CheckDef def) async {
    final run = def.run;
    if (run == null || _states[def.id]!.status == CheckStatus.running) return;
    _states[def.id] = const CheckState(CheckStatus.running);
    notifyListeners();
    CheckState next;
    try {
      final result = await run(sdk, config).timeout(const Duration(seconds: 20));
      next = CheckState(result.passed ? CheckStatus.pass : CheckStatus.fail, result.note);
    } on CheckSkipped catch (e) {
      next = CheckState(CheckStatus.fail, e.reason);
    } on TimeoutException {
      next = const CheckState(CheckStatus.fail, 'Timed out after 20s. Is the ThunderID server reachable?');
    } on MissingPluginException {
      next = const CheckState(CheckStatus.fail, 'The native bridge does not implement this call on this platform.');
    } catch (e) {
      next = CheckState(CheckStatus.fail, describeError(e));
    }
    _states[def.id] = next;
    EventLog.instance.add(
      'check:${def.id}',
      next.status == CheckStatus.pass ? 'pass · ${next.note}' : 'fail · ${next.note}',
      kind: next.status == CheckStatus.pass ? LogKind.ok : LogKind.error,
    );
    notifyListeners();
  }

  Future<void> runAll(ThunderIDState sdk) async {
    if (_runningAll) return;
    _runningAll = true;
    notifyListeners();
    final ordered = [
      ...checkDefs.where((d) => d.run != null && !d.runsLast),
      ...checkDefs.where((d) => d.run != null && d.runsLast),
    ];
    for (final def in ordered) {
      _states[def.id] = const CheckState(CheckStatus.running);
    }
    notifyListeners();
    for (final def in ordered) {
      _states[def.id] = const CheckState(CheckStatus.idle);
      await runOne(sdk, def);
    }
    _runningAll = false;
    notifyListeners();
  }
}

final _log = EventLog.instance;

void _requireInitialized(ThunderIDState sdk) {
  if (!sdk.initialized) {
    throw CheckSkipped(sdk.error == null ? 'SDK is still initializing.' : 'SDK failed to initialize: ${sdk.error}');
  }
}

void _requireSignedIn(ThunderIDState sdk) {
  _requireInitialized(sdk);
  if (!sdk.isSignedIn) throw const CheckSkipped('Requires a signed-in session. Sign in from the Session tab.');
}

String _requireAppId(PlaygroundConfig config) {
  final id = config.applicationId;
  if (id == null || id == 'your-application-id') {
    throw const CheckSkipped('Set THUNDERID_APP_ID in .env.');
  }
  return id;
}

final List<CheckDef> checkDefs = [
  // ── Authentication ──────────────────────────────────────────────────────
  CheckDef(
    id: 'browser',
    section: 'Authentication',
    name: 'Sign in (system browser)',
    api: 'client.buildSignInUrl()',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      if (config.clientId == null) {
        throw const CheckSkipped('Set THUNDERID_CLIENT_ID to enable redirect-based sign-in.');
      }
      final url = await _log.trace('buildSignInUrl', () => sdk.client.buildSignInUrl(), detail: (u) => u);
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return CheckResult.fail('SDK returned an invalid authorize URL: "$url"');
      }
      final params = uri.queryParameters;
      final missing = ['client_id', 'redirect_uri', 'code_challenge'].where((p) => !params.containsKey(p)).toList();
      if (missing.isNotEmpty) return CheckResult.fail('Authorize URL is missing ${missing.join(', ')}');
      return CheckResult.pass('Authorize URL built for ${uri.host}${uri.path}');
    },
  ),
  CheckDef(
    id: 'backend',
    section: 'Authentication',
    name: 'Sign in on a backend',
    api: 'endpoints.backend · client.buildSignInUrl()',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      if (!sdk.client.isBackendMode()) {
        throw const CheckSkipped('Set THUNDERID_BACKEND_URL to sign in through an app backend.');
      }
      final url = await _log.trace('buildSignInUrl', () => sdk.client.buildSignInUrl());
      final uri = Uri.parse(url);
      final params = uri.queryParameters;
      final missing = ['redirect_uri', 'code_challenge'].where((p) => !params.containsKey(p)).toList();
      if (missing.isNotEmpty) return CheckResult.fail('Backend sign-in URL is missing ${missing.join(', ')}');
      if (params['code_challenge_method'] != 'S256') return const CheckResult.fail('PKCE method is not S256');
      try {
        await sdk.client.exchangeToken(const TokenExchangeRequestConfig(subjectToken: 'x', subjectTokenType: 'x'));
        return const CheckResult.fail('exchangeToken() was not refused on a backend');
      } on IAMException catch (e) {
        if (e.code != ThunderIDErrorCode.operationNotSupported) rethrow;
      }
      return CheckResult.pass('Sign-in URL bound to PKCE for ${uri.host}${uri.path}; token operations refused');
    },
  ),
  CheckDef(
    id: 'native',
    section: 'Authentication',
    name: 'Sign in (app-native flow)',
    api: 'client.signIn(EmbeddedSignInPayload)',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      final appId = _requireAppId(config);
      final response = await _log.trace(
        'signIn',
        () => sdk.client.signIn(
          payload: const EmbeddedSignInPayload(actionId: 'init'),
          request: EmbeddedFlowRequestConfig(applicationId: appId),
        ),
        detail: (r) => 'flowStatus=${r.flowStatus.name} stepId=${r.stepId ?? '-'}',
      );
      if (response.flowStatus == FlowStatus.error) {
        return CheckResult.fail(response.failureReason ?? 'Flow returned an error');
      }
      final inputs = (response.data?['inputs'] as List?)?.length ?? 0;
      final actions = (response.data?['actions'] as List?)?.length ?? 0;
      return CheckResult.pass('Flow started: $inputs inputs, $actions actions');
    },
  ),
  CheckDef(
    id: 'passkey',
    section: 'Authentication',
    name: 'Passkey sign-in',
    api: 'client.performPasskeyAuthentication()',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      // Probes the native WebAuthn bridge with request options it must reject. A real ceremony
      // needs a passkeyChallenge from a flow step, which the SignIn widget handles end to end.
      try {
        await _log.trace(
          'performPasskeyAuthentication',
          () => sdk.client.performPasskeyAuthentication(requestOptionsJson: 'playground-probe'),
        );
        return const CheckResult.fail('Native bridge accepted malformed request options');
      } on IAMException catch (e) {
        if (e.code == ThunderIDErrorCode.passkeyNotSupported) {
          return CheckResult.fail('Passkeys are not supported on this device: ${e.message}');
        }
        const passkeyCodes = {
          ThunderIDErrorCode.passkeyFailed,
          ThunderIDErrorCode.passkeyCancelled,
          ThunderIDErrorCode.passkeyNoCredential,
        };
        if (passkeyCodes.contains(e.code)) {
          return CheckResult.pass('Native passkey bridge reachable (${e.code.value} for probe options)');
        }
        rethrow;
      }
    },
  ),
  const CheckDef(
    id: 'biometric',
    section: 'Authentication',
    name: 'Biometric unlock',
    api: 'not in thunderid_flutter',
    unavailableReason: 'thunderid_flutter has no biometric unlock API.',
  ),
  CheckDef(
    id: 'signout',
    section: 'Authentication',
    name: 'Sign out',
    api: 'client.signOut()',
    runsLast: true,
    run: (sdk, config) async {
      _requireSignedIn(sdk);
      await _log.trace('signOut', () => sdk.client.signOut(), detail: (r) => 'redirect=$r');
      await sdk.refresh();
      final still = await sdk.client.isSignedIn();
      return still
          ? const CheckResult.fail('isSignedIn() is still true after signOut()')
          : const CheckResult.pass('Session cleared; isSignedIn() is false');
    },
  ),
  CheckDef(
    id: 'deeplink',
    section: 'Authentication',
    name: 'Redirect callback',
    api: 'client.handleRedirectCallback(url)',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      final redirect = config.afterSignInUrl;
      if (config.clientId == null || redirect == null) {
        throw const CheckSkipped('Set THUNDERID_CLIENT_ID and THUNDERID_AFTER_SIGN_IN_URL in .env.');
      }
      final forged = Uri.parse(redirect).replace(
        queryParameters: {'code': 'playground-probe', 'state': 'playground-probe'},
      );
      try {
        await _log.trace('handleRedirectCallback', () => sdk.client.handleRedirectCallback(forged.toString()));
        return const CheckResult.fail('A forged callback was accepted');
      } on IAMException catch (e) {
        return CheckResult.pass('Forged callback rejected (${e.code.value})');
      }
    },
  ),

  // ── Session ─────────────────────────────────────────────────────────────
  CheckDef(
    id: 'refresh',
    section: 'Session',
    name: 'Token refresh',
    api: 'client.getAccessToken() · native auto refresh',
    run: (sdk, config) async {
      _requireSignedIn(sdk);
      final token = await _log.trace('getAccessToken', () => sdk.client.getAccessToken(), detail: (t) => '${t.length} chars');
      if (token.isEmpty) return const CheckResult.fail('getAccessToken() returned an empty token');
      final claims = await _log.trace('decodeJwtToken', () => sdk.client.decodeJwtToken(token));
      final exp = claims['exp'];
      if (exp is! num) return const CheckResult.pass('Valid access token returned (no exp claim)');
      final remaining = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000).difference(DateTime.now());
      if (remaining.isNegative) return const CheckResult.fail('getAccessToken() returned an expired token');
      return CheckResult.pass('Fresh token, expires in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s');
    },
  ),
  CheckDef(
    id: 'storage',
    section: 'Session',
    name: 'Secure token storage',
    api: 'client.isSignedIn() · Keychain / EncryptedSharedPreferences',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      final signedIn = await _log.trace('isSignedIn', () => sdk.client.isSignedIn(), detail: (v) => '$v');
      if (signedIn != sdk.isSignedIn) {
        return CheckResult.fail('Native store says signedIn=$signedIn, provider says ${sdk.isSignedIn}');
      }
      if (!signedIn) {
        throw const CheckSkipped('No stored session. Sign in, relaunch the app, and run this again.');
      }
      final token = await sdk.client.getAccessToken();
      return token.isEmpty
          ? const CheckResult.fail('Session reported but no token in the native store')
          : const CheckResult.pass('Session read back from the native secure store');
    },
  ),
  CheckDef(
    id: 'user',
    section: 'Session',
    name: 'User info',
    api: 'client.getUser() · getUserProfile()',
    run: (sdk, config) async {
      _requireSignedIn(sdk);
      final user = await _log.trace('getUser', () => sdk.client.getUser(), detail: (u) => 'sub=${u.sub ?? '-'}');
      if (user.claims.isEmpty) return const CheckResult.fail('getUser() returned no claims');
      try {
        final profile = await _log.trace(
          'getUserProfile',
          () => sdk.client.getUserProfile(),
          detail: (p) => '${p.attributes.length} attributes',
        );
        return CheckResult.pass('${user.claims.length} claims, ${profile.attributes.length} profile attributes');
      } on IAMException catch (e) {
        return CheckResult.pass('${user.claims.length} claims; profile unavailable (${e.code.value})');
      }
    },
  ),
  const CheckDef(
    id: 'orgs',
    section: 'Session',
    name: 'Organizations',
    api: 'not in thunderid_flutter',
    unavailableReason: 'thunderid_flutter has no organizations API.',
  ),

  // ── UI ──────────────────────────────────────────────────────────────────
  CheckDef(
    id: 'theme',
    section: 'UI',
    name: 'Theming and dark mode',
    api: 'ThemePreferences · client.getFlowMeta()',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      final mode = sdk.preferences?.theme?.mode;
      if (mode == null) return const CheckResult.fail('No ThemePreferences in the SDK config');
      final appId = _requireAppId(config);
      final meta = await _log.trace(
        'getFlowMeta',
        () => sdk.client.getFlowMeta(appId),
        detail: (m) => 'keys=${m.keys.join(',')}',
      );
      return CheckResult.pass('mode=$mode; flow meta resolved (${meta.length} keys)');
    },
  ),
  CheckDef(
    id: 'i18n',
    section: 'UI',
    name: 'Translations',
    api: 'ThunderIDI18n.resolve() · setLocale()',
    run: (sdk, config) async {
      final previous = sdk.i18n.activeLocale;
      try {
        sdk.setLocale('fr-FR');
        final fr = sdk.i18n.resolve('signIn.button');
        sdk.setLocale('es-ES');
        final es = sdk.i18n.resolve('signIn.button');
        final fallback = sdk.i18n.resolve('signIn.password');
        _log.add('i18n:resolve', 'fr-FR="$fr" es-ES="$es"', kind: LogKind.ok);
        if (fr != playgroundBundles['fr-FR']!['signIn.button'] || es != playgroundBundles['es-ES']!['signIn.button']) {
          return CheckResult.fail('Bundles not applied: fr-FR="$fr", es-ES="$es"');
        }
        if (fallback != 'Password') return CheckResult.fail('Fallback to built-in strings failed: "$fallback"');
        return CheckResult.pass('fr-FR "$fr", es-ES "$es", fallback to built-in English');
      } finally {
        sdk.setLocale(previous);
      }
    },
  ),
];
