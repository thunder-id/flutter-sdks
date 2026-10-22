// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../../i18n/default_strings.dart';
import '../../../models/preferences.dart';
import '../../thunderid_provider.dart';

// Package-internal (not exported): theme tokens and translation for the admin components.

/// Colors the admin components draw with.
///
/// Resolved from `preferences.theme`: `mode` picks the light or dark set (`auto`, the default,
/// follows the platform brightness), and `overrides` replaces individual tokens using the same
/// shape as the JavaScript SDK's theme, e.g. `{'colors': {'primary': {'main': '#1A73E8'}}}`. An
/// override only has to name the tokens it changes.
class AdminColors {
  final Color background;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color border;
  final Color primary;
  final Color onPrimary;
  final Color error;
  final Color onError;
  final Color errorBackground;

  const AdminColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.error,
    required this.onError,
    required this.errorBackground,
  });

  static const light = AdminColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F8),
    text: Color(0xFF1F1F1F),
    textSecondary: Color(0xFF5F6368),
    border: Color(0xFFDADCE0),
    primary: Color(0xFF1A56DB),
    onPrimary: Color(0xFFFFFFFF),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorBackground: Color(0xFFFCEEEE),
  );

  static const dark = AdminColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    text: Color(0xFFF2F2F2),
    textSecondary: Color(0xFFB0B0B0),
    border: Color(0xFF3C3C3C),
    primary: Color(0xFF8AB4F8),
    onPrimary: Color(0xFF0B1A33),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF3B0A08),
    errorBackground: Color(0xFF3B1716),
  );

  AdminColors _withOverrides(Map<String, dynamic>? overrides) {
    final colors = overrides?['colors'];
    if (colors is! Map) return this;
    Color pick(Color current, List<String> path) {
      Object? node = colors;
      for (final segment in path) {
        node = node is Map ? node[segment] : null;
      }
      return node is String ? (parseHexColor(node) ?? current) : current;
    }

    return AdminColors(
      background: pick(background, ['background', 'body', 'main']),
      surface: pick(surface, ['background', 'surface']),
      text: pick(text, ['text', 'primary']),
      textSecondary: pick(textSecondary, ['text', 'secondary']),
      border: pick(border, ['border']),
      primary: pick(primary, ['primary', 'main']),
      onPrimary: pick(onPrimary, ['primary', 'contrastText']),
      error: pick(error, ['error', 'main']),
      onError: pick(onError, ['error', 'contrastText']),
      errorBackground: pick(errorBackground, ['error', 'light']),
    );
  }
}

/// Parses `#RGB`, `#RRGGBB`, or `#AARRGGBB`; returns `null` for anything else.
Color? parseHexColor(String value) {
  var hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Theme and translation for one admin component, resolved from the component's own
/// `preferences` over the [ThunderIDProvider]'s. Works without a provider, so the `Base`
/// components can be used on their own.
class AdminContext {
  final AdminColors colors;
  final String Function(String key) _resolve;

  const AdminContext._(this.colors, this._resolve);

  factory AdminContext.of(BuildContext context, [ThunderIDPreferences? preferences]) {
    final provider = ThunderIDProvider.maybeOf(context);
    final providerTheme = provider?.preferences?.theme;
    final localTheme = preferences?.theme;
    final mode = localTheme?.mode ?? providerTheme?.mode ?? 'auto';
    final dark = mode == 'dark' ||
        (mode != 'light' && MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark);
    final colors = (dark ? AdminColors.dark : AdminColors.light)
        ._withOverrides(providerTheme?.overrides)
        ._withOverrides(localTheme?.overrides);

    final local = preferences?.i18n;
    final providerI18n = provider?.i18n;
    String resolve(String key) {
      if (local != null) {
        final locale = local.language ?? providerI18n?.activeLocale ?? local.fallbackLanguage;
        final value = local.bundles[locale]?[key] ?? local.bundles[local.fallbackLanguage]?[key];
        if (value != null) return value;
      }
      return providerI18n?.resolve(key) ?? thunderDefaultStrings[key] ?? key;
    }

    return AdminContext._(colors, resolve);
  }

  /// Translates [key], substituting `{param}` placeholders from [params].
  String t(String key, [Map<String, String> params = const {}]) {
    var value = _resolve(key);
    params.forEach((name, replacement) => value = value.replaceAll('{$name}', replacement));
    return value;
  }

  /// The translated label of an identity type wire value, e.g. `user` -> `User`.
  String identityType(String type) => t('admin.common.identity_types.$type');
}
