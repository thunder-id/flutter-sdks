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

import '../models/preferences.dart';
import 'default_strings.dart';

/// Resolves localized strings for ThunderID UI components (spec §8.1).
///
/// Resolution order:
/// 1. Custom bundle for active locale (from [I18nPreferences.bundles])
/// 2. Custom bundle for fallback locale
/// 3. Built-in English defaults
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

    final fallback = _prefs?.fallbackLanguage ?? 'en-US';
    final fallbackBundle = bundles[fallback];
    if (fallbackBundle != null && fallbackBundle.containsKey(key)) {
      return fallbackBundle[key]!;
    }

    return thunderDefaultStrings[key] ?? key;
  }
}
