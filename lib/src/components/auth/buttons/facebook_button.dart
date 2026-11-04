// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'outlined_trigger_button.dart';
import 'svg_icon_path.dart';

const Size _viewBox = Size(512, 512);

/// Facebook "f" glyph, ported from the SVG path data used by the web SDK's `FacebookButton`
/// icon adapter (viewBox 512 x 512).
class _FacebookGlyph extends StatelessWidget {
  const _FacebookGlyph();

  @override
  Widget build(BuildContext context) => const MultiColorSvgIcon(
        viewBox: _viewBox,
        size: 18,
        paths: [
          SvgPathSpec(
            pathData:
                'M448,0H64C28.704,0,0,28.704,0,64v384c0,35.296,28.704,64,64,64h384c35.296,0,64-28.704,64-64V64C512,28.704,483.296,0,448,0z',
            color: Color(0xFF1976D2),
          ),
          SvgPathSpec(
            pathData:
                'M432,256h-80v-64c0-17.664,14.336-16,32-16h32V96h-64l0,0c-53.024,0-96,42.976-96,96v64h-64v80h64v176h96V336h48L432,256z',
            color: Color(0xFFFAFAFA),
          ),
        ],
      );
}

/// "Continue with Facebook" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
class FacebookButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const FacebookButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Facebook',
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => OutlinedTriggerButton(
        label: label,
        isLoading: isLoading,
        disabled: disabled,
        onPressed: onPressed,
        icon: const _FacebookGlyph(),
      );
}
