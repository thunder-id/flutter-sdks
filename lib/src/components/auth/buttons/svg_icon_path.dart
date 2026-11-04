// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single colored `<path d="...">` from a brand icon's SVG source, ported into a Flutter
/// [Path] and scaled into a shared [viewBox]. Mirrors the `SVGIconPath`/`PathParser` ports used
/// by the iOS (`SVGIconPath.swift`) and Android (`GoogleButton.kt`/`GitHubButton.kt`) SDKs, so
/// the same brand glyph renders identically across platforms.
@immutable
class SvgPathSpec {
  /// The raw SVG path `d` attribute data. Supports the M/L/H/V/C/A/Z commands (absolute and
  /// relative) used by the Google/GitHub logos ported from the web SDK's icon adapters.
  final String pathData;

  /// Fill or stroke color for this path (see [strokeWidth]).
  final Color color;

  /// Translation applied in the SVG's own coordinate space, matching a
  /// `<g transform="translate(...)">` wrapper around the source `<path>` (e.g. Google's
  /// four-color glyph groups).
  final Offset translate;

  /// When set, the path is stroked (round cap/join) with this width instead of filled —
  /// for line-art icons ported from `fill="none" stroke="currentColor"` SVG sources (e.g. the
  /// passkey fingerprint glyph). Null (the default) fills the path, matching brand logo glyphs.
  final double? strokeWidth;

  const SvgPathSpec({
    required this.pathData,
    required this.color,
    this.translate = Offset.zero,
    this.strokeWidth,
  });
}

/// Renders one or more [SvgPathSpec]s scaled to fit a square icon of [size], matching the
/// `MultiColorSvgIcon`-style composition used by the Google/GitHub brand marks.
class MultiColorSvgIcon extends StatelessWidget {
  final Size viewBox;
  final List<SvgPathSpec> paths;
  final double size;

  const MultiColorSvgIcon({
    super.key,
    required this.viewBox,
    required this.paths,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SvgPathPainter(viewBox: viewBox, paths: paths),
        ),
      );
}

class _SvgPathPainter extends CustomPainter {
  final Size viewBox;
  final List<SvgPathSpec> paths;

  const _SvgPathPainter({required this.viewBox, required this.paths});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / viewBox.width;
    final scaleY = size.height / viewBox.height;
    for (final spec in paths) {
      Offset map(Offset point) => Offset(
            (point.dx + spec.translate.dx) * scaleX,
            (point.dy + spec.translate.dy) * scaleY,
          );
      final path = _SvgPathParser(spec.pathData).parseToPath(map);
      final strokeWidth = spec.strokeWidth;
      final paint = strokeWidth != null
          ? (Paint()
            ..color = spec.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * ((scaleX + scaleY) / 2)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round)
          : (Paint()..color = spec.color);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SvgPathPainter oldDelegate) =>
      oldDelegate.viewBox != viewBox || oldDelegate.paths != paths;
}

/// A parsed drawing instruction in the SVG path's own coordinate space (pre-scaling).
abstract class _Seg {
  void apply(Path path, Offset Function(Offset) map);
}

class _MoveSeg extends _Seg {
  final Offset point;
  _MoveSeg(this.point);
  @override
  void apply(Path path, Offset Function(Offset) map) =>
      path.moveTo(map(point).dx, map(point).dy);
}

class _LineSeg extends _Seg {
  final Offset point;
  _LineSeg(this.point);
  @override
  void apply(Path path, Offset Function(Offset) map) =>
      path.lineTo(map(point).dx, map(point).dy);
}

class _CurveSeg extends _Seg {
  final Offset control1;
  final Offset control2;
  final Offset end;
  _CurveSeg(this.control1, this.control2, this.end);
  @override
  void apply(Path path, Offset Function(Offset) map) {
    final c1 = map(control1);
    final c2 = map(control2);
    final e = map(end);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
  }
}

class _CloseSeg extends _Seg {
  @override
  void apply(Path path, Offset Function(Offset) map) => path.close();
}

