import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A CSS `linear-gradient(<deg>deg, ...)` as a Flutter [LinearGradient].
///
/// CSS angles are clockwise from "up"; the gradient line is stretched so the
/// corners of the box get the end colours exactly as in a browser (that is
/// what [Alignment] does for a non-square box too, within a pixel or two).
LinearGradient cssLinear(
  double deg,
  List<Color> colors, [
  List<double>? stops,
]) {
  final r = deg * math.pi / 180;
  final end = Alignment(math.sin(r), -math.cos(r));
  return LinearGradient(
    begin: Alignment(-end.x, -end.y),
    end: end,
    colors: colors,
    stops: stops,
  );
}
