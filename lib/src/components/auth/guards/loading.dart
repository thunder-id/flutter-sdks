// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import '../../thunderid_provider.dart';

/// Renders [indicator] while the SDK is initializing or loading (spec §8.4 Control/Guard).
/// Renders [child] (or nothing) once loading completes.
class Loading extends StatelessWidget {
  final Widget? child;
  final Widget? indicator;

  const Loading({super.key, this.child, this.indicator});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    if (state.isLoading) {
      return indicator ?? const Center(child: _DefaultSpinner());
    }
    return child ?? const SizedBox.shrink();
  }
}

class _DefaultSpinner extends StatelessWidget {
  const _DefaultSpinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 24, height: 24, child: CircularProgressIndicatorStub());
}

// Stub — avoids a Material/Cupertino import at this layer.
// Replace with CircularProgressIndicator when using with Flutter Material.
class CircularProgressIndicatorStub extends StatelessWidget {
  const CircularProgressIndicatorStub({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
