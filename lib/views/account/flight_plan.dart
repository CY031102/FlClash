import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'logo_data.dart';

/// Where the plane is at one frame of the flight, in logo view box units.
class PlanePose {
  const PlanePose({
    required this.distance,
    required this.x,
    required this.y,
    required this.rotation,
    required this.scale,
  });

  /// How much of the line has been drawn.
  final double distance;
  final double x;
  final double y;

  /// Radians, relative to the plane's heading in the artwork.
  final double rotation;
  final double scale;
}

/// The logo flight worked out once: the line sampled every [step] units, the
/// pace along it and the plane's heading per frame, and the pen width.
///
/// The heading follows the line's broad direction rather than every wiggle
/// and is smoothed over time, so the plane never whips round a tight loop;
/// it slows where the line turns and the pen presses harder there.
class FlightPlan {
  FlightPlan._(
    this.length,
    this.xs,
    this.ys,
    this.widths,
    this.headings,
    this._s,
    this._a,
  );

  static const step = 2.0;
  static const fps = 60;
  static const duration = Duration(milliseconds: 7000);
  static const _headingWindow = 160.0;
  static const _slowdown = 100.0;
  static const _edge = 0.1;
  static const _sigmaMs = 240.0;
  static const _flightScale = 0.72;
  static const _penWidth = 7.8;

  static final FlightPlan instance = FlightPlan._build();

  final double length;
  final Float64List xs;
  final Float64List ys;
  final Float64List widths;

  /// Radians, the line's broad direction at each sample, unwrapped.
  final Float64List headings;
  final Float64List _s;
  final Float64List _a;

  int get sampleCount => xs.length;
  int get frameCount => _s.length - 1;

  static double get heading => logoPlaneHeadingDegrees * math.pi / 180;

