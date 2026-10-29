// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'config.dart';
import 'event_log.dart';
import 'management_endpoints.dart';

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
    } on IAMApiException catch (e) {
      next = CheckState(CheckStatus.fail, _describeApiError(e));
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

/// The management client, once there is a session whose token can authorize it.
ThunderIDManagementClient _management(ThunderIDState sdk) {
  _requireSignedIn(sdk);
  return sdk.management;
}

/// Management failures carry the HTTP status; 403 and 404 get a hint on what to change.
String _describeApiError(IAMApiException e) => switch (e.code) {
      ThunderIDErrorCode.forbidden =>
        'HTTP 403 from ${e.operation}: the access token lacks the permission. Request it with THUNDERID_SCOPES.',
      ThunderIDErrorCode.notFound =>
        'HTTP 404 from ${e.operation}: no such resource, or the collection URL is wrong (see the endpoints check).',
      ThunderIDErrorCode.networkError => '${e.operation}: the management API could not be reached.',
      _ => describeError(e),
    };

String _pageDetail(ManagementPage<Object?> page) => '${page.items.length} of ${page.totalResults}';

/// The first agent, which the agent relationship checks read from.
Future<Agent> _firstAgent(ThunderIDManagementClient management) async {
  final page = await _log.trace('getAgents', () => management.getAgents(limit: 1), detail: _pageDetail);
  if (page.items.isEmpty) throw const CheckSkipped('No agents registered. Create one with the AgentCreate story.');
  return page.items.first;
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
        return CheckResult.pass(
          '${user.claims.length} claims, ${profile.attributes.length} profile attributes',
        );
      } on IAMException catch (e) {
        return CheckResult.pass(
          '${user.claims.length} claims; profile unavailable (${e.code.value})',
        );
      }
    },
  ),
  CheckDef(
    id: 'verification',
    section: 'Session',
    name: 'Attribute verification',
    api: 'UserProfile.verifiedAttributes · client.verifyAttribute()',
    run: (sdk, config) async {
      _requireSignedIn(sdk);
      // Starting a verification sends a message, so this check reads the status and probes the
      // handle rule only. The VerifyAttribute story runs a real verification on request.
      try {
        await _log.trace(
          'verifyAttribute',
          () => sdk.client.verifyAttribute(attribute: 'email', handle: ''),
        );
        return const CheckResult.fail(
          'A verification without a handle was not refused',
        );
      } on IAMException catch (e) {
        if (e.code != ThunderIDErrorCode.invalidInput) rethrow;
      }
      final schema =
          await _log.trace('getUserSchema', () => sdk.client.getUserSchema());
      final profile = await _log.trace(
        'getUserProfile',
        () => sdk.client.getUserProfile(),
        detail: (p) =>
            'verifiedAttributes=${p.verifiedAttributes?.keys.join(',') ?? 'not reported'}',
      );
      final verifiable = schema.keys
          .where(
            (name) => AttributeVerification.isVerifiableAttribute(name, schema),
          )
          .toList();
      final verified = profile.verifiedAttributes;
      if (verified == null) {
        return CheckResult.pass(
          'Handle rule enforced; server does not report verification (${verifiable.length} verifiable)',
        );
      }
      final statuses = verifiable.map(
        (name) =>
            '$name ${verified.containsKey(name) ? 'verified' : 'unverified'}',
      );
      return CheckResult.pass(
        'Handle rule enforced; ${statuses.isEmpty ? 'no verifiable attributes' : statuses.join(', ')}',
      );
    },
  ),
  const CheckDef(
    id: 'orgs',
    section: 'Session',
    name: 'Organizations',
    api: 'not in thunderid_flutter',
    unavailableReason: 'thunderid_flutter has no organizations API.',
  ),

  // ── Management ──────────────────────────────────────────────────────────
  CheckDef(
    id: 'endpoints',
    section: 'Management',
    name: 'Management endpoints',
    api: 'ThunderIDConfig.endpoints · client.management',
    run: (sdk, config) async {
      _requireInitialized(sdk);
      final resolved = await resolveManagementEndpoints(sdk.management);
      final baseHost = Uri.parse(config.baseUrl).authority;
      final lines = <String>['baseUrl (sign-in, tokens, flows): $baseHost'];
      final problems = <String>[];
      for (final endpoint in resolved) {
        final override = config.endpoints[endpoint.key];
        final url = endpoint.url;
        if (url == null) {
          problems.add('${endpoint.key}: ${endpoint.error}');
          continue;
        }
        if (override != null && url != override.replaceFirst(RegExp(r'/+$'), '')) {
          problems.add('${endpoint.key}: override $override was not applied (got $url)');
        }
        lines.add('${endpoint.key} → $url${override != null ? ' (override)' : ''}');
      }
      _log.add('management:endpoints', lines.skip(1).join(' · '), kind: problems.isEmpty ? LogKind.ok : LogKind.error);
      if (problems.isNotEmpty) return CheckResult.fail(problems.join('\n'));
      final overridden = config.endpoints.length;
      lines.add(overridden == 0 ? 'No overrides: every collection resolves under baseUrl.' : '$overridden of ${resolved.length} collections overridden.');
      return CheckResult.pass(lines.join('\n'));
    },
  ),
  CheckDef(
    id: 'errors',
    section: 'Management',
    name: 'Forbidden vs not found',
    api: 'IAMApiException · serverError · toManagementErrorMessage()',
    run: (sdk, config) async {
      // A client with its own fetcher answers 403 and 404 locally, so this needs no server.
      Future<IAMApiException> failWith(int status, {String body = '{"description":"server detail"}'}) async {
        final client = ThunderIDManagementClient(
          baseUrl: config.baseUrl,
          fetcher: (request) async => ManagementResponse(statusCode: status, body: body),
        );
        try {
          await client.getRoles(limit: 1);
        } on IAMApiException catch (e) {
          return e;
        }
        throw StateError('getRoles() succeeded against HTTP $status');
      }

      final forbidden = await failWith(403);
      final missing = await failWith(404);
      if (forbidden.code != ThunderIDErrorCode.forbidden || missing.code != ThunderIDErrorCode.notFound) {
        return CheckResult.fail('Mapped 403 → ${forbidden.code.value}, 404 → ${missing.code.value}');
      }
      final message = toManagementErrorMessage(sdk.i18n.resolve, forbidden, 'admin.roles.list.error');
      if (message == null || message.contains('server detail') || forbidden.message.contains('server detail')) {
        return const CheckResult.fail('The server response body leaked into the error message');
      }
      // A body that is the server's error envelope is kept as serverError, with the server's code.
      final envelope = await failWith(409, body: '{"code":"USR-1027","message":{"defaultValue":"In use"}}');
      if (forbidden.serverError != null || envelope.serverError?.code != 'USR-1027') {
        return CheckResult.fail('serverError: ${forbidden.serverError?.code} / ${envelope.serverError?.code}');
      }
      return CheckResult.pass('403 → forbidden, 404 → notFound, envelope → serverError USR-1027; UI text: "$message"');
    },
  ),
  CheckDef(
    id: 'permissions',
    section: 'Management',
    name: 'Permission checks',
    api: 'client.getGrantedPermissions() · hasPermission() · grantedPermissions()',
    run: (sdk, config) async {
      // The hierarchy rule first: a permission covers itself and every `:` path under it.
      const probes = [
        (['system'], 'system:user:view', true),
        (['system:user'], 'system:user', true),
        (['system:user'], 'system', false),
        (['system:user'], 'system:username', false),
        (<String>[], '', true),
      ];
      for (final (granted, required, expected) in probes) {
        if (hasPermission(granted, required) != expected) {
          return CheckResult.fail('hasPermission($granted, "$required") should be $expected');
        }
      }
      _requireSignedIn(sdk);
      final granted = await _log.trace(
        'getGrantedPermissions',
        () => sdk.client.getGrantedPermissions(),
        detail: (p) => p.isEmpty ? 'none' : p.join(' '),
      );
      final notifier = sdk.grantedPermissions();
      try {
        await notifier.reload();
        if (notifier.permissions.toSet().difference(granted.toSet()).isNotEmpty ||
            notifier.permissions.length != granted.length) {
          return CheckResult.fail('GrantedPermissionsNotifier read ${notifier.permissions}, client read $granted');
        }
      } finally {
        notifier.dispose();
      }
      if (granted.isEmpty) {
        return const CheckResult.pass('Hierarchy rules hold; the token grants no permissions (add them with THUNDERID_SCOPES)');
      }
      final shown = granted.take(4).join(', ');
      return CheckResult.pass('Hierarchy rules hold; ${granted.length} granted: $shown${granted.length > 4 ? ', …' : ''}');
    },
  ),
  CheckDef(
    id: 'groups',
    section: 'Management',
    name: 'Groups',
    api: 'management.getGroups() · getGroup()',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page = await _log.trace('getGroups', () => management.getGroups(limit: 5), detail: _pageDetail);
      if (page.items.isEmpty) return CheckResult.pass('No groups yet (totalResults=${page.totalResults})');
      final group = await _log.trace('getGroup', () => management.getGroup(page.items.first.id), detail: (g) => g.name);
      return CheckResult.pass('${page.totalResults} groups; getGroup("${group.name}") ok');
    },
  ),
  CheckDef(
    id: 'groupMembers',
    section: 'Management',
    name: 'Group members',
    api: 'management.getGroupMembers(groupId)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final groups = await _log.trace('getGroups', () => management.getGroups(limit: 1), detail: _pageDetail);
      if (groups.items.isEmpty) throw const CheckSkipped('No groups. Create one with the GroupCreate story.');
      final group = groups.items.first;
      final members = await _log.trace(
        'getGroupMembers',
        () => management.getGroupMembers(group.id, limit: 20),
        detail: _pageDetail,
      );
      final byType = <String, int>{};
      for (final member in members.items) {
        byType.update(member.type.value, (n) => n + 1, ifAbsent: () => 1);
      }
      final summary = byType.isEmpty ? 'no members' : byType.entries.map((e) => '${e.value} ${e.key}').join(', ');
      return CheckResult.pass('"${group.name}": ${members.totalResults} members ($summary)');
    },
  ),
  CheckDef(
    id: 'roles',
    section: 'Management',
    name: 'Roles',
    api: 'management.getRoles() · getRole() · managementResources.rolesQuery()',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page = await _log.trace('getRoles', () => management.getRoles(limit: 5), detail: _pageDetail);
      // The shared state layer must see the same collection through its own query.
      final query = sdk.managementResources.rolesQuery(limit: 5);
      try {
        final viaState = await query.refetch();
        if (query.error != null) throw query.error!;
        if (viaState?.totalResults != page.totalResults) {
          return CheckResult.fail('rolesQuery saw ${viaState?.totalResults} roles, getRoles saw ${page.totalResults}');
        }
      } finally {
        query.dispose();
      }
      if (page.items.isEmpty) return CheckResult.pass('No roles yet (totalResults=${page.totalResults})');
      final role = await _log.trace('getRole', () => management.getRole(page.items.first.id), detail: (r) => r.name);
      final permissions = role.permissions.fold<int>(0, (n, p) => n + p.permissions.length);
      return CheckResult.pass('${page.totalResults} roles; "${role.name}" grants $permissions permissions; rolesQuery agrees');
    },
  ),
  CheckDef(
    id: 'roleAssignments',
    section: 'Management',
    name: 'Role assignments',
    api: 'management.getRoleAssignments(roleId, type:)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final roles = await _log.trace('getRoles', () => management.getRoles(limit: 1), detail: _pageDetail);
      if (roles.items.isEmpty) throw const CheckSkipped('No roles. Create one with the RoleCreate story.');
      final role = roles.items.first;
      final all = await _log.trace('getRoleAssignments', () => management.getRoleAssignments(role.id), detail: _pageDetail);
      final users = await _log.trace(
        'getRoleAssignments(type: user)',
        () => management.getRoleAssignments(role.id, type: RoleAssigneeType.user),
        detail: _pageDetail,
      );
      if (users.items.any((a) => a.type != RoleAssigneeType.user)) {
        return const CheckResult.fail('The type filter returned assignees of other types');
      }
      return CheckResult.pass('"${role.name}": ${all.totalResults} assignees, ${users.totalResults} of them users');
    },
  ),
  CheckDef(
    id: 'userGroups',
    section: 'Management',
    name: 'User groups (signed-in user)',
    api: 'management.getUserGroups(userId)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final userId = sdk.user?.sub;
      if (userId == null || userId.isEmpty) throw const CheckSkipped('The signed-in user has no sub claim.');
      final page = await _log.trace('getUserGroups', () => management.getUserGroups(userId), detail: _pageDetail);
      final names = page.items.map((g) => g.name).take(3).join(', ');
      return CheckResult.pass(page.items.isEmpty ? 'Not a member of any group' : '${page.totalResults} groups: $names');
    },
  ),
  CheckDef(
    id: 'userUsages',
    section: 'Management',
    name: 'User usages (signed-in user)',
    api: 'management.getUserUsages(userId)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final userId = sdk.user?.sub;
      if (userId == null || userId.isEmpty) throw const CheckSkipped('The signed-in user has no sub claim.');
      final usages = await _log.trace(
        'getUserUsages',
        () => management.getUserUsages(userId),
        detail: (u) => '${u.count} usages',
      );
      final summary = usages.summary?.entries.map((e) => '${e.value} ${e.key}').join(', ');
      return CheckResult.pass(
        usages.usages.isEmpty ? 'Nothing references the signed-in user' : '${usages.count} usages${summary == null ? '' : ': $summary'}',
      );
    },
  ),
  CheckDef(
    id: 'userTypes',
    section: 'Management',
    name: 'User types',
    api: 'management.getUserTypes() · getUserType(id)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page = await _log.trace('getUserTypes', () => management.getUserTypes(limit: 10), detail: _pageDetail);
      if (page.items.isEmpty) return const CheckResult.pass('No user types defined');
      final first = page.items.first;
      final type = await _log.trace(
        'getUserType',
        () => management.getUserType(first.id),
        detail: (t) => '${t.schema.length} attributes',
      );
      return CheckResult.pass(
        '${page.totalResults} types; "${type.displayName ?? type.handle}" (OU ${type.ouHandle ?? type.ouId}) '
        'has ${type.schema.length} attributes',
      );
    },
  ),
  CheckDef(
    id: 'agentTypes',
    section: 'Management',
    name: 'Agent types',
    api: 'management.getAgentTypes() · getAgentType(id)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page = await _log.trace('getAgentTypes', () => management.getAgentTypes(limit: 10), detail: _pageDetail);
      final names = page.items.map((t) => t.displayName.isEmpty ? t.handle : t.displayName).take(3).join(', ');
      if (page.items.isEmpty) return const CheckResult.pass('No agent types defined');
      final type = await _log.trace(
        'getAgentType',
        () => management.getAgentType(page.items.first.id),
        detail: (t) => '${t.schema.length} attributes',
      );
      return CheckResult.pass('${page.totalResults} types: $names; "${type.handle}" has ${type.schema.length} attributes');
    },
  ),
  CheckDef(
    id: 'applications',
    section: 'Management',
    name: 'Applications',
    api: 'management.getApplications() · getApplication(id)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page = await _log.trace('getApplications', () => management.getApplications(limit: 5), detail: _pageDetail);
      if (page.items.isEmpty) return const CheckResult.pass('No applications registered');
      final application = await _log.trace(
        'getApplication',
        () => management.getApplication(page.items.first.id),
        detail: (a) => a.name,
      );
      final oauth = application.oauth2Config;
      return CheckResult.pass(
        '${page.totalResults} applications; "${application.name}" '
        '${oauth == null ? 'has no OAuth client' : 'grants ${oauth.grantTypes.join(', ')}'}',
      );
    },
  ),
  CheckDef(
    id: 'administrationFlows',
    section: 'Management',
    name: 'Administration flows',
    api: 'management.resolveAdministrationFlows() · AdministrationMode.flow',
    run: (sdk, config) async {
      // Read only: which operations would run a flow in AdministrationMode.flow. Needs a token that
      // may read server configuration and flows.
      final management = _management(sdk);
      final resolved = await _log.trace(
        'resolveAdministrationFlows',
        () => management.resolveAdministrationFlows(AdministrationFlowConfigKey.values),
        detail: (r) => '${r.length} configured',
      );
      if (resolved.isEmpty) {
        return const CheckResult.pass('No administration flows configured: flow mode calls the API directly');
      }
      return CheckResult.pass(
        '${resolved.length} of ${AdministrationFlowConfigKey.values.length} operations run a flow: '
        '${resolved.keys.join(', ')}',
      );
    },
  ),
  CheckDef(
    id: 'organizationUnits',
    section: 'Management',
    name: 'Organization units',
    api: 'management.getOrganizationUnits() · getOrganizationUnitByPath(path) · getOrganizationUnitChildren()',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page =
          await _log.trace('getOrganizationUnits', () => management.getOrganizationUnits(limit: 5), detail: _pageDetail);
      if (page.items.isEmpty) return const CheckResult.pass('No organization units');
      final first = page.items.first;
      final unit = await _log.trace(
        'getOrganizationUnitByPath',
        () => management.getOrganizationUnitByPath(first.handle),
        detail: (u) => u.id,
      );
      final children = await _log.trace(
        'getOrganizationUnitChildren',
        () => management.getOrganizationUnitChildren(path: first.handle, limit: 5),
        detail: _pageDetail,
      );
      return CheckResult.pass(
        '${page.totalResults} root units; "${unit.name}" (${unit.handle}) has ${children.totalResults} children',
      );
    },
  ),
  CheckDef(
    id: 'resourceServers',
    section: 'Management',
    name: 'Resource servers',
    api: 'management.getResourceServers() · getResources(id) · getActions(id)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final page =
          await _log.trace('getResourceServers', () => management.getResourceServers(limit: 5), detail: _pageDetail);
      if (page.items.isEmpty) return const CheckResult.pass('No resource servers');
      final server = page.items.first;
      final resources =
          await _log.trace('getResources', () => management.getResources(server.id, limit: 5), detail: _pageDetail);
      final actions = await _log.trace('getActions', () => management.getActions(server.id, limit: 5), detail: _pageDetail);
      return CheckResult.pass(
        '${page.totalResults} servers; "${server.name}" has ${resources.totalResults} resources and '
        '${actions.totalResults} actions',
      );
    },
  ),
  CheckDef(
    id: 'connectionsAndFlows',
    section: 'Management',
    name: 'Connections and flows',
    api: 'management.getConnections() · getConnectionsMeta() · getFlows() · getFlowVersions(id)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final connections =
          await _log.trace('getConnections', () => management.getConnections(limit: 5), detail: _pageDetail);
      final meta = await _log.trace(
        'getConnectionsMeta',
        management.getConnectionsMeta,
        detail: (m) => '${m.vendors.length} vendors',
      );
      final flows = await _log.trace('getFlows', () => management.getFlows(limit: 5), detail: _pageDetail);
      var versions = '';
      if (flows.items.isNotEmpty) {
        final history = await _log.trace(
          'getFlowVersions',
          () => management.getFlowVersions(flows.items.first.id),
          detail: (v) => '${v.totalVersions} versions',
        );
        versions = '; "${flows.items.first.name}" has ${history.totalVersions} versions';
      }
      return CheckResult.pass(
        '${connections.totalResults} connections (${meta.vendors.length} vendors); '
        '${flows.totalResults} flows$versions',
      );
    },
  ),
  CheckDef(
    id: 'designAndTranslations',
    section: 'Management',
    name: 'Design, translations and templates',
    api: 'management.getThemes() · getLayouts() · getLanguages() · getNotificationTemplates(channel)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final themes = await _log.trace('getThemes', () => management.getThemes(limit: 5), detail: _pageDetail);
      final layouts = await _log.trace('getLayouts', () => management.getLayouts(limit: 5), detail: _pageDetail);
      final languages =
          await _log.trace('getLanguages', management.getLanguages, detail: (l) => '${l.length} languages');
      final templates = await _log.trace(
        'getNotificationTemplates',
        () => management.getNotificationTemplates(NotificationChannel.email, limit: 5),
        detail: _pageDetail,
      );
      return CheckResult.pass(
        '${themes.totalResults} themes, ${layouts.totalResults} layouts, languages ${languages.join(', ')}, '
        '${templates.totalResults} email templates',
      );
    },
  ),
  CheckDef(
    id: 'configurationAndGateways',
    section: 'Management',
    name: 'Server configuration, variables and gateways',
    api: 'management.getServerConfigs() · getVariables() · getSecrets() · getGateways() · getConfigurationVersions()',
    run: (sdk, config) async {
      // Read only. Secrets come back without their values.
      final management = _management(sdk);
      final sections =
          await _log.trace('getServerConfigs', management.getServerConfigs, detail: (n) => '${n.length} sections');
      final variables = await _log.trace('getVariables', () => management.getVariables(limit: 5), detail: _pageDetail);
      final secrets = await _log.trace('getSecrets', () => management.getSecrets(limit: 5), detail: _pageDetail);
      final gateways =
          await _log.trace('getGateways', management.getGateways, detail: (g) => '${g.length} gateways');
      final versions = await _log.trace(
        'getConfigurationVersions',
        management.getConfigurationVersions,
        detail: (v) => '${v.length} versions',
      );
      return CheckResult.pass(
        '${sections.length} config sections, ${variables.totalResults} variables, ${secrets.totalResults} secrets, '
        '${gateways.length} gateways, ${versions.length} configuration versions',
      );
    },
  ),
  CheckDef(
    id: 'agentGroups',
    section: 'Management',
    name: 'Agent groups',
    api: 'management.getAgents() · getAgentGroups(agentId)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final agent = await _firstAgent(management);
      final page = await _log.trace('getAgentGroups', () => management.getAgentGroups(agent.id), detail: _pageDetail);
      return CheckResult.pass('"${agent.name}" is in ${page.totalResults} groups');
    },
  ),
  CheckDef(
    id: 'agentRoles',
    section: 'Management',
    name: 'Agent roles',
    api: 'management.getAgents() · getAgentRoles(agentId)',
    run: (sdk, config) async {
      final management = _management(sdk);
      final agent = await _firstAgent(management);
      final page = await _log.trace('getAgentRoles', () => management.getAgentRoles(agent.id), detail: _pageDetail);
      final names = page.items.take(3).join(', ');
      return CheckResult.pass('"${agent.name}" has ${page.totalResults} roles${names.isEmpty ? '' : ': $names'}');
    },
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
