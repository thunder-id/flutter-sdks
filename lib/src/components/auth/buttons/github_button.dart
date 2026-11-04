// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'outlined_trigger_button.dart';
import 'svg_icon_path.dart';

const Size _viewBox = Size(67.91, 66.233);

/// GitHub "Octocat" mark, ported from the SVG path data used by the web SDK's `GitHubButton`
/// icon adapter (viewBox 67.91 x 66.233). Matches the iOS `GitHubGlyph` (`GitHubButton.swift`)
/// and Android `gitHubLogo()` (`GitHubButton.kt`) ports.
class _GitHubGlyph extends StatelessWidget {
  const _GitHubGlyph();

  @override
  Widget build(BuildContext context) => MultiColorSvgIcon(
        viewBox: _viewBox,
        size: 18,
        paths: [
          SvgPathSpec(
            pathData:
                'M420.915,-658.072a33.956,33.956,0,0,0,-33.955,33.955,33.963,33.963,0,0,0,23.221,32.22c1.7,.314,2.32,-.737,2.32,-1.633,0,-.81,-.031,-3.484,-.046,-6.322,-9.446,2.054,-11.44,-4.006,-11.44,-4.006,-1.545,-3.925,-3.77,-4.968,-3.77,-4.968,-3.081,-2.107,.232,-2.064,.232,-2.064,3.41,.239,5.205,3.5,5.205,3.5,3.028,5.19,7.943,3.69,9.881,2.822a7.23,7.23,0,0,1,2.156,-4.54c-7.542,-.859,-15.47,-3.77,-15.47,-16.781a13.141,13.141,0,0,1,3.5,-9.114,12.2,12.2,0,0,1,.329,-8.986s2.851,-.913,9.34,3.48a32.545,32.545,0,0,1,8.5,-1.143,32.629,32.629,0,0,1,8.506,1.143c6.481,-4.393,9.328,-3.48,9.328,-3.48a12.185,12.185,0,0,1,.333,8.986,13.115,13.115,0,0,1,3.495,9.114c0,13.042,-7.943,15.913,-15.5,16.754,1.218,1.054,2.3,3.12,2.3,6.288,0,4.543,-.039,8.2,-.039,9.318,0,.9,.611,1.962,2.332,1.629a33.959,33.959,0,0,0,23.2,-32.215,33.955,33.955,0,0,0,-33.955,-33.955',
            // The upstream "Octocat" mark ships as a single white-fill path meant to sit on a
            // dark badge background. This button's chrome is a transparent/outlined surface
            // (see OutlinedTriggerButton), so a hardcoded white fill would be invisible in
            // light mode. Use the theme's foreground color instead so the glyph stays visible
            // in both light and dark mode.
            color: Theme.of(context).colorScheme.onSurface,
            translate: const Offset(-386.96, 658.072),
          ),
        ],
      );
}

/// "Continue with GitHub" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
class GitHubButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const GitHubButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with GitHub',
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => OutlinedTriggerButton(
        label: label,
        isLoading: isLoading,
        disabled: disabled,
        onPressed: onPressed,
        icon: const _GitHubGlyph(),
      );
}
