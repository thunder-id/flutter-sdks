// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'outlined_trigger_button.dart';
import 'svg_icon_path.dart';

const Size _viewBox = Size(24, 24);

/// LinkedIn "in" glyph, ported from the SVG path data used by the web SDK's `LinkedInButton`
/// icon adapter (viewBox 24 x 24).
class _LinkedInGlyph extends StatelessWidget {
  const _LinkedInGlyph();

  @override
  Widget build(BuildContext context) => const MultiColorSvgIcon(
        viewBox: _viewBox,
        size: 18,
        paths: [
          SvgPathSpec(
            pathData:
                'M20.447,20.452h-3.554v-5.569c0-1.328,-.027,-3.037,-1.852,-3.037,-1.853,0,-2.136,1.445,-2.136,2.939v5.667H9.351V9h3.414v1.561h.046c.477,-.9,1.637,-1.85,3.37,-1.85,3.601,0,4.267,2.37,4.267,5.455v6.286zM5.337,7.433c-1.144,0,-2.063,-.926,-2.063,-2.065,0,-1.138,.92,-2.063,2.063,-2.063,1.14,0,2.064,.925,2.064,2.063,0,1.139,-.925,2.065,-2.064,2.065zm1.782,13.019H3.555V9h3.564v11.452zM22.225,0H1.771C.792,0,0,.774,0,1.729v20.542C0,23.227,.792,24,1.771,24h20.451C23.2,24,24,23.227,24,22.271V1.729C24,.774,23.2,0,22.222,0h.003z',
            color: Color(0xFF0077B5),
          ),
        ],
      );
}

/// "Continue with LinkedIn" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
class LinkedInButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const LinkedInButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with LinkedIn',
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => OutlinedTriggerButton(
        label: label,
        isLoading: isLoading,
        disabled: disabled,
        onPressed: onPressed,
        icon: const _LinkedInGlyph(),
      );
}
