// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import '../../thunderid_provider.dart';

/// Renders [child] only when the user is authenticated. Renders [fallback] (or
/// nothing) otherwise (spec §8.4 Control/Guard).
class SignedIn extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const SignedIn({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    if (state.isSignedIn) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