  static Path linePath() {
    final p = <Offset>[
      for (var i = 0; i < logoLinePoints.length; i += 2)
        Offset(
          logoLinePoints[i].toDouble(),
          logoLinePoints[i + 1].toDouble(),
        ),
    ];
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = p[math.max(0, i - 1)];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = p[math.min(p.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  factory FlightPlan._build() {
    final metric = linePath().computeMetrics().first;
    final length = metric.length;
    final n = (length / step).ceil();
    final xs = Float64List(n + 1);
    final ys = Float64List(n + 1);
    for (var i = 0; i <= n; i++) {
      final p = metric
          .getTangentForOffset(math.min(length, i * step))!
          .position;
      xs[i] = p.dx;
      ys[i] = p.dy;
    }
    final w = (_headingWindow / step).round();
    final h = Float64List(n + 1);
    for (var i = 0; i <= n; i++) {
      final a = math.max(0, i - w);
      final b = math.min(n, i + w);
      h[i] = math.atan2(ys[b] - ys[a], xs[b] - xs[a]);
    }
    for (var i = 1; i <= n; i++) {
      h[i] = h[i - 1] + _wrap(h[i] - h[i - 1]);
    }
    final k = Float64List(n + 1);
    for (var i = 0; i <= n; i++) {
      final a = math.max(0, i - 2);
      final b = math.min(n, i + 2);
      k[i] = (h[b] - h[a]).abs() / ((b - a) * step);
    }
    final t = Float64List(n + 1);
    for (var i = 1; i <= n; i++) {
      t[i] = t[i - 1] + step * (1 + _slowdown * k[i]);
    }
    final total = t[n];
    final frames = (duration.inMilliseconds / 1000 * fps).round();
    final s = Float64List(frames + 1);
    final a = Float64List(frames + 1);
    var j = 0;
    for (var f = 0; f <= frames; f++) {
      final tk = _ease(f / frames) * total;
      while (j < n - 1 && t[j + 1] < tk) {
        j++;
      }
      final span = t[j + 1] - t[j];
      final fr = span == 0 ? 0.0 : (tk - t[j]) / span;
      s[f] = (j + fr) * step;
      a[f] = h[j] + (h[j + 1] - h[j]) * fr;
    }
    final sg = _sigmaMs * fps / 1000;
    final r = (sg * 3).ceil();
    final smoothed = Float64List(frames + 1);
    for (var f = 0; f <= frames; f++) {
      var sw = 0.0;
      var sv = 0.0;
      for (var d = -r; d <= r; d++) {
        final g = math.exp(-d * d / (2 * sg * sg));
        sw += g;
        sv += g * a[(f + d).clamp(0, frames)];
      }
      smoothed[f] = sv / sw;
    }
    return FlightPlan._(length, xs, ys, _penWidths(k, length), h, s, smoothed);
  }

  static Float64List _penWidths(Float64List k, double length) {
    final n = k.length - 1;
    final sorted = Float64List.fromList(k)..sort();
    final lo = sorted[(sorted.length * 0.1).floor()];
    final hi = sorted[(sorted.length * 0.9).floor()];
    final range = hi - lo == 0 ? 1e-6 : hi - lo;
    final raw = Float64List(n + 1);
    for (var i = 0; i <= n; i++) {
      raw[i] = ((k[i] - lo) / range).clamp(0.0, 1.0);
    }
    final out = Float64List(n + 1);
    for (var i = 0; i <= n; i++) {
      var sw = 0.0;
      var sv = 0.0;
      for (var d = -20; d <= 20; d += 2) {
        final g = math.exp(-d * d / 200);
        sw += g;
        sv += g * raw[(i + d).clamp(0, n)];
      }
      final s = i * step;
      final taper =
          (0.22 + 0.78 * smoothStep(s / 45)) *
          (0.18 + 0.82 * smoothStep((length - s) / 60));
      out[i] = _penWidth * (0.55 + 0.95 * sv / sw) * taper;
    }
    return out;
  }

  static double _wrap(double d) => math.atan2(math.sin(d), math.cos(d));

  static double _ease(double k) {
    const e = _edge;
    if (k < e) return k * k / (2 * e * (1 - e));
    if (k > 1 - e) {
      final r = 1 - k;
      return 1 - r * r / (2 * e * (1 - e));
    }
    return (k - e / 2) / (1 - e);
  }

  static double smoothStep(double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return x * x * (3 - 2 * x);
  }

  Offset _pointAt(double s) {
    if (s <= length) {
      final i = math.min(sampleCount - 1.0, s / step);
      final a = i.floor();
      final b = math.min(sampleCount - 1, a + 1);
      final f = i - a;
      return Offset(xs[a] + (xs[b] - xs[a]) * f, ys[a] + (ys[b] - ys[a]) * f);
    }
    final e = s - length;
    return Offset(
      xs.last + math.cos(heading) * e,
      ys.last + math.sin(heading) * e,
    );
  }

  /// [frame] counts from the start of the flight at [fps]; past the end it
  /// rests where the plane sits in the artwork.
  PlanePose poseAt(double frame) {
    final f = frame.clamp(0.0, frameCount.toDouble());
    final a = f.floor();
    final b = math.min(frameCount, a + 1);
    final fr = f - a;
    final s = _s[a] + (_s[b] - _s[a]) * fr;
    final th = _a[a] + (_a[b] - _a[a]) * fr;
    return poseAlong(s, th, smoothStep((f / frameCount - 0.88) / 0.12));
  }

  /// The plane [s] along the line heading [th], blended by [k] into the
  /// pose it rests in at the end of the artwork.
  PlanePose poseAlong(double s, double th, double k) {
    var target = heading;
    while (target - th > math.pi) {
      target -= 2 * math.pi;
    }
    while (target - th < -math.pi) {
      target += 2 * math.pi;
    }
    th += (target - th) * k;
    final scale = _flightScale + (1 - _flightScale) * k;
    final centre = math.sqrt(
      logoPlaneCenterX * logoPlaneCenterX +
          logoPlaneCenterY * logoPlaneCenterY,
    );
    final c = _pointAt(s + centre * scale);
    final rest = Offset(
      xs.last + logoPlaneCenterX,
      ys.last + logoPlaneCenterY,
    );
    return PlanePose(
      distance: s,
      x: c.dx + (rest.dx - c.dx) * k,
      y: c.dy + (rest.dy - c.dy) * k,
      rotation: th - heading,
      scale: scale,
    );
  }

  double headingAt(double s) =>
      headings[(s / step).round().clamp(0, sampleCount - 1)];
}

/// Parses the M, L and Z commands the traced outlines use.
Path parseOutline(String data) {
  final path = Path();
  final tokens = RegExp(r'[MLZ]|-?\d+(?:\.\d+)?').allMatches(data);
  String? command;
  final numbers = <double>[];
  void flush() {
    for (var i = 0; i + 1 < numbers.length; i += 2) {
      if (command == 'M' && i == 0) {
        path.moveTo(numbers[i], numbers[i + 1]);
      } else {
        path.lineTo(numbers[i], numbers[i + 1]);
      }
    }
    numbers.clear();
  }

  for (final m in tokens) {
    final t = m.group(0)!;
    if (t == 'M' || t == 'L' || t == 'Z') {
      flush();
      if (t == 'Z') path.close();
      command = t;
    } else {
      numbers.add(double.parse(t));
    }
  }
  flush();
  return path;
}
