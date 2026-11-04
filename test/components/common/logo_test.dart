// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

void main() {
  group('resolveLogoSpec', () {
    test('parses emoji: specs', () {
      final resolved = resolveLogoSpec('emoji:🛡️');
      expect(resolved, isA<EmojiLogo>());
      expect((resolved as EmojiLogo).glyph, '🛡️');
    });

    test('parses avatar: specs with explicit params', () {
      final resolved = resolveLogoSpec(
        'avatar:shape=circle,variant=two_letter,content=Acme,colors=2',
      );
      expect(resolved, isA<AvatarLogo>());
      final avatar = resolved as AvatarLogo;
      expect(avatar.shape, AvatarShape.circle);
      expect(avatar.variant, AvatarVariant.twoLetter);
      expect(avatar.content, 'Acme');
      expect(avatar.colors, 2);
      expect(avatar.bg, isNull);
    });

    test('parses the bg= param', () {
      final resolved = resolveLogoSpec(
        'avatar:variant=one_letter,content=B,bg=#FF5733',
      ) as AvatarLogo;
      expect(resolved.bg, '#FF5733');
    });

    test(
        'avatar: derives content from fallbackSeedText when spec has no content param',
        () {
      final resolved = resolveLogoSpec(
        'avatar:shape=rounded,variant=two_letter,colors=0',
        fallbackSeedText: 'Contoso',
      );
      expect((resolved as AvatarLogo).content, 'CO');
    });

    test('avatar: one_letter derives a single letter from fallbackSeedText',
        () {
      final resolved = resolveLogoSpec(
        'avatar:variant=one_letter,colors=0',
        fallbackSeedText: 'Contoso',
      );
      expect((resolved as AvatarLogo).content, 'C');
    });

    test(
        'avatar: defaults shape to rounded, variant to two_letter, and colors to 0 when omitted/invalid',
        () {
      final resolved = resolveLogoSpec('avatar:content=X') as AvatarLogo;
      expect(resolved.shape, AvatarShape.rounded);
      expect(resolved.variant, AvatarVariant.twoLetter);
      expect(resolved.colors, 0);
    });

    test(
        'parses variant=anonymous_animal with a known content key to a bundled asset',
        () {
      final resolved =
          resolveLogoSpec('avatar:variant=anonymous_animal,content=jackalope');
      expect(resolved, isA<AssetLogo>());
      expect(
        (resolved as AssetLogo).assetPath,
        'packages/thunderid_flutter/assets/logo-icons/anonymous/jackalope.png',
      );
    });

    test(
        'variant=anonymous_animal with an unknown content key falls back to a url logo',
        () {
      final resolved =
          resolveLogoSpec('avatar:variant=anonymous_animal,content=dragon');
      expect(resolved, isA<UrlLogo>());
      expect(
        (resolved as UrlLogo).url,
        'avatar:variant=anonymous_animal,content=dragon',
      );
    });

    test(
        'variant=anonymous_animal derives a deterministic animal from fallbackSeedText',
        () {
      final first = resolveLogoSpec(
        'avatar:variant=anonymous_animal',
        fallbackSeedText: 'Contoso',
      ) as AssetLogo;
      final second = resolveLogoSpec(
        'avatar:variant=anonymous_animal',
        fallbackSeedText: 'Contoso',
      ) as AssetLogo;
      expect(first.assetPath, second.assetPath);
      expect(
        kAnonymousAnimalNames
            .any((name) => first.assetPath.endsWith('$name.png')),
        isTrue,
      );
    });

    test(
        'parses variant=anonymous_entity with a known content key to a bundled asset',
        () {
      final resolved =
          resolveLogoSpec('avatar:variant=anonymous_entity,content=hexagon');
      expect(resolved, isA<AssetLogo>());
      expect(
        (resolved as AssetLogo).assetPath,
        'packages/thunderid_flutter/assets/logo-icons/entity/hexagon.png',
      );
    });

    test(
        'variant=anonymous_entity with an unknown content key falls back to a url logo',
        () {
      final resolved =
          resolveLogoSpec('avatar:variant=anonymous_entity,content=dragon');
      expect(resolved, isA<UrlLogo>());
      expect(
        (resolved as UrlLogo).url,
        'avatar:variant=anonymous_entity,content=dragon',
      );
    });

    test(
        'variant=anonymous_entity derives a deterministic entity icon from fallbackSeedText',
        () {
      final first = resolveLogoSpec(
        'avatar:variant=anonymous_entity',
        fallbackSeedText: 'Contoso',
      ) as AssetLogo;
      final second = resolveLogoSpec(
        'avatar:variant=anonymous_entity',
        fallbackSeedText: 'Contoso',
      ) as AssetLogo;
      expect(first.assetPath, second.assetPath);
      expect(
        kAnonymousEntityNames
            .any((name) => first.assetPath.endsWith('$name.png')),
        isTrue,
      );
    });

    test('bare URL falls back to a url logo', () {
      final resolved = resolveLogoSpec('https://example.com/logo.png');
      expect(resolved, isA<UrlLogo>());
      expect((resolved as UrlLogo).url, 'https://example.com/logo.png');
    });

    test('empty/unrecognized spec falls back to a url logo', () {
      expect(resolveLogoSpec(''), isA<UrlLogo>());
    });
  });

  group('deriveAvatarContent', () {
    test('extracts 1/2 alphanumeric letters, uppercased', () {
      expect(deriveAvatarContent('Zebra Inc', AvatarVariant.twoLetter), 'ZE');
      expect(deriveAvatarContent('Zebra Inc', AvatarVariant.oneLetter), 'Z');
    });

    test('falls back to "A" when the seed has no alphanumeric characters', () {
      expect(deriveAvatarContent('🚀', AvatarVariant.twoLetter), 'A');
    });

    test('hash-picks the same anonymous animal for the same seed', () {
      final first =
          deriveAvatarContent('Contoso', AvatarVariant.anonymousAnimal);
      final second =
          deriveAvatarContent('Contoso', AvatarVariant.anonymousAnimal);
      expect(first, second);
      expect(kAnonymousAnimalNames, contains(first));
    });

    test('picks some valid animal for an empty seed', () {
      final picked = deriveAvatarContent('', AvatarVariant.anonymousAnimal);
      expect(kAnonymousAnimalNames, contains(picked));
    });

    test('hash-picks the same anonymous entity icon for the same seed', () {
      final first =
          deriveAvatarContent('Contoso', AvatarVariant.anonymousEntity);
      final second =
          deriveAvatarContent('Contoso', AvatarVariant.anonymousEntity);
      expect(first, second);
      expect(kAnonymousEntityNames, contains(first));
    });

    test('picks some valid entity icon for an empty seed', () {
      final picked = deriveAvatarContent('', AvatarVariant.anonymousEntity);
      expect(kAnonymousEntityNames, contains(picked));
    });
  });

  group('AvatarLogoRender.forSeed', () {
    // Reference values cross-checked against the web SDK's generateAvatarDataUri.ts algorithm
    // (same hashStr, same 10-entry AVATAR_PALETTES, same idx/angle formulas) to keep the two
    // SDKs bit-for-bit in sync. `content` here is already-derived (final) content, matching the
    // new spec's contract for `AvatarLogoRender.forSeed`.
    test('matches the web SDK reference for ("Acme", 2)', () {
      final render =
          AvatarLogoRender.forSeed('Acme', 2, AvatarVariant.twoLetter);
      expect(render.angleDegrees, 183);
      expect(render.initials, 'AC');
      expect(render.startColor, const Color(0xFFF59E0B));
      expect(render.endColor, const Color(0xFFEA580C));
    });

    test(
        'matches the web SDK reference for ("", 0) using the "App" default seed',
        () {
      final render = AvatarLogoRender.forSeed('', 0, AvatarVariant.twoLetter);
      expect(render.angleDegrees, 168);
      expect(render.initials, 'AP');
      expect(render.startColor, const Color(0xFFEF4444));
      expect(render.endColor, const Color(0xFFB91C1C));
    });

    test(
        'matches the web SDK reference for ("Zebra Inc", -37) — negative colors wrap correctly',
        () {
      final render =
          AvatarLogoRender.forSeed('Zebra Inc', -37, AvatarVariant.twoLetter);
      expect(render.angleDegrees, 191);
      expect(render.initials, 'ZE');
      expect(render.startColor, const Color(0xFF8B5CF6));
      expect(render.endColor, const Color(0xFF6D28D9));
    });

    test(
        'matches the web SDK reference for a seed whose hash has the top bit set',
        () {
      // Hash 3969909691 >= 2^31: JS's `h >> 4` sign-extends here, so an unsigned
      // shift would compute 340 degrees instead of the web SDK's 324.
      final render = AvatarLogoRender.forSeed(
        'SomeReallyLongAppNameThatProducesABigHash12345',
        5,
        AvatarVariant.twoLetter,
      );
      expect(render.angleDegrees, 324);
      expect(render.initials, 'SO');
      expect(render.startColor, const Color(0xFFF59E0B));
      expect(render.endColor, const Color(0xFFEA580C));
    });

    test('truncates to a single letter for AvatarVariant.oneLetter', () {
      final render =
          AvatarLogoRender.forSeed('Acme', 2, AvatarVariant.oneLetter);
      expect(render.initials, 'A');
    });
  });

  group('widgets', () {
    testWidgets('ThunderIDLogo renders an emoji glyph without throwing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ThunderIDLogo(spec: 'emoji:🛡️')),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('🛡️'), findsOneWidget);
    });

    testWidgets(
        'ThunderIDLogo renders an avatar badge with initials without throwing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThunderIDLogo(
              spec:
                  'avatar:shape=circle,variant=two_letter,content=Acme,colors=2',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AvatarLogoBadge), findsOneWidget);
      expect(find.text('AC'), findsOneWidget);
    });

    testWidgets(
        'ThunderIDLogo renders a bundled anonymous animal asset without throwing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThunderIDLogo(
              spec: 'avatar:variant=anonymous_animal,content=jackalope',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
        'ThunderIDLogo renders a bundled anonymous entity asset without throwing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThunderIDLogo(
              spec: 'avatar:variant=anonymous_entity,content=hexagon',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('AvatarLogoBadge always renders its initials text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarLogoBadge(
              content: 'Acme',
              colors: 0,
              shape: AvatarShape.rounded,
              variant: AvatarVariant.twoLetter,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('AC'), findsOneWidget);
    });

    testWidgets(
        'AvatarLogoBadge paints a flat bg color instead of a gradient when set',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarLogoBadge(
              content: 'Acme',
              colors: 0,
              shape: AvatarShape.rounded,
              variant: AvatarVariant.twoLetter,
              bg: '#FF5733',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFFF5733));
      expect(decoration.gradient, isNull);
    });
  });
}
