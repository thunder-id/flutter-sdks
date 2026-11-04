// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'default_strings.dart';
import 'translations/fr_fr.dart';
import 'translations/hi_in.dart';
import 'translations/ja_jp.dart';
import 'translations/pt_br.dart';
import 'translations/pt_pt.dart';
import 'translations/si_lk.dart';
import 'translations/ta_in.dart';
import 'translations/te_in.dart';

/// The locales the SDK ships strings for: the same set as the JavaScript SDK.
const List<String> thunderSupportedLocales = [
  'en-US',
  'fr-FR',
  'hi-IN',
  'ja-JP',
  'pt-BR',
  'pt-PT',
  'si-LK',
  'ta-IN',
  'te-IN',
];

/// The built-in string bundles, keyed by locale.
const Map<String, Map<String, String>> thunderBuiltInBundles = {
  'en-US': thunderDefaultStrings,
  'fr-FR': thunderStringsFrFR,
  'hi-IN': thunderStringsHiIN,
  'ja-JP': thunderStringsJaJP,
  'pt-BR': thunderStringsPtBR,
  'pt-PT': thunderStringsPtPT,
  'si-LK': thunderStringsSiLK,
  'ta-IN': thunderStringsTaIN,
  'te-IN': thunderStringsTeIN,
};

/// The built-in bundle for [locale], or `null` when the SDK ships none for it.
///
/// Matches the tag exactly, then ignoring case and `_`/`-` (`pt_br` is `pt-BR`), then by language
/// alone (`fr` is `fr-FR`; `pt` is the first shipped Portuguese, `pt-BR`).
Map<String, String>? builtInBundleFor(String locale) {
  final exact = thunderBuiltInBundles[locale];
  if (exact != null) return exact;
  final normalized = locale.trim().replaceAll('_', '-').toLowerCase();
  if (normalized.isEmpty) return null;
  for (final tag in thunderSupportedLocales) {
    if (tag.toLowerCase() == normalized) return thunderBuiltInBundles[tag];
  }
  final language = normalized.split('-').first;
  for (final tag in thunderSupportedLocales) {
    if (tag.toLowerCase().split('-').first == language) return thunderBuiltInBundles[tag];
  }
  return null;
}
