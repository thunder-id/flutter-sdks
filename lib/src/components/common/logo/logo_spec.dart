// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'avatar_logo.dart';
import 'curated_logo_icons.dart';

/// Background shape an `avatar:` logo is rendered onto.
enum AvatarShape {
  circle,
  rounded,
}

/// What's drawn on top of an `avatar:` logo's background.
enum AvatarVariant {
  /// A generated gradient avatar with a single overlaid letter.
  oneLetter,

  /// A generated gradient avatar with two overlaid letters.
  twoLetter,

  /// One of the curated "anonymous animal" badge icons (a bundled asset image).
  anonymousAnimal,

  /// One of the curated "anonymous entity" badge icons (applications, organizations, resource
  /// servers, agents) — a bundled asset image.
  anonymousEntity,
}

/// Wire-string (snake_case) for an [AvatarShape], as used in the `shape=` spec param.
extension AvatarShapeWire on AvatarShape {
  String get wireValue => switch (this) {
        AvatarShape.circle => 'circle',
        AvatarShape.rounded => 'rounded',
      };
}

/// Wire-string (snake_case) for an [AvatarVariant], as used in the `variant=` spec param.
extension AvatarVariantWire on AvatarVariant {
  String get wireValue => switch (this) {
        AvatarVariant.oneLetter => 'one_letter',
        AvatarVariant.twoLetter => 'two_letter',
        AvatarVariant.anonymousAnimal => 'anonymous_animal',
        AvatarVariant.anonymousEntity => 'anonymous_entity',
      };
}

/// A parsed application logo spec — `emoji:<glyph>`,
/// `avatar:shape=...,variant=...,content=...,colors=...,bg=...`, or a bare URL — resolved into a
/// renderable representation.
///
/// Construct via [resolveLogoSpec]; render with a widget that pattern-matches on the sealed
/// subtypes (e.g. a switch expression).
sealed class ResolvedLogo {
  const ResolvedLogo();
}

/// An `emoji:<glyph>` spec — render [glyph] directly (e.g. in a [Text] widget).
final class EmojiLogo extends ResolvedLogo {
  final String glyph;

  const EmojiLogo(this.glyph);

  @override
  bool operator ==(Object other) => other is EmojiLogo && other.glyph == glyph;

  @override
  int get hashCode => glyph.hashCode;
}

/// An `avatar:shape=...,variant=one_letter|two_letter,content=...,colors=...,bg=...` spec — a
/// deterministically-generated gradient avatar with 1 or 2 overlaid letters. See
/// `AvatarLogoBadge` for the widget that renders this.
///
/// `avatar:` specs whose `variant=anonymous_animal`/`anonymous_entity` resolve to an [AssetLogo]
/// instead (or a [UrlLogo] fallback), since those variants are bundled asset images on this
/// platform, not a generated gradient.
final class AvatarLogo extends ResolvedLogo {
  /// The literal content overlaid on the avatar (1-2 letters, already uppercased/derived — not a
  /// seed to further extract from).
  final String content;

  /// Gradient rotation/palette index (any integer; wraps around the palette).
  final int colors;

  /// Background shape.
  final AvatarShape shape;

  /// Letter-count variant.
  final AvatarVariant variant;

  /// Optional explicit flat background color (e.g. `"#FF5733"`), overriding the derived gradient.
  final String? bg;

  const AvatarLogo({
    required this.content,
    required this.colors,
    required this.shape,
    required this.variant,
    this.bg,
  });

  @override
  bool operator ==(Object other) =>
      other is AvatarLogo &&
      other.content == content &&
      other.colors == colors &&
      other.shape == shape &&
      other.variant == variant &&
      other.bg == bg;

  @override
  int get hashCode => Object.hash(content, colors, shape, variant, bg);
}