/// Minimal SVG path-data ("d" attribute) parser producing [_Seg]s, ported from the iOS SDK's
/// `SVGPathParser` (`SVGIconPath.swift`).
class _SvgPathParser {
  final String _data;
  int _idx = 0;
  Offset _current = Offset.zero;
  Offset _subpathStart = Offset.zero;
  String _command = 'M';
  // The reflection of the previous C/S command's second control point, used by S/s per the SVG
  // spec. Reset to null after any other command, in which case S/s uses the current point itself
  // as its (unreflected) first control point.
  Offset? _lastCubicControl;

  _SvgPathParser(this._data);

  Path parseToPath(Offset Function(Offset) map) {
    final path = Path();
    for (final seg in _parse()) {
      seg.apply(path, map);
    }
    return path;
  }

  List<_Seg> _parse() {
    final segments = <_Seg>[];
    while (_idx < _data.length) {
      _skipSeparators();
      if (_idx >= _data.length) break;
      final ch = _data[_idx];
      if (_isLetter(ch)) {
        _command = ch;
        _idx++;
      } else if (_command == 'M') {
        _command = 'L';
      } else if (_command == 'm') {
        _command = 'l';
      }
      final numbers = _readNumbers(_command);
      if (numbers == null) continue;
      _apply(_command, numbers, segments);
    }
    return segments;
  }

  List<double>? _readNumbers(String command) {
    final count = _argumentCount(command);
    if (count == 0) return const [];
    final values = <double>[];
    for (var i = 0; i < count; i++) {
      final value = _parseNumber();
      if (value == null) return values.isEmpty ? null : values;
      values.add(value);
    }
    return values;
  }

  int _argumentCount(String command) {
    switch (command.toLowerCase()) {
      case 'm':
      case 'l':
      case 't':
        return 2;
      case 'h':
      case 'v':
        return 1;
      case 'c':
        return 6;
      case 's':
      case 'q':
        return 4;
      case 'a':
        return 7;
      case 'z':
        return 0;
      default:
        return 0;
    }
  }

  void _apply(String command, List<double> values, List<_Seg> segments) {
    final isRelative = command.toLowerCase() == command && _isLetter(command);
    Offset resolved(double deltaX, double deltaY) => isRelative
        ? Offset(_current.dx + deltaX, _current.dy + deltaY)
        : Offset(deltaX, deltaY);

    switch (command.toLowerCase()) {
      case 'm':
        final point = resolved(values[0], values[1]);
        segments.add(_MoveSeg(point));
        _current = point;
        _subpathStart = point;
        break;
      case 'l':
        final point = resolved(values[0], values[1]);
        segments.add(_LineSeg(point));
        _current = point;
        break;
      case 'h':
        final point = Offset(
          isRelative ? _current.dx + values[0] : values[0],
          _current.dy,
        );
        segments.add(_LineSeg(point));
        _current = point;
        break;
      case 'v':
        final point = Offset(
          _current.dx,
          isRelative ? _current.dy + values[0] : values[0],
        );
        segments.add(_LineSeg(point));
        _current = point;
        break;
      case 'c':
        final control1 = resolved(values[0], values[1]);
        final control2 = resolved(values[2], values[3]);
        final end = resolved(values[4], values[5]);
        segments.add(_CurveSeg(control1, control2, end));
        _current = end;
        _lastCubicControl = _reflect(control2, end);
        return;
      case 's':
        final control1 = _lastCubicControl ?? _current;
        final control2 = resolved(values[0], values[1]);
        final end = resolved(values[2], values[3]);
        segments.add(_CurveSeg(control1, control2, end));
        _current = end;
        _lastCubicControl = _reflect(control2, end);
        return;
      case 'a':
        final end = resolved(values[5], values[6]);
        final arc = _EllipticalArc(
          start: _current,
          end: end,
          radiusX: values[0],
          radiusY: values[1],
          rotationDegrees: values[2],
          largeArc: values[3] != 0,
          sweep: values[4] != 0,
        );
        segments.addAll(arc.bezierSegments());
        _current = end;
        break;
      case 'z':
        segments.add(_CloseSeg());
        _current = _subpathStart;
        break;
      default:
        break;
    }
    _lastCubicControl = null;
  }

