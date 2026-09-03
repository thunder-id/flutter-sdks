// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _screen = 'home';

  @override
  Widget build(BuildContext context) {
    switch (_screen) {
      case 'profile':
        return _ProfileScreen(onBack: () => setState(() => _screen = 'home'));
      case 'token':
        return _TokenScreen(onBack: () => setState(() => _screen = 'home'));
      default:
        return _HomeTabScreen(
          onNavigate: (screen) => setState(() => _screen = screen),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Design constants
// ─────────────────────────────────────────────────────────────────────────────

const _kBlue = Color(0xFF3688FF);
const _kGreen = Color(0xFF2FBD6B);
const _kRed = Color(0xFFD95757);
const _kMuted = Color(0xFF5A7085);
const _kTextDark = Color(0xFF05213F);
const _kCodeBg = Color(0xFF0b1120);

// ─────────────────────────────────────────────────────────────────────────────
// Home tab
// ─────────────────────────────────────────────────────────────────────────────

/// Converts a raw claim value (typically a JSON number bridged from the
/// platform channel) into whole seconds-since-epoch, or `null` if the claim
/// is absent or not numeric.
int? _epochSecondsFromClaim(dynamic value) {
  if (value is num) return value.toInt();
  return null;
}

/// Formats a unix-seconds timestamp as a local `h:mm AM/PM` time string.
String _formatLocalTime(int? epochSeconds) {
  if (epochSeconds == null) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  var hour12 = dt.hour % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $period';
}

/// Formats the number of whole seconds remaining until session expiry.
/// Returns `—` once the claim is unavailable or the session has expired.
String _formatCountdown(int? secondsLeft) {
  if (secondsLeft == null || secondsLeft <= 0) return '—';
  if (secondsLeft < 3600) {
    final minutes = secondsLeft ~/ 60;
    final seconds = secondsLeft % 60;
    return '${minutes}m ${seconds}s';
  }
  final hours = secondsLeft ~/ 3600;
  final minutes = (secondsLeft % 3600) ~/ 60;
  return '${hours}h ${minutes}m';
}

/// Returns a time-of-day-aware greeting, e.g. "Good afternoon, Alex.".
String _greeting(String name) {
  final hour = DateTime.now().hour;
  final String timeOfDay;
  if (hour < 12) {
    timeOfDay = 'morning';
  } else if (hour < 17) {
    timeOfDay = 'afternoon';
  } else {
    timeOfDay = 'evening';
  }
  return 'Good $timeOfDay, $name.';
}

const List<String> _kWeekdayNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _kMonthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats today's date as e.g. "FRIDAY, JULY 31".
String _dateLabel() {
  final now = DateTime.now();
  final weekday = _kWeekdayNames[now.weekday - 1];
  final month = _kMonthNames[now.month - 1];
  return '$weekday, $month ${now.day}'.toUpperCase();
}

class _HomeTabScreen extends StatefulWidget {
  final void Function(String) onNavigate;
  const _HomeTabScreen({required this.onNavigate});

  @override
  State<_HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<_HomeTabScreen> {
  Timer? _ticker;
  int _nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thunder = ThunderIDProvider.of(context);
    final user = thunder.user;
    final givenName = user?['given_name'] as String?;
    final emailPrefix = user?.email?.split('@').first;
    final greetingName = (givenName != null && givenName.isNotEmpty)
        ? givenName
        : (emailPrefix != null && emailPrefix.isNotEmpty)
            ? emailPrefix
            : 'there';
    final authTime = _epochSecondsFromClaim(user?['auth_time']);
    final exp = _epochSecondsFromClaim(user?['exp']);
    final secondsLeft = exp != null ? exp - _nowSeconds : null;
    final organisation = thunder.widget.config.organizationHandle ?? 'Default';

    return Scaffold(
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.only(top: 72, left: 20, right: 20, bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero: avatar + (date/session row, greeting row) ─────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const UserAvatar(size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _dateLabel(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _kMuted,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: _kMuted.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _kGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Session active',
                            style: TextStyle(
                              fontSize: 12,
                              color: _kGreen,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _greeting(greetingName),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _kTextDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // ── Stats row ──────────────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                children: [
                  _StatCell(
                      label: 'Signed in at', value: _formatLocalTime(authTime)),
                  const VerticalDivider(width: 32),
                  _StatCell(
                      label: 'Session expires in',
                      value: _formatCountdown(secondsLeft)),
                  const VerticalDivider(width: 32),
                  _StatCell(label: 'Organisation', value: organisation),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── What's next ────────────────────────────────────────────────
            Text(
              'WHAT\'S NEXT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),

            const _StepRow(
              number: '01',
              title: 'Explore use cases',
              subtitle:
                  'See what you can build — auth flows for web, mobile, APIs, and agents.',
              href: 'https://thunderid.dev/docs/next/use-cases/overview/',
            ),
            const _StepRow(
              number: '02',
              title: 'Learn about flows',
              subtitle:
                  'Understand how authorization code, PKCE, client credentials, and '
                  'device flows work.',
              href:
                  'https://thunderid.dev/docs/next/guides/flows/what-are-flows/',
            ),
            const _StepRow(
              number: '03',
              title: 'Style your experience',
              subtitle:
                  'Customize the login UI, branding, and email templates to match '
                  'your product.',
              href: 'https://thunderid.dev/docs/next/guides/design/overview/',
            ),
            const _StepRow(
              number: '04',
              title: 'Explore SDK APIs',
              subtitle:
                  'Full Flutter SDK reference — widgets, hooks, and configuration options.',
              href: 'https://thunderid.dev/docs/next/sdks/flutter/overview/',
            ),

            const SizedBox(height: 8),

            // ── Action list ────────────────────────────────────────────────
            const Divider(),
            _ActionRow(
              icon: Icons.person_outline,
              label: 'My profile',
              onTap: () => widget.onNavigate('profile'),
            ),
            const Divider(),
            _ActionRow(
              icon: Icons.key_outlined,
              label: 'Token debug',
              onTap: () => widget.onNavigate('token'),
            ),
            const Divider(),

            // ── Sign out ───────────────────────────────────────────────────
            BaseSignOutButton(
              builder: (ctx, isLoading) => InkWell(
                onTap: null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _kRed,
                              ),
                            )
                          : const Icon(Icons.logout, color: _kRed, size: 20),
                      const SizedBox(width: 14),
                      const Text(
                        'Sign out',
                        style: TextStyle(
                          fontSize: 15,
                          color: _kRed,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _kTextDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final String href;
  const _StepRow({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.href,
  });

  Future<void> _open() async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Text(
                  number,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _kBlue,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13, color: _kMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _kMuted, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _kMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: _kTextDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: _kMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile screen
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileScreen extends StatelessWidget {
  final VoidCallback onBack;
  const _ProfileScreen({required this.onBack});

  @override
  Widget build(BuildContext context) {
    // BaseUserProfile drives the /users/me data and edit/save state, so this screen
    // keeps its own card design and adds inline per-field edit controls to it.
    return BaseUserProfile(
      onSaved: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      ),
      builder: (ctx, state) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Back button ────────────────────────────────────────────
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: onBack,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left, color: _kBlue, size: 22),
                      Text(
                        'Home',
                        style: TextStyle(
                          color: _kBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                if (state.isLoading && state.profile == null)
                  const Center(child: CircularProgressIndicator())
                else if (state.error != null)
                  Text(
                    state.error!,
                    style: const TextStyle(fontSize: 13, color: _kRed),
                  )
                else ...[
                  // ── Avatar + name + email ──────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        const UserAvatar(size: 56),
                        const SizedBox(height: 12),
                        Text(
                          state.displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.email ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Account details section ────────────────────────────
                  const _SectionHeader(label: 'ACCOUNT DETAILS'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _kMuted.withValues(alpha: 0.2),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        for (final field in state.fields) ...[
                          if (field != state.fields.first)
                            const Divider(height: 1),
                          _DetailFieldRow(field: field, state: state),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
        color: _kMuted,
      ),
    );
  }
}

/// A single row: pencil to edit, then an inline field with save/cancel.
class _DetailFieldRow extends StatelessWidget {
  final ProfileField field;
  final UserProfileState state;
  const _DetailFieldRow({required this.field, required this.state});

  @override
  Widget build(BuildContext context) {
    final isEditing = state.isEditing(field.name);
    final error = state.fieldError(field.name);
    final value = stringifyFieldValue(field.rawValue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  field.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (isEditing && !field.isReadonly) ...[
                Expanded(
                  child: Semantics(
                    label: field.label,
                    child: TextField(
                      controller: state.controllerFor(field.name),
                      onChanged: (v) => state.setFieldValue(field.name, v),
                      style: const TextStyle(fontSize: 14, color: _kTextDark),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => state.save(field.name),
                  icon: const Icon(Icons.check_circle, color: _kGreen),
                  iconSize: 20,
                  tooltip: 'Save',
                ),
                IconButton(
                  onPressed: () => state.cancel(field.name),
                  icon: const Icon(Icons.cancel, color: _kMuted),
                  iconSize: 20,
                  tooltip: 'Cancel',
                ),
              ] else ...[
                Expanded(
                  child: Text(
                    value.isEmpty ? '-' : value,
                    style: const TextStyle(fontSize: 14, color: _kTextDark),
                  ),
                ),
                if (!field.isReadonly)
                  IconButton(
                    onPressed: () => state.edit(field.name),
                    icon: const Icon(Icons.edit, color: _kBlue),
                    iconSize: 16,
                    tooltip: 'Edit',
                  ),
              ],
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 110, top: 2),
              child: Text(
                error,
                style: const TextStyle(fontSize: 11, color: _kRed),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Token debug screen
// ─────────────────────────────────────────────────────────────────────────────

class _TokenScreen extends StatefulWidget {
  final VoidCallback onBack;
  const _TokenScreen({required this.onBack});

  @override
  State<_TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<_TokenScreen> {
  String? _token;
  String _payload = '{}';
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) {
      _loadToken();
    }
  }

  Future<void> _loadToken() async {
    final thunder = ThunderIDProvider.of(context);
    try {
      final tok = await thunder.client.getAccessToken();
      if (!mounted) return;
      setState(() {
        _token = tok;
        _payload = _decodePayload(tok);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '{}';
      final padded = parts[1].padRight((parts[1].length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return '{}';
    }
  }

  Widget _buildExpiryBadge() {
    try {
      final map = jsonDecode(_payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp == null) return const SizedBox.shrink();
      final expSecs = (exp as num).toInt();
      final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final diffSecs = expSecs - nowSecs;
      if (diffSecs <= 0) {
        return const _Badge(label: 'Expired', color: _kRed);
      }
      final mins = (diffSecs / 60).ceil();
      return _Badge(label: '$mins min', color: _kGreen);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  String _issuer() {
    try {
      final map = jsonDecode(_payload) as Map<String, dynamic>;
      return (map['iss'] as String?) ?? '—';
    } catch (_) {
      return '—';
    }
  }

  String _scopes() {
    try {
      final map = jsonDecode(_payload) as Map<String, dynamic>;
      final scp = map['scp'] ?? map['scope'];
      if (scp == null) return '—';
      if (scp is List) return scp.join(', ');
      return scp.toString();
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back button ──────────────────────────────────────────────
              const SizedBox(height: 16),
              GestureDetector(
                onTap: widget.onBack,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, color: _kBlue, size: 22),
                    Text(
                      'Home',
                      style: TextStyle(
                        color: _kBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Title row ────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Token debug',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kTextDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Access token and claims',
                          style: TextStyle(fontSize: 13, color: _kMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!_loading && _token != null) _buildExpiryBadge(),
                ],
              ),

              const SizedBox(height: 20),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: _kBlue),
                  ),
                )
              else if (_error != null)
                Text(
                  'Error: $_error',
                  style: const TextStyle(color: _kRed, fontSize: 13),
                )
              else ...[
                // ── JWT token display ────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _kCodeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _token != null
                      ? _buildJwtRichText(_token!)
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 8),

                // ── Copy button ──────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      if (_token != null) {
                        await Clipboard.setData(ClipboardData(text: _token!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Token copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.copy, size: 14, color: _kMuted),
                    label: const Text(
                      'Copy',
                      style: TextStyle(fontSize: 13, color: _kMuted),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── JWT Payload section ──────────────────────────────────
                const Text(
                  'JWT PAYLOAD',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kCodeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _prettyJson(_payload),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF79c0ff),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Metadata rows ────────────────────────────────────────
                const Text(
                  'METADATA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _MetaRow(label: 'Issuer', value: _issuer()),
                const Divider(),
                _MetaRow(label: 'Scopes', value: _scopes()),
                const Divider(),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJwtRichText(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return Text(
        token,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Colors.white70,
        ),
      );
    }
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: parts[0],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFFff7b72),
            ),
          ),
          const TextSpan(
            text: '.',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF8b949e),
            ),
          ),
          TextSpan(
            text: parts[1],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF79c0ff),
            ),
          ),
          const TextSpan(
            text: '.',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF8b949e),
            ),
          ),
          TextSpan(
            text: parts[2],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF3fb950),
            ),
          ),
        ],
      ),
    );
  }

  String _prettyJson(String raw) {
    try {
      final obj = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(obj);
    } catch (_) {
      return raw;
    }
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: _kMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: _kTextDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