/// An `avatar:variant=anonymous_animal,content=<key>` (or `anonymous_entity`) spec resolved to a
/// bundled asset image, identified by its package-relative asset path (e.g.
/// `"packages/thunderid_flutter/assets/logo-icons/anonymous/fox.png"`).
final class AssetLogo extends ResolvedLogo {
  /// Package-relative asset path, suitable for [AssetImage]/`Image.asset`.
  final String assetPath;

  const AssetLogo(this.assetPath);

  @override
  bool operator ==(Object other) =>
      other is AssetLogo && other.assetPath == assetPath;

  @override
  int get hashCode => assetPath.hashCode;
}

/// A plain image URL — either the spec wasn't in a recognized scheme, or it named an
/// `anonymous_animal` key that isn't in the curated set.
final class UrlLogo extends ResolvedLogo {
  final String url;

  const UrlLogo(this.url);

  @override
  bool operator ==(Object other) => other is UrlLogo && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

const String _emojiScheme = 'emoji:';
const String _avatarScheme = 'avatar:';

/// Resolves an application logo spec string into a renderable [ResolvedLogo].
///
/// An unknown `anonymous_animal`/`anonymous_entity` key, or a spec in none of the recognized
/// schemes, falls back to [UrlLogo] so callers can always render *something* without
/// special-casing.
///
/// [fallbackSeedText] seeds an `avatar:` spec's derived content when the spec itself doesn't
/// carry a `content` param (e.g. an app name to keep the avatar in sync as it changes).
///
/// ```dart
/// resolveLogoSpec('emoji:🛡️');   // EmojiLogo('🛡️')
/// resolveLogoSpec('avatar:shape=circle,variant=two_letter,content=BM,colors=2'); // AvatarLogo(...)
/// resolveLogoSpec('avatar:variant=anonymous_animal,content=jackalope');
///   // AssetLogo('packages/thunderid_flutter/assets/logo-icons/anonymous/jackalope.png')
/// resolveLogoSpec('https://example.com/logo.png'); // UrlLogo('https://example.com/logo.png')
/// ```
ResolvedLogo resolveLogoSpec(String spec, {String fallbackSeedText = ''}) {
  if (spec.startsWith(_emojiScheme)) {
    return EmojiLogo(spec.substring(_emojiScheme.length));
  }

  if (spec.startsWith(_avatarScheme)) {
    final params = _parseAvatarParams(spec.substring(_avatarScheme.length));
    final variant = _avatarVariantFrom(params['variant']);
    final rawContent = params['content'];
    final content = (rawContent != null && rawContent.isNotEmpty)
        ? rawContent
        : deriveAvatarContent(fallbackSeedText, variant);

    if (variant == AvatarVariant.anonymousAnimal) {
      final assetPath = anonymousAnimalAssetPath(content);
      return assetPath != null ? AssetLogo(assetPath) : UrlLogo(spec);
    }

    if (variant == AvatarVariant.anonymousEntity) {
      final assetPath = anonymousEntityAssetPath(content);
      return assetPath != null ? AssetLogo(assetPath) : UrlLogo(spec);
    }

    return AvatarLogo(
      content: content,
      colors: int.tryParse(params['colors'] ?? '') ?? 0,
      shape: _avatarShapeFrom(params['shape']),
      variant: variant,
      bg: params['bg'],
    );
  }

  return UrlLogo(spec);
}

AvatarShape _avatarShapeFrom(String? raw) {
  for (final shape in AvatarShape.values) {
    if (shape.wireValue == raw) {
      return shape;
    }
  }
  return AvatarShape.rounded;
}

AvatarVariant _avatarVariantFrom(String? raw) {
  for (final variant in AvatarVariant.values) {
    if (variant.wireValue == raw) {
      return variant;
    }
  }
  return AvatarVariant.twoLetter;
}

Map<String, String> _parseAvatarParams(String raw) {
  final params = <String, String>{};
  for (final pair in raw.split(',')) {
    final parts = pair.split('=');
    final key = parts.first.trim();
    if (key.isEmpty) {
      continue;
    }
    params[key] = parts.skip(1).join('=').trim();
  }
  return params;
}