  /// Reflects [controlPoint] through [end], per the SVG spec's rule for S/s and T/t: the implicit
  /// first control point is the reflection of the previous curve's final control point about the
  /// current point.
  Offset _reflect(Offset controlPoint, Offset end) =>
      Offset(2 * end.dx - controlPoint.dx, 2 * end.dy - controlPoint.dy);

  void _skipSeparators() {
    while (_idx < _data.length &&
        (_data[_idx] == ',' || _data[_idx].trim().isEmpty)) {
      _idx++;
    }
  }

  bool _isLetter(String s) => s.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(s);

  bool _isDigit(String s) => s.isNotEmpty && RegExp(r'[0-9]').hasMatch(s);

  double? _parseNumber() {
    _skipSeparators();
    if (_idx >= _data.length) return null;
    final sb = StringBuffer();
    if (_data[_idx] == '-' || _data[_idx] == '+') {
      sb.write(_data[_idx]);
      _idx++;
    }
    var sawDot = false;
    while (_idx < _data.length &&
        (_isDigit(_data[_idx]) || (_data[_idx] == '.' && !sawDot))) {
      if (_data[_idx] == '.') sawDot = true;
      sb.write(_data[_idx]);
      _idx++;
    }
    if (_idx < _data.length && (_data[_idx] == 'e' || _data[_idx] == 'E')) {
      final expSb = StringBuffer(_data[_idx]);
      var lookahead = _idx + 1;
      if (lookahead < _data.length &&
          (_data[lookahead] == '+' || _data[lookahead] == '-')) {
        expSb.write(_data[lookahead]);
        lookahead++;
      }
      while (lookahead < _data.length && _isDigit(_data[lookahead])) {
        expSb.write(_data[lookahead]);
        lookahead++;
      }
      sb.write(expSb.toString());
      _idx = lookahead;
    }
    if (sb.isEmpty) return null;
    return double.tryParse(sb.toString());
  }
}

/// An SVG elliptical arc ("A"/"a" command), convertible to cubic-bezier segments per the
/// SVG 1.1 spec's endpoint-to-center-parameterization (Appendix F.6.5). Ported from the iOS
/// SDK's `EllipticalArc` (`SVGIconPath.swift`).
class _EllipticalArc {
  final Offset start;
  final Offset end;
  final double radiusX;
  final double radiusY;
  final double rotationDegrees;
  final bool largeArc;
  final bool sweep;

  const _EllipticalArc({
    required this.start,
    required this.end,
    required this.radiusX,
    required this.radiusY,
    required this.rotationDegrees,
    required this.largeArc,
    required this.sweep,
  });

  List<_Seg> bezierSegments() {
    final form = _centerForm();
    if (radiusX == 0 || radiusY == 0 || start == end || form == null) {
      return [_LineSeg(end)];
    }
    final segmentCount =
        math.max(1, (form.sweepAngle.abs() / (math.pi / 2)).ceil());
    final step = form.sweepAngle / segmentCount;
    var angle = form.startAngle;
    final segments = <_Seg>[];
    for (var i = 0; i < segmentCount; i++) {
      final nextAngle = angle + step;
      segments.add(_bezierSegment(angle, nextAngle, form));
      angle = nextAngle;
    }
    return segments;
  }

