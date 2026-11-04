// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' show cos, pi, sin;

import 'package:flutter/widgets.dart';

import '../../models/user.dart';
import '../thunderid_provider.dart';

/// A pre-built avatar that renders the authenticated user's profile picture,
/// falling back to a deterministic two-color gradient circle with the
/// user's initials when no picture is available.
///
/// Reads the current user from [ThunderIDProvider] and delegates rendering
/// to [BaseUserAvatar].
class UserAvatar extends StatelessWidget {
  final double size;

  const UserAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseUserAvatar(user: state.user, size: size);
  }
}

/// Unstyled base variant — for full customization (spec §8.2 Base* components).
///
/// Takes an explicit [user] with no provider dependency, so it can be reused
/// outside of a [ThunderIDProvider] tree (e.g. previews, tests).
class BaseUserAvatar extends StatelessWidget {
  final User? user;
  final double size;
  final String? anonymousSeed;

  const BaseUserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.anonymousSeed,
  });

  String _resolveName() {
    final givenName = user?['given_name'];
    final familyName = user?['family_name'];
    if (givenName is String &&
        givenName.isNotEmpty &&
        familyName is String &&
        familyName.isNotEmpty) {
      return '$givenName $familyName';
    }
    final displayName = user?.displayName;
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final username = user?.username;
    if (username != null && username.isNotEmpty) return username;
    final email = user?.email;
    if (email != null && email.isNotEmpty) return email;
    return anonymousSeed != null && anonymousSeed!.isNotEmpty
        ? anonymousSeed!
        : 'Guest';
  }

  String? _resolvePictureUrl() {
    final user = this.user;
    if (user == null) return null;
    const claimKeys = <String>[
      'picture',
      'profileUrl',
      'profile',
      'URL',
      'avatarUrl',
      'avatar',
    ];
    for (final key in claimKeys) {
      final value = user[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = _resolveName();
    final pictureUrl = _resolvePictureUrl();

    return Semantics(
      label: 'User avatar for $name',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: pictureUrl != null
            ? ClipOval(
                child: Image.network(
                  pictureUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _InitialsAvatar(name: name, size: size),
                ),
              )
            : _InitialsAvatar(name: name, size: size),
      ),
    );
  }
}

/// Renders the deterministic gradient + initials fallback for [name].
class _InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _InitialsAvatar({required this.name, required this.size});

  /// JS-compatible 32-bit signed integer string hash:
  /// `((acc << 5) - acc + charCode)` per character, wrapping at 32 bits.
  static int _hash(String value) {
    int hash = 0;
    for (final rune in value.codeUnits) {
      hash = ((hash << 5) - hash + rune).toSigned(32);
    }
    return hash == -2147483648 ? 0 : hash.abs();
  }

  static String _initials(String value) => value
      .trim()
      .split(' ')
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();

  /// Ported bit-for-bit from the web SDK's `generateBackgroundColor`
  /// (`packages/react/src/components/primitives/Avatar/Avatar.tsx`).
  static LinearGradient _gradient(String value) {
    final seed = _hash(value);
    final hue1 = (2 * seed) % 360;
    final hue2 = (hue1 + 60 + (seed % 120)) % 360;
    final saturation = 70 + (seed % 20);
    final lightness1 = 55 + (seed % 15);
    final lightness2 = 60 + ((2 * seed) % 15);
    final angleDegrees = 45 + (seed % 91);

    final color1 = HSLColor.fromAHSL(
      1.0,
      hue1.toDouble(),
      saturation / 100,
      lightness1 / 100,
    ).toColor();
    final color2 = HSLColor.fromAHSL(
      1.0,
      hue2.toDouble(),
      saturation / 100,
      lightness2 / 100,
    ).toColor();

    final radians = angleDegrees * pi / 180;
    final dx = sin(radians);
    final dy = -cos(radians);

    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: [color1, color2],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: _gradient(name),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initials(name),
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontWeight: FontWeight.w600,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }
}
