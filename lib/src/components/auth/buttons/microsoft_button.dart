// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'outlined_trigger_button.dart';
import 'svg_icon_path.dart';

const Size _viewBox = Size(23, 23);

/// Microsoft four-square glyph, ported from the SVG path data used by the web SDK's
/// `MicrosoftButton` icon adapter (viewBox 23 x 23).
class _MicrosoftGlyph extends StatelessWidget {
  const _MicrosoftGlyph();

  @override
  Widget build(BuildContext context) => const MultiColorSvgIcon(
        viewBox: _viewBox,
        size: 18,
        paths: [
          SvgPathSpec(
            pathData: 'M0,0h23v23h-23z',
            color: Color(0xFFF3F3F3),
          ),
          SvgPathSpec(
            pathData: 'M1,1h10v10h-10z',
            color: Color(0xFFF35325),
          ),
          SvgPathSpec(
            pathData: 'M12,1h10v10h-10z',
            color: Color(0xFF81BC06),
          ),
          SvgPathSpec(
            pathData: 'M1,12h10v10h-10z',
            color: Color(0xFF05A6F0),
          ),
          SvgPathSpec(
            pathData: 'M12,12h10v10h-10z',
            color: Color(0xFFFFBA08),
          ),
        ],
      );
}

/// "Continue with Microsoft" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
class MicrosoftButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const MicrosoftButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Microsoft',
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => OutlinedTriggerButton(
        label: label,
        isLoading: isLoading,
        disabled: disabled,
        onPressed: onPressed,
        icon: const _MicrosoftGlyph(),
      );
}
