// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'curated_logo_icons.dart';
import 'logo_spec.dart';

/// Curated on-brand gradient pairs — `colors` rotates through this set. Must stay in lockstep
/// with `AVATAR_PALETTES` in the web SDK's `generateAvatarDataUri.ts` so the same `(content,
/// colors)` pair renders an identical avatar on every platform.
const List<List<int>> _avatarPalettes = <List<int>>[
  <int>[0xFFFF7300, 0xFFEF4223],
  <int>[0xFF3688FF, 0xFF1D5EB4],
  <int>[0xFF5567D5, 0xFF8B6FE8],
  <int>[0xFF06B6D4, 0xFF0891B2],
  <int>[0xFF10B981, 0xFF059669],
  <int>[0xFFEC4899, 0xFFBE185D],
  <int>[0xFFF59E0B, 0xFFEA580C],
  <int>[0xFF8B5CF6, 0xFF6D28D9],
  <int>[0xFF5CD1FF, 0xFF3688FF],
  <int>[0xFFEF4444, 0xFFB91C1C],
];

final RegExp _alphanumeric = RegExp(r'[A-Za-z0-9]');

/// Derives the literal `content` value for an `avatar:` spec from a raw seed string (e.g. an app
/// name or session id), for callers that only have a seed and not an already-resolved spec —
/// `resolveLogoSpec` uses this to fill in `content` when a spec omits it.
///
/// For [AvatarVariant.oneLetter]/[AvatarVariant.twoLetter], extracts the first 1/2 ASCII
/// alphanumeric characters from [seed], uppercased (falling back to `'A'` when [seed] has none).
///
/// For [AvatarVariant.anonymousAnimal]/[AvatarVariant.anonymousEntity], hash-picks one of
/// [kAnonymousAnimalNames]/[kAnonymousEntityNames] deterministically from [seed] (using the same
/// polynomial hash as the gradient/angle derivation), so the same seed always picks the same
/// name. An empty [seed] still returns *some* valid name, via a random pick.
String deriveAvatarContent(String seed, AvatarVariant variant) {
  switch (variant) {
    case AvatarVariant.oneLetter:
      return _lettersFrom(seed, 1);
    case AvatarVariant.twoLetter:
      return _lettersFrom(seed, 2);
    case AvatarVariant.anonymousAnimal:
      return _pickAnonymousName(kAnonymousAnimalNames, seed);
    case AvatarVariant.anonymousEntity:
      return _pickAnonymousName(kAnonymousEntityNames, seed);
  }
}

String _lettersFrom(String seed, int letterCount) {
  final matches =
      _alphanumeric.allMatches(seed).map((m) => m[0]!).take(letterCount).join();
  return (matches.isEmpty ? 'A' : matches).toUpperCase();
}

String _pickAnonymousName(List<String> names, String seed) {
  final sorted = List<String>.of(names)..sort();
  if (seed.isEmpty) {
    return sorted[math.Random().nextInt(sorted.length)];
  }
  return sorted[_hashStr(seed) % sorted.length];
}

/// 32-bit unsigned polynomial hash: `h = (h * 31 + charCode) mod 2^32`, matching `hashStr` in
/// the web SDK.
int _hashStr(String str) {
  var h = 0;
  for (final unit in str.codeUnits) {
    h = (h * 31 + unit) & 0xFFFFFFFF;
  }
  return h;
}

int _positiveMod(int value, int modulus) =>
    ((value % modulus) + modulus) % modulus;

/// Parses a `bg=` spec param (e.g. `"#FF5733"` or `"#80FF5733"`) into a [Color], or `null` when
/// [hex] is absent/unparseable — in which case callers should fall back to the derived gradient.
Color? _parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) {
    return null;
  }
  var value = hex.startsWith('#') ? hex.substring(1) : hex;
  if (value.length == 6) {
    value = 'FF$value';
  }
  if (value.length != 8) {
    return null;
  }
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Deterministically derives the gradient colors, rotation angle, and initials for an
/// [AvatarVariant], matching the algorithm in the web SDK's `generateAvatarDataUri.ts` bit-for-bit
/// (same hash, same palette index, same rotation math) so the two SDKs render identical avatars.
class AvatarLogoRender {
  final Color startColor;
  final Color endColor;

  /// Gradient rotation, in degrees, matching the SVG `gradientTransform="rotate(...)"` used by
  /// the web SDK.
  final double angleDegrees;

