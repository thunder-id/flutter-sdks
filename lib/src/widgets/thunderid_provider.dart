// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../i18n/thunderid_i18n.dart';
import '../models/preferences.dart';
import '../models/thunderid_config.dart';
import '../models/user.dart';
import '../models/user_profile.dart';
import '../thunderid_client.dart';

/// Provides a [ThunderIDClient] and reactive authentication state to the widget tree.
///
/// Wrap your root widget with [ThunderIDProvider]:
/// ```dart
/// ThunderIDProvider(
///   config: ThunderIDConfig(baseUrl: '...', clientId: '...'),
///   child: MyApp(),
/// )
/// ```
class ThunderIDProvider extends StatefulWidget {
  final ThunderIDConfig config;
  final Widget child;
  final ThunderIDClient? client;

  const ThunderIDProvider({
    super.key,
    required this.config,
    required this.child,
    this.client,
  });

  static ThunderIDState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThunderIDScope>();
    assert(scope != null, 'No ThunderIDProvider found in widget tree');
    return scope!.state;
  }

  @override
  State<ThunderIDProvider> createState() => ThunderIDState();
}

class ThunderIDState extends State<ThunderIDProvider> {
  late final ThunderIDClient client;
  late final ThunderIDI18n i18n;
  bool _initialized = false;
  bool _isLoading = false;
  User? _user;
  String? _error;

  bool get initialized => _initialized;
  bool get isLoading => _isLoading;
  User? get user => _user;
  bool get isSignedIn => _user != null;
  String? get error => _error;
  ThunderIDPreferences? get preferences => widget.config.preferences;

  /// Mirrors [ThunderIDConfig.fetchUserProfile].
  bool get fetchUserProfileEnabled => widget.config.fetchUserProfile;

  @override
  void initState() {
    super.initState();
    client = widget.client ?? ThunderIDClient();
    i18n = ThunderIDI18n(widget.config.preferences?.i18n);
    _init();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      await client.initialize(widget.config).timeout(const Duration(seconds: 15));
      final signedIn = await client.isSignedIn().timeout(const Duration(seconds: 10));
      if (signedIn) {
        _user = await client.getUser().timeout(const Duration(seconds: 10));
        _syncUserProfile();
      }
      _initialized = true;
      _error = null;
    } on TimeoutException {
      _error = 'Initialization timed out. Verify THUNDERID_BASE_URL and that the ThunderID server is reachable.';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> refresh() async {
    if (!_initialized) return;
    setState(() => _isLoading = true);
    try {
      final signedIn = await client.isSignedIn();
      _user = signedIn ? await client.getUser() : null;
      if (signedIn) _syncUserProfile();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Merges [profile]'s attributes into the cached user's claims, so widgets reading
  /// [user] reflect a freshly saved edit without waiting for the next sign-in.
  void mergeUserProfile(UserProfile profile) {
    final current = _user;
    if (current == null || !mounted) return;
    final merged = User({...current.claims, ...profile.attributes});
    setState(() => _user = merged);
    // Write through to the native cache as well: getUser() short-circuits on it,
    // so a later refresh() would otherwise resurrect the pre-merge claims.
    unawaited(client.setCachedUser(merged).catchError((Object _) {}));
  }

  /// Pulls `/users/me` in the background and merges it into [user].
  ///
  /// Deliberately fire-and-forget: sign-in has already succeeded by this point, so a
  /// profile fetch failure must not be surfaced as an auth [error]. The profile view
  /// reports its own load failures.
  void _syncUserProfile() {
    if (!fetchUserProfileEnabled) return;
    unawaited(
      client.getUserProfile().then(mergeUserProfile).catchError((Object _) {}),
    );
  }

  /// Switches the active locale for UI component labels.
  void setLocale(String locale) {
    i18n.setLocale(locale);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _ThunderIDScope(
        state: this,
        user: user,
        isSignedIn: isSignedIn,
        isLoading: isLoading,
        error: error,
        activeLocale: i18n.activeLocale,
        child: widget.child,
      );
}

class _ThunderIDScope extends InheritedWidget {
  final ThunderIDState state;
  final User? user;
  final bool isSignedIn;
  final bool isLoading;
  final String? error;
  final String activeLocale;

  const _ThunderIDScope({
    required this.state,
    required this.user,
    required this.isSignedIn,
    required this.isLoading,
    required this.error,
    required this.activeLocale,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ThunderIDScope oldWidget) =>
      // Compared by identity: merging a profile swaps in a new User whose claims
      // changed while isSignedIn stayed true, and dependents must still rebuild.
      !identical(user, oldWidget.user) ||
      isSignedIn != oldWidget.isSignedIn ||
      isLoading != oldWidget.isLoading ||
      error != oldWidget.error ||
      activeLocale != oldWidget.activeLocale;
}
