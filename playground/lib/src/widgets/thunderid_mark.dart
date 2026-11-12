// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// The ThunderID mark, with the top bar lightened for the playground's dark background.
class ThunderIDMark extends StatelessWidget {
  const ThunderIDMark({super.key, this.height = 26});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ThunderID',
      child: CustomPaint(size: Size(height * 207 / 257, height), painter: const _ThunderIDMarkPainter()),
    );
  }
}

class _ThunderIDMarkPainter extends CustomPainter {
  const _ThunderIDMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 207, size.height / 257);

    final topBar = Path()
      ..moveTo(55.4763, 26.4391)
      ..lineTo(58.8866, 0)
      ..lineTo(0, 0)
      ..lineTo(0, 26.4391)
      ..close();
    canvas.drawPath(topBar, Paint()..color = const Color(0xFFE8F4FF));

    final blue = Paint()..color = PlaygroundColors.primary;

    final leftBar = Path()
      ..moveTo(39.8438, 147.407)
      ..lineTo(49.5455, 72.2839)
      ..lineTo(0, 72.2839)
      ..lineTo(0, 256.743)
      ..lineTo(60.5602, 256.743)
      ..lineTo(80.048, 147.407)
      ..close();
    canvas.drawPath(leftBar, blue);

    final bolt = Path()
      ..moveTo(192.42, 59.361)
      ..cubicTo(182.782, 40.2307, 168.929, 25.5705, 150.903, 15.3381)
      ..cubicTo(145.501, 12.2662, 139.761, 9.6605, 133.703, 7.5208)
      ..lineTo(115.401, 103.702)
      ..lineTo(159.757, 103.702)
      ..lineTo(76.2987, 256.743)
      ..lineTo(83.3735, 256.743)
      ..cubicTo(109.449, 256.743, 131.69, 251.574, 150.14, 241.236)
      ..cubicTo(168.569, 230.897, 182.634, 216.131, 192.356, 196.959)
      ..cubicTo(202.058, 177.765, 206.909, 154.8, 206.909, 128.043)
      ..cubicTo(206.909, 101.286, 202.079, 78.5123, 192.441, 59.3821)
      ..close();
    canvas
      ..drawPath(bolt, blue)
      ..restore();
  }

  @override
  bool shouldRepaint(_ThunderIDMarkPainter oldDelegate) => false;
}