  _CenterForm? _centerForm() {
    var radiusX = this.radiusX.abs();
    var radiusY = this.radiusY.abs();
    final rotation = rotationDegrees * math.pi / 180;
    final cosRotation = math.cos(rotation);
    final sinRotation = math.sin(rotation);
    final halfDeltaX = (start.dx - end.dx) / 2;
    final halfDeltaY = (start.dy - end.dy) / 2;
    final rotatedX = cosRotation * halfDeltaX + sinRotation * halfDeltaY;
    final rotatedY = -sinRotation * halfDeltaX + cosRotation * halfDeltaY;

    final scaleCheck = (rotatedX * rotatedX) / (radiusX * radiusX) +
        (rotatedY * rotatedY) / (radiusY * radiusY);
    if (scaleCheck > 1) {
      final scale = math.sqrt(scaleCheck);
      radiusX *= scale;
      radiusY *= scale;
    }

    final sign = largeArc != sweep ? 1.0 : -1.0;
    final numerator = radiusX * radiusX * radiusY * radiusY -
        radiusX * radiusX * rotatedY * rotatedY -
        radiusY * radiusY * rotatedX * rotatedX;
    final denominator = radiusX * radiusX * rotatedY * rotatedY +
        radiusY * radiusY * rotatedX * rotatedX;
    final coefficient = denominator == 0
        ? 0.0
        : sign * math.sqrt(math.max(0, numerator / denominator));
    final centerRotatedX = coefficient * (radiusX * rotatedY) / radiusY;
    final centerRotatedY = coefficient * -(radiusY * rotatedX) / radiusX;

    final centerX = cosRotation * centerRotatedX -
        sinRotation * centerRotatedY +
        (start.dx + end.dx) / 2;
    final centerY = sinRotation * centerRotatedX +
        cosRotation * centerRotatedY +
        (start.dy + end.dy) / 2;

    final startVectorX = (rotatedX - centerRotatedX) / radiusX;
    final startVectorY = (rotatedY - centerRotatedY) / radiusY;
    final endVectorX = (-rotatedX - centerRotatedX) / radiusX;
    final endVectorY = (-rotatedY - centerRotatedY) / radiusY;
    final startAngle = _angleBetween(1, 0, startVectorX, startVectorY);
    var sweepAngle =
        _angleBetween(startVectorX, startVectorY, endVectorX, endVectorY);
    if (!sweep && sweepAngle > 0) sweepAngle -= 2 * math.pi;
    if (sweep && sweepAngle < 0) sweepAngle += 2 * math.pi;

    return _CenterForm(
      center: Offset(centerX, centerY),
      radiusX: radiusX,
      radiusY: radiusY,
      cosRotation: cosRotation,
      sinRotation: sinRotation,
      startAngle: startAngle,
      sweepAngle: sweepAngle,
    );
  }

  _Seg _bezierSegment(double angle, double nextAngle, _CenterForm form) {
    final kappa = 4.0 / 3.0 * math.tan((nextAngle - angle) / 4.0);
    final cosStart = math.cos(angle), sinStart = math.sin(angle);
    final cosEnd = math.cos(nextAngle), sinEnd = math.sin(nextAngle);
    final control1 = _mapUnitPoint(
      cosStart - kappa * sinStart,
      sinStart + kappa * cosStart,
      form,
    );
    final control2 = _mapUnitPoint(
      cosEnd + kappa * sinEnd,
      sinEnd - kappa * cosEnd,
      form,
    );
    final segmentEnd = _mapUnitPoint(cosEnd, sinEnd, form);
    return _CurveSeg(control1, control2, segmentEnd);
  }

  Offset _mapUnitPoint(double unitX, double unitY, _CenterForm form) {
    final scaledX = form.radiusX * unitX;
    final scaledY = form.radiusY * unitY;
    return Offset(
      form.cosRotation * scaledX - form.sinRotation * scaledY + form.center.dx,
      form.sinRotation * scaledX + form.cosRotation * scaledY + form.center.dy,
    );
  }

  double _angleBetween(double fromX, double fromY, double toX, double toY) {
    final dot = fromX * toX + fromY * toY;
    final magnitude =
        math.sqrt((fromX * fromX + fromY * fromY) * (toX * toX + toY * toY));
    var angle = math.acos((dot / magnitude).clamp(-1.0, 1.0));
    if (fromX * toY - fromY * toX < 0) angle = -angle;
    return angle;
  }
}

/// Center-parameterization values derived from the endpoint form of an elliptical arc.
class _CenterForm {
  final Offset center;
  final double radiusX;
  final double radiusY;
  final double cosRotation;
  final double sinRotation;
  final double startAngle;
  final double sweepAngle;

  const _CenterForm({
    required this.center,
    required this.radiusX,
    required this.radiusY,
    required this.cosRotation,
    required this.sinRotation,
    required this.startAngle,
    required this.sweepAngle,
  });
}
