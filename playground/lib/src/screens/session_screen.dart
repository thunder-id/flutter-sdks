// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import '../config.dart';
import '../event_log.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'logs_screen.dart';

/// Session inspector: user card, token countdown, refresh / sign out, tokens, claims, granted
/// permissions, events.
class SessionScreen extends StatefulWidget {
  final PlaygroundConfig config;
  final VoidCallback onOpenLogs;

  const SessionScreen({super.key, required this.config, required this.onOpenLogs});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

enum _Tab { tokens, claims, permissions, events }

class _SessionScreenState extends State<SessionScreen> {
  final _log = EventLog.instance;
  _Tab _tab = _Tab.tokens;
  String? _accessToken;
  Map<String, dynamic> _claims = const {};
  String? _tokenError;
  bool _reveal = false;
  bool _busy = false;
  Timer? _ticker;
  String? _loadedFor;

  /// The SDK's permission state for the current session; replaced when the session changes.
  GrantedPermissionsNotifier? _permissions;
  final TextEditingController _required = TextEditingController(text: 'system:user:view');

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _accessToken != null) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sdk = ThunderIDProvider.of(context);
    final key = sdk.isSignedIn ? (sdk.user?.sub ?? 'signed-in') : null;
    if (key != _loadedFor) {
      _loadedFor = key;
      _permissions?.dispose();
      _permissions = null;
      if (key == null) {
        _accessToken = null;
        _claims = const {};
        _tokenError = null;
        _reveal = false;
      } else {
        unawaited(_loadToken(sdk));
      }
    }
    // Created signed-out too: it then grants nothing and reads no token.
    _permissions ??= sdk.grantedPermissions();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _permissions?.dispose();
    _required.dispose();
    super.dispose();
  }

  Future<void> _loadToken(ThunderIDState sdk) async {
    try {
      final token = await _log.trace('getAccessToken', () => sdk.client.getAccessToken(), detail: (t) => '${t.length} chars');
      final claims = token.isEmpty
          ? const <String, dynamic>{}
          : await _log.trace('decodeJwtToken', () => sdk.client.decodeJwtToken(token), detail: (c) => '${c.length} claims');
      if (!mounted) return;
      setState(() {
        _accessToken = token.isEmpty ? null : token;
        _claims = claims;
        _tokenError = token.isEmpty ? 'getAccessToken() returned an empty token' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _tokenError = describeError(e));
    }
  }

  Future<void> _refresh(ThunderIDState sdk) async {
    setState(() => _busy = true);
    await sdk.refresh();
    await _loadToken(sdk);
    await _permissions?.reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signOut(ThunderIDState sdk) async {
    setState(() => _busy = true);
    try {
      await _log.trace('signOut', () => sdk.client.signOut(), detail: (r) => 'redirect=$r');
      await sdk.refresh();
    } catch (_) {
      // Logged by trace.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _tab = _Tab.events;
        });
      }
    }
  }

  Future<void> _openFlow(BuildContext context, {required bool signUp}) async {
    final appId = widget.config.applicationId;
    if (appId == null || appId == 'your-application-id') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set THUNDERID_APP_ID in .env to run app-native flows.')),
      );
      return;
    }
    _log.add(signUp ? 'signUp:started' : 'signIn:started', 'mode=app-native appId=$appId');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: signUp
              ? SignUp(
                  applicationId: appId,
                  onSuccess: () {
                    _log.add('signUp:completed', 'account created', kind: LogKind.ok);
                    Navigator.of(sheetContext).pop();
                  },
                  onError: () => _log.add('signUp:error', 'see the form for details', kind: LogKind.error),
                )
              : SignIn(
                  applicationId: appId,
                  onSuccess: (user) {
                    _log.add('signIn:completed', 'sub=${user.sub ?? '-'}', kind: LogKind.ok);
                    Navigator.of(sheetContext).pop();
                  },
                  onError: () => _log.add('signIn:error', 'see the form for details', kind: LogKind.error),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sdk = ThunderIDProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          title: 'Session',
          trailing: StatusPill(
            label: sdk.isLoading
                ? 'Loading'
                : sdk.isSignedIn
                    ? 'Signed in'
                    : 'Signed out',
            color: sdk.isSignedIn ? PlaygroundColors.passSoft : PlaygroundColors.white(0.6),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              if (sdk.isSignedIn) _userCard(sdk) else _signedOutCard(context, sdk),
              const SizedBox(height: 14),
              Segmented<_Tab>(
                options: const [
                  (_Tab.tokens, 'Tokens'),
                  (_Tab.claims, 'Claims'),
                  (_Tab.permissions, 'Access'),
                  (_Tab.events, 'Events'),
                ],
                value: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              const SizedBox(height: 14),
              ...switch (_tab) {
                _Tab.tokens => _tokens(context),
                _Tab.claims => _claimsList(sdk),
                _Tab.permissions => [_permissionsView(sdk)],
                _Tab.events => [EventList(limit: 30, onOpenAll: widget.onOpenLogs)],
              },
            ],
          ),
        ),
      ],
    );
  }

  String _displayName(User user) {
    final full = [user.givenName ?? user['given_name'], user.familyName ?? user['family_name']]
        .whereType<String>()
        .join(' ')
        .trim();
    return user.displayName ?? (full.isNotEmpty ? full : null) ?? user.username ?? user.email ?? user.sub ?? 'Signed-in user';
  }

  Widget _userCard(ThunderIDState sdk) {
    final user = sdk.user!;
    final exp = _claims['exp'];
    final iat = _claims['iat'];
    String expiry = _tokenError ?? 'loading';
    double fraction = 0;
    if (exp is num) {
      final remaining = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000).difference(DateTime.now());
      final lifetime = iat is num ? (exp - iat).toInt() : 3600;
      if (remaining.isNegative) {
        expiry = 'expired';
      } else {
        final mm = remaining.inMinutes.toString().padLeft(2, '0');
        final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        expiry = 'expires in $mm:$ss';
        fraction = lifetime > 0 ? (remaining.inSeconds / lifetime).clamp(0, 1).toDouble() : 0;
      }
    } else if (_accessToken != null) {
      expiry = 'no exp claim';
    }
    final subtitle = [user.email, user['ouHandle'] ?? user['ouName']].whereType<String>().join(' · ');
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const UserAvatar(size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayName(user), style: const TextStyle(fontSize: 16)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: PlaygroundColors.white(0.55))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text('Access token', style: TextStyle(fontSize: 12.5, color: PlaygroundColors.white(0.6)))),
              Flexible(
                child: Text(
                  expiry,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: PlaygroundTheme.monoStyle(size: 12.5, color: PlaygroundColors.white(0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: PlaygroundColors.white(0.08))),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [PlaygroundColors.primary, PlaygroundColors.accent]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _refresh(sdk),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: Colors.white,
                    backgroundColor: PlaygroundColors.white(0.06),
                    side: BorderSide(color: PlaygroundColors.white(0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Refresh token'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _signOut(sdk),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: const Color(0xFFF87171),
                    side: BorderSide(color: PlaygroundColors.fail.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _signedOutCard(BuildContext context, ThunderIDState sdk) {
    final message = sdk.error != null
        ? 'The SDK failed to initialize: ${sdk.error}'
        : sdk.isLoading
            ? 'Initializing the SDK.'
            : 'No active session. Sign in with the app-native flow to inspect tokens and claims.';
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BaseUserAvatar(user: null, size: 48, anonymousSeed: 'playground'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: TextStyle(fontSize: 13.5, height: 1.4, color: PlaygroundColors.white(0.75))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'Sign in',
                  onPressed: sdk.initialized ? () => _openFlow(context, signUp: false) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: sdk.initialized ? () => _openFlow(context, signUp: true) : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: PlaygroundColors.white(0.15)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Create account'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Algorithm from the JWT header, decoded locally (the SDK only decodes the payload).
  String _jwtMeta(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return 'opaque';
    try {
      final header = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts.first))));
      if (header is Map && header['alg'] is String) return 'JWT · ${header['alg']}';
    } catch (_) {
      // Not a JWT header.
    }
    return 'JWT';
  }

  List<Widget> _tokens(BuildContext context) {
    final token = _accessToken;
    final storage = Platform.isIOS
        ? 'Stored by the native ThunderID iOS SDK in the Keychain.'
        : 'Stored by the native ThunderID Android SDK in EncryptedSharedPreferences (Android Keystore).';
    return [
      _TokenCard(
        name: 'Access token',
        meta: token == null ? (_tokenError == null ? 'signed out' : 'error') : _jwtMeta(token),
        value: token,
        emptyText: _tokenError ?? 'Sign in to fetch a token with getAccessToken().',
        reveal: _reveal,
        onToggle: () => setState(() => _reveal = !_reveal),
      ),
      const SizedBox(height: 10),
      const _TokenCard(
        name: 'ID token',
        meta: 'unavailable',
        emptyText: 'thunderid_flutter does not expose the ID token to Dart.',
      ),
      const SizedBox(height: 10),
      const _TokenCard(
        name: 'Refresh token',
        meta: 'unavailable',
        emptyText: 'Held by the native SDK, which refreshes on getAccessToken(). Not exposed to Dart.',
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.lock_outline_rounded, size: 14, color: PlaygroundColors.white(0.5)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(storage, style: TextStyle(fontSize: 12, height: 1.5, color: PlaygroundColors.white(0.5)))),
        ],
      ),
    ];
  }

  /// Granted permissions from [GrantedPermissionsNotifier], and a live [hasPermission] probe.
  Widget _permissionsView(ThunderIDState sdk) {
    final notifier = _permissions;
    if (notifier == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([notifier, _required]),
      builder: (context, _) {
        final granted = notifier.permissions;
        final required = _required.text.trim();
        final allowed = notifier.can(required);
        final covering = granted.where((p) => hasPermission([p], required)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: SectionLabel('Granted · sdk.grantedPermissions()')),
                ChipButton(
                  label: 'Reload',
                  icon: Icons.refresh_rounded,
                  onPressed: notifier.isLoading ? null : () => _log.trace('grantedPermissions.reload', notifier.reload),
                ),
              ],
            ),
            if (!sdk.isSignedIn)
              Text('Sign in to read the permissions in the access token.', style: TextStyle(fontSize: 13, color: PlaygroundColors.white(0.55)))
            else if (notifier.isLoading)
              Text('Reading the access token.', style: TextStyle(fontSize: 13, color: PlaygroundColors.white(0.55)))
            else if (granted.isEmpty)
              Text(
                'The token carries no scope or scopes claim beyond what the server granted. '
                'Request admin permissions with THUNDERID_SCOPES in .env.',
                style: TextStyle(fontSize: 13, height: 1.45, color: PlaygroundColors.white(0.55)),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final permission in granted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: covering.contains(permission)
                            ? PlaygroundColors.pass.withValues(alpha: 0.16)
                            : PlaygroundColors.white(0.05),
                        border: Border.all(color: PlaygroundColors.white(0.08)),
                      ),
                      child: Text(permission, style: PlaygroundTheme.monoStyle(size: 12, color: PlaygroundColors.white(0.85))),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            const SectionLabel('Check · grantedPermissions.can()'),
            TextField(
              controller: _required,
              autocorrect: false,
              style: PlaygroundTheme.monoStyle(size: 13, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'system:user:view',
                filled: true,
                fillColor: PlaygroundColors.white(0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                StatusPill(
                  label: allowed ? 'granted' : 'not granted',
                  color: allowed ? PlaygroundColors.passSoft : PlaygroundColors.failSoft,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    required.isEmpty
                        ? 'An empty requirement is always covered.'
                        : covering.isEmpty
                            ? 'No granted permission covers "$required".'
                            : 'Covered by ${covering.join(', ')}.',
                    style: TextStyle(fontSize: 12.5, color: PlaygroundColors.white(0.6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Decoded from the token, not verified: it only decides what to show. The server still '
              'checks every management request.',
              style: TextStyle(fontSize: 12, height: 1.5, color: PlaygroundColors.white(0.5)),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _claimsList(ThunderIDState sdk) {
    String format(Object? v) => v is String ? v : jsonEncode(v);
    Widget rows(Map<String, dynamic> claims) => ListCard(
          children: [
            for (final e in claims.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key, style: PlaygroundTheme.monoStyle(size: 12.5, color: PlaygroundColors.accent, weight: FontWeight.w500)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        format(e.value),
                        textAlign: TextAlign.right,
                        style: PlaygroundTheme.monoStyle(size: 12.5, color: PlaygroundColors.white(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
    final user = sdk.user;
    if (_claims.isEmpty && user == null) {
      return [
        Text('Sign in to decode claims.', style: TextStyle(fontSize: 13, color: PlaygroundColors.white(0.55))),
      ];
    }
    return [
      if (_claims.isNotEmpty) ...[
        const SectionLabel('Access token · decodeJwtToken()'),
        rows(_claims),
        const SizedBox(height: 14),
      ],
      if (user != null) ...[
        const SectionLabel('User · getUser()'),
        rows(user.claims),
      ],
    ];
  }
}

class _TokenCard extends StatelessWidget {
  final String name;
  final String meta;
  final String? value;
  final String emptyText;
  final bool reveal;
  final VoidCallback? onToggle;

  const _TokenCard({
    required this.name,
    required this.meta,
    required this.emptyText,
    this.value,
    this.reveal = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final token = value;
    final shown = token == null
        ? emptyText
        : reveal
            ? token
            : '${token.substring(0, token.length < 12 ? token.length : 12)}•••••••••••••••••••••••';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: PlaygroundColors.white(0.025),
        border: Border.all(color: PlaygroundColors.white(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              Text(
                meta,
                style: PlaygroundTheme.monoStyle(
                  size: 11.5,
                  color: meta == 'unavailable' ? PlaygroundColors.warnSoft : PlaygroundColors.white(0.5),
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(10)),
            child: Text(
              shown,
              style: token == null
                  ? TextStyle(fontSize: 12.5, height: 1.45, color: PlaygroundColors.white(0.55))
                  : PlaygroundTheme.monoStyle(size: 12, color: const Color(0xFFCFE3FF)).copyWith(height: 1.5),
            ),
          ),
          if (token != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                ChipButton(label: reveal ? 'Hide' : 'Reveal', onPressed: onToggle),
                const SizedBox(width: 8),
                ChipButton(label: 'Copy', onPressed: () => copyToClipboard(context, token, '$name copied')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
