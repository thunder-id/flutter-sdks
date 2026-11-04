// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../i18n/thunderid_i18n.dart';
import '../../models/user.dart';
import '../thunderid_provider.dart';

/// Read-only display of the authenticated user's name and avatar (spec §8.4 Presentation).
class UserObject extends StatelessWidget {
  const UserObject({super.key});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseUserObject(
      builder: (ctx, user) => _DefaultUserLayout(user: user, i18n: state.i18n),
    );
  }
}

class _DefaultUserLayout extends StatelessWidget {
  final User? user;
  final ThunderIDI18n i18n;

  const _DefaultUserLayout({required this.user, required this.i18n});

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    final name = user!.displayName ?? user!.username ?? user!.email ?? i18n.resolve('user.anonymous');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Avatar(user: user!),
        const SizedBox(width: 8),
        Semantics(label: name, child: Text(name)),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final User user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final pic = user['picture'] as String?;
    if (pic != null) {
      return Semantics(
        label: 'Profile picture',
        child: SizedBox(width: 36, height: 36, child: Image.network(pic)),
      );
    }
    final initials = _initials(user);
    return Semantics(
      label: 'User initials: $initials',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(child: Text(initials)),
      ),
    );
  }

  String _initials(User user) {
    final name = user.displayName ?? user.username ?? user.email ?? '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

/// Unstyled base variant (spec §8.3).
class BaseUserObject extends StatelessWidget {
  final Widget Function(BuildContext context, User? user) builder;

  const BaseUserObject({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return builder(context, state.user);
  }
}
