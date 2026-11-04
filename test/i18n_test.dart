// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/i18n/built_in_strings.dart';
import 'package:thunderid_flutter/src/i18n/default_strings.dart';
import 'package:thunderid_flutter/src/i18n/thunderid_i18n.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

Set<String> _placeholders(String text) =>
    {for (final match in RegExp(r'\{(\w+)\}').allMatches(text)) match.group(1)!.replaceAll('Lower', '')};

void main() {
  test('ships the same locales as the JavaScript SDK', () {
    expect(thunderSupportedLocales, ['en-US', 'fr-FR', 'hi-IN', 'ja-JP', 'pt-BR', 'pt-PT', 'si-LK', 'ta-IN', 'te-IN']);
    expect(thunderBuiltInBundles.keys, thunderSupportedLocales);
  });

  for (final locale in thunderSupportedLocales.skip(1)) {
    test('$locale translates every key and keeps its placeholders', () {
      final bundle = thunderBuiltInBundles[locale]!;
      expect(bundle.keys.toSet(), thunderDefaultStrings.keys.toSet());
      thunderDefaultStrings.forEach((key, english) {
        expect(bundle[key]!.trim(), isNotEmpty, reason: '$locale $key');
        expect(
          _placeholders(english).difference({'resourceServer'}),
          _placeholders(bundle[key]!).intersection(_placeholders(english)),
          reason: '$locale $key',
        );
      });
    });
  }

  group('ThunderIDI18n', () {
    test('resolves a built-in locale, by tag or by language', () {
      final i18n = ThunderIDI18n(const I18nPreferences(language: 'fr-FR'));
      expect(i18n.resolve('admin.roles.permissions.title'), 'Autorisations');
      i18n.setLocale('ja');
      expect(i18n.resolve('admin.roles.permissions.title'), '権限');
      i18n.setLocale('pt_br');
      expect(i18n.resolve('admin.roles.permissions.add'), 'Adicionar permissão');
    });

    test('lets a custom bundle override a built-in string', () {
      final i18n = ThunderIDI18n(
        const I18nPreferences(
          language: 'fr-FR',
          bundles: {
            'fr-FR': {'signIn.button': 'Connexion'},
          },
        ),
      );
      expect(i18n.resolve('signIn.button'), 'Connexion');
      expect(i18n.resolve('signOut.button'), 'Se déconnecter');
    });

    test('falls back to the fallback locale, then to English', () {
      final i18n = ThunderIDI18n(const I18nPreferences(language: 'es-ES', fallbackLanguage: 'pt-PT'));
      expect(i18n.resolve('signIn.button'), 'Iniciar Sessão');
      expect(i18n.resolve('no.such.key'), 'no.such.key');
      expect(ThunderIDI18n(const I18nPreferences(language: 'es-ES')).resolve('signIn.button'), 'Sign In');
    });
  });

  testWidgets('management components use the built-in bundle of preferences.i18n.language', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BaseRolePermissions(
            permissions: [],
            preferences: ThunderIDPreferences(i18n: I18nPreferences(language: 'si-LK')),
          ),
        ),
      ),
    );
    expect(find.text(thunderBuiltInBundles['si-LK']!['admin.roles.permissions.title']!), findsOneWidget);
  });
}
