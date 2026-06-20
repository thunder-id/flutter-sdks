/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import 'dart:async';

import 'package:flutter/widgets.dart';
import '../thunderid_client.dart';
import '../models/thunderid_config.dart';
import '../models/preferences.dart';
import '../models/user.dart';
import '../i18n/thunderid_i18n.dart';

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
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Switches the active locale for UI component labels.
  void setLocale(String locale) {
    i18n.setLocale(locale);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _ThunderIDScope(
        state: this,
        isSignedIn: isSignedIn,
        isLoading: isLoading,
        error: error,
        activeLocale: i18n.activeLocale,
        child: widget.child,
      );
}

class _ThunderIDScope extends InheritedWidget {
  final ThunderIDState state;
  final bool isSignedIn;
  final bool isLoading;
  final String? error;
  final String activeLocale;

  const _ThunderIDScope({
    required this.state,
    required this.isSignedIn,
    required this.isLoading,
    required this.error,
    required this.activeLocale,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ThunderIDScope oldWidget) =>
      isSignedIn != oldWidget.isSignedIn ||
      isLoading != oldWidget.isLoading ||
      error != oldWidget.error ||
      activeLocale != oldWidget.activeLocale;
}
