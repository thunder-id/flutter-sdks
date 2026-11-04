// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'outlined_trigger_button.dart';

/// Multi-gradient Google "G" glyph, rendered from a bundled raster asset since Google's
/// current mark can't be reasonably reproduced with the flat-path `MultiColorSvgIcon`
/// renderer used by the other provider adapters in this directory.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) => Image.asset(
        'packages/thunderid_flutter/assets/provider-icons/google.png',
        width: 18,
        height: 18,
        fit: BoxFit.contain,
      );
}

/// "Continue with Google" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
class GoogleButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const GoogleButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Google',
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => OutlinedTriggerButton(
        label: label,
        isLoading: isLoading,
        disabled: disabled,
        onPressed: onPressed,
        icon: const _GoogleGlyph(),
      );
}