  /// 1-2 uppercase letters to overlay, truncated from [content] to the [variant]'s letter count.
  final String initials;

  const AvatarLogoRender({
    required this.startColor,
    required this.endColor,
    required this.angleDegrees,
    required this.initials,
  });

  /// [content] is assumed to already be the final, ready-to-render content (e.g. `"BM"`) — not a
  /// seed to extract initials from; it is only uppercased/truncated to the [variant]'s letter
  /// count for display, and hashed as-is (together with [colors]) to pick the gradient/angle.
  factory AvatarLogoRender.forSeed(
    String content,
    int colors,
    AvatarVariant variant,
  ) {
    final seed = content.isNotEmpty ? content : 'App';
    final hash = _hashStr(seed);
    final paletteIndex = _positiveMod(hash + colors, _avatarPalettes.length);
    final palette = _avatarPalettes[paletteIndex];
    // JS's `h >> 4` is a signed Int32 shift, so hashes >= 2^31 sign-extend to a negative value.
    final signedHash = hash >= 0x80000000 ? hash - 0x100000000 : hash;
    final angle = _positiveMod((signedHash >> 4) + colors * 37, 360);
    final letters = variant == AvatarVariant.oneLetter ? 1 : 2;
    final initials = _uppercaseTruncate(seed, letters);
    return AvatarLogoRender(
      startColor: Color(palette[0]),
      endColor: Color(palette[1]),
      angleDegrees: angle.toDouble(),
      initials: initials,
    );
  }

  static String _uppercaseTruncate(String seed, int letters) {
    final upper = seed.toUpperCase();
    return upper.length <= letters ? upper : upper.substring(0, letters);
  }
}

/// Renders a deterministically-generated gradient avatar with 1-2 overlaid letters, matching the
/// visual output of the web SDK's `generateAvatarDataUri`-produced SVG data URI.
///
/// The same `(content, colors, shape, variant)` combination always renders the same avatar, on
/// both platforms. Only ever used for [AvatarVariant.oneLetter]/[AvatarVariant.twoLetter] —
/// `avatar:variant=anonymous_animal`/`anonymous_entity` specs resolve to a bundled [AssetLogo]
/// instead.
class AvatarLogoBadge extends StatelessWidget {
  /// The literal content overlaid on the avatar (already-derived initials, not a seed).
  final String content;

  /// Gradient/rotation variant index (any integer; wraps around the palette).
  final int colors;

  /// Background shape.
  final AvatarShape shape;

  /// Letter-count variant.
  final AvatarVariant variant;

  /// Optional explicit flat background color (e.g. `"#FF5733"`), overriding the derived gradient.
  final String? bg;

  /// Side length of the square badge, in logical pixels.
  final double size;

  const AvatarLogoBadge({
    super.key,
    required this.content,
    required this.colors,
    required this.shape,
    required this.variant,
    this.bg,
    this.size = 60,
  });

  /// Convenience constructor building an [AvatarLogoBadge] straight from a parsed [AvatarLogo].
  AvatarLogoBadge.fromLogo(AvatarLogo logo, {Key? key, double size = 60})
      : this(
          key: key,
          content: logo.content,
          colors: logo.colors,
          shape: logo.shape,
          variant: logo.variant,
          bg: logo.bg,
          size: size,
        );

  bool get _isCircle => shape == AvatarShape.circle;

  @override
  Widget build(BuildContext context) {
    final render = AvatarLogoRender.forSeed(content, colors, variant);
    final radians = render.angleDegrees * math.pi / 180;
    // A 45°-diagonal unit gradient rotated by `radians`, matching the SVG
    // `gradientTransform="rotate(angle 0.5 0.5)"` applied to an `x1/y1=0% x2/y2=100%` gradient.
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    const dx = 1.0, dy = 1.0;
    final rotatedDx = dx * cos - dy * sin;
    final rotatedDy = dx * sin + dy * cos;
    final begin = Alignment(-rotatedDx, -rotatedDy);
    final end = Alignment(rotatedDx, rotatedDy);
    final flatColor = _parseHexColor(bg);

    return Semantics(
      label: 'Avatar with initials ${render.initials}',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: _isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius:
              _isCircle ? null : BorderRadius.circular(size * 14 / 60),
          color: flatColor,
          gradient: flatColor == null
              ? LinearGradient(
                  begin: begin,
                  end: end,
                  colors: <Color>[render.startColor, render.endColor],
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          render.initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 20 / 60,
          ),
        ),
      ),
    );
  }
}
