// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'outlined_trigger_button.dart';
import 'svg_icon_path.dart';

const Size _viewBox = Size(24, 24);

/// Fallback fingerprint glyph used for passkey trigger actions when the server response has
/// no `startIcon`/`image` for the button. Ported from the "fingerprint-pattern" line-art icon
/// (24x24 viewBox, `stroke="currentColor" stroke-width="2"`), stroked rather than filled.
class _FingerprintGlyph extends StatelessWidget {
  const _FingerprintGlyph();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final paths = [
      'M12,10a2,2,0,0,0,-2,2c0,1.02,-.1,2.51,-.26,4',
      'M14,13.12c0,2.38,0,6.38,-1,8.88',
      'M17.29,21.02c.12,-.6,.43,-2.3,.5,-3.02',
      'M2,12a10,10,0,0,1,18,-6',
      'M2,16h.01',
      'M21.8,16c.2,-2,.131,-5.354,0,-6',
      'M5,19.5C5.5,18,6,15,6,12a6,6,0,0,1,.34,-2',
      'M8.65,22c.21,-.66,.45,-1.32,.57,-2',
      'M9,6.8a6,6,0,0,1,9,5.2v2',
    ];
    return MultiColorSvgIcon(
      viewBox: _viewBox,
      size: 18,
      paths: [
        for (final pathData in paths)
          SvgPathSpec(pathData: pathData, color: color, strokeWidth: 2),
      ],
    );
  }
}

/// "Sign In with Passkey" trigger, styled to match the outlined action buttons rendered below
/// a SignIn form's "Or" divider. Used as an icon fallback when the flow response's passkey
/// action carries no `startIcon`/`image`.
class PasskeyButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const PasskeyButton({
    super.key,
    required this.onPressed,
    this.label = 'Sign In with Passkey',
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => OutlinedTriggerButton(
        label: label,
        isLoading: isLoading,
        disabled: disabled,
        onPressed: onPressed,
        icon: const _FingerprintGlyph(),
      );
}
