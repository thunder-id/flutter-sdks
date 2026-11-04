// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import '../../thunderid_provider.dart';

/// Renders [child] only when no user is authenticated (spec §8.4 Control/Guard).
class SignedOut extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const SignedOut({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    if (!state.isSignedIn) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
