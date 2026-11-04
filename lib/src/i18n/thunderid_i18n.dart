// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/preferences.dart';
import 'built_in_strings.dart';
import 'default_strings.dart';

/// Resolves localized strings for ThunderID UI components (spec §8.1).
///
/// Resolution order:
/// 1. Custom bundle for active locale (from [I18nPreferences.bundles])
/// 2. Built-in bundle for active locale (see [thunderSupportedLocales])
/// 3. Custom bundle for fallback locale
/// 4. Built-in bundle for fallback locale
/// 5. Built-in English defaults
class ThunderIDI18n {
  final I18nPreferences? _prefs;
  String _activeLocale;

  ThunderIDI18n(this._prefs) : _activeLocale = _prefs?.language ?? 'en-US';

  String get activeLocale => _activeLocale;

  void setLocale(String locale) {
    _activeLocale = locale;
  }

  String resolve(String key) {
    final bundles = _prefs?.bundles ?? {};

    final activeBundle = bundles[_activeLocale];
    if (activeBundle != null && activeBundle.containsKey(key)) {
      return activeBundle[key]!;
    }

    final builtIn = builtInBundleFor(_activeLocale)?[key];
    if (builtIn != null) return builtIn;

    final fallback = _prefs?.fallbackLanguage ?? 'en-US';
    final fallbackBundle = bundles[fallback];
    if (fallbackBundle != null && fallbackBundle.containsKey(key)) {
      return fallbackBundle[key]!;
    }

    final builtInFallback = builtInBundleFor(fallback)?[key];
    if (builtInFallback != null) return builtInFallback;

    return thunderDefaultStrings[key] ?? key;
  }
}
