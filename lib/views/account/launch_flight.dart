import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'flight_plan.dart';
import 'logo_data.dart';

enum LaunchVerdict { ok, denied, unknown }

/// The short flight played whenever the full drawing has been seen once: the
/// plane crosses the sky while the account is checked, then either flies back
/// along the last stretch of the logo's route or falls out of the window.
class LaunchFlight extends StatefulWidget {
  const LaunchFlight({
    super.key,
    required this.verdict,
    required this.onLanded,
    this.onDenied,
    this.deniedPanel,
    this.mayGiveUp = true,
    this.from = _K.bg,
  });

  final Future<LaunchVerdict> verdict;

  /// Called once the dark has covered the window; false when the check gave
  /// up rather than answered.
  final ValueChanged<bool> onLanded;

  /// Called when the plane is gone after a denial, if [deniedPanel] is null.
  final VoidCallback? onDenied;
  final Widget? deniedPanel;
  final bool mayGiveUp;
  final Color from;

  @override
  State<LaunchFlight> createState() => _LaunchFlightState();
}

abstract final class _K {
  static const bg = Color(0xFFE9EEF5);
  static const ink = Color(0xFF191D2B);
  static const accent = Color(0xFF3DB4F2);
  static const trail = Color(0xFF788AA5);
  static const hintText = Color(0xFF4A5570);
  static const hintBorder = Color(0xFFD3DAE6);
}

enum _Step { pass, approach, follow, fall, wait, out, crash }

class _Trail {
  const _Trail(this.at, this.ms, this.width, {this.gap = false});

  final Offset at;
  final double ms;
  final double width;
  final bool gap;
}

class _Cloud {
  const _Cloud(this.x, this.y, this.r, this.depth);

  final double x;
  final double y;
  final double r;
  final double depth;
}

class _LaunchFlightState extends State<LaunchFlight>
    with SingleTickerProviderStateMixin {
  static const _speed = 2.0;
  static const _passMs = 850.0;
  static const _approachMs = 620.0;
  static const _followMs = 560.0;
  static const _join = 165.0;
  static const _trailMs = 480 * _speed;
  static const _stageW = 640.0;
  static const _stageH = 420.0;
  static const _pass = [
    Offset(-160, 470),
    Offset(170, 350),
    Offset(430, 190),
    Offset(820, 30),
  ];
  static const _clouds = [
    _Cloud(120, 110, 26, .35),
    _Cloud(520, 90, 20, .3),
    _Cloud(380, 330, 30, .45),
    _Cloud(700, 250, 24, .4),
    _Cloud(250, 250, 16, .25),
    _Cloud(820, 140, 28, .5),
  ];
  static const _front = _Cloud(620, 170, 62, 1.6);

  final _plan = FlightPlan.instance;
  final _plane = parseOutline(logoPlanePath);
  final _text = parseOutline(logoTextPath)..fillType = PathFillType.evenOdd;
  late final Ticker _ticker = createTicker(_tick);
  late final double _joinAt = _plan.length - _join;
  late final ui.Picture _baseInk = _drawBaseInk();
  late final Rect _textBounds = _text.getBounds();

  double _ms = 0;
  LaunchVerdict? _verdict;
  _Step _step = _Step.pass;
  double _stepAt = 0;
  double? _logoAt;
  double? _mapAt;
  double? _hintAt;
  double? _deniedAt;
  double? _outAt;
  bool _tapped = false;
  bool _gaveUp = false;
  bool _landed = false;
  List<Offset> _approach = const [];
  final List<_Trail> _trail = [];

  Size _size = const Size(_stageW, _stageH);
  Offset _planeAt = Offset.zero;
  double _planeTurn = 0;
  double _planeScale = 1;
  double _planeBank = 1;
  bool _planeInLogo = false;
  double _planeOpacity = 1;
  double _inkTo = 0;
  double _inkOpacity = 1;
  double _cloudAlpha = 1;
  double _logoFade = 1;

  @override
  void initState() {
    super.initState();
    _inkTo = _joinAt;
    unawaited(
      widget.verdict.then((v) {
        if (mounted) _verdict = v;
      }),
    );
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _baseInk.dispose();
    super.dispose();
  }

  ui.Picture _drawBaseInk() {
    final recorder = ui.PictureRecorder();
    _drawInk(Canvas(recorder), 0, (_joinAt / FlightPlan.step).floor());
    return recorder.endRecording();
  }

  void _drawInk(Canvas canvas, int from, int to) {
    final paint = Paint()
      ..color = _K.ink
      ..strokeCap = StrokeCap.round;
    for (var i = from; i < to; i++) {
      paint.strokeWidth = (_plan.widths[i] + _plan.widths[i + 1]) / 2;
      canvas.drawLine(
        Offset(_plan.xs[i], _plan.ys[i]),
        Offset(_plan.xs[i + 1], _plan.ys[i + 1]),
        paint,
      );
    }
  }

  double get _sx => _size.width / _stageW;
  double get _sy => _size.height / _stageH;
  double get _anim => _ms / _speed;
  double get _sinceStep => _anim - _stepAt;

  double get _logoScale => math.min(
    _size.width * 0.55,
    _size.height * 0.78 * logoViewWidth / logoViewHeight,
  ) / logoViewWidth;

  Offset get _logoOrigin {
    final k = _logoScale;
    return Offset(
      (_size.width - logoViewWidth * k) / 2,
      (_size.height - logoViewHeight * k) / 2,
    );
  }

  Offset _toStage(double x, double y) => _logoOrigin + Offset(x, y) * _logoScale;

  Offset _st(Offset p) => Offset(p.dx * _sx, p.dy * _sy);

  void _go(_Step step) {
    _step = step;
    _stepAt = _anim;
  }

  static Offset _bez(List<Offset> p, double u) {
    final v = 1 - u;
    return p[0] * (v * v * v) +
        p[1] * (3 * v * v * u) +
        p[2] * (3 * v * u * u) +
        p[3] * (u * u * u);
  }

  static double _dir(List<Offset> p, double u) {
    u = u.clamp(0.001, 0.999);
    final v = 1 - u;
    final d =
        (p[1] - p[0]) * (3 * v * v) +
        (p[2] - p[1]) * (6 * v * u) +
        (p[3] - p[2]) * (3 * u * u);
    return math.atan2(d.dy, d.dx);
  }

  static double _sm(double x) => FlightPlan.smoothStep(x);

  void _fly(Offset at, double turn, double scale, double bank, {bool mark = true}) {
    _planeAt = at;
    _planeTurn = turn;
    _planeScale = scale;
    _planeBank = bank;
    _planeInLogo = false;
    if (mark) _mark(at, turn, scale);
  }

  void _mark(Offset at, double turn, double scale) {
    final back = 56 * scale;
    _trail.add(
      _Trail(
        at - Offset(math.cos(turn), math.sin(turn)) * back,
        _ms,
        scale,
      ),
    );
  }

  void _restInLogo({double dx = 0, double dy = 0, double turn = 0}) {
    final rest = _plan.poseAlong(_plan.length, FlightPlan.heading, 1);
    _planeAt = Offset(rest.x + dx, rest.y + dy);
    _planeTurn = FlightPlan.heading + turn;
    _planeScale = 1;
    _planeBank = 1;
    _planeInLogo = true;
  }

  void _startApproach() {
    final q = _plan.poseAlong(_joinAt, _plan.headingAt(_joinAt), 0);
    final target = _toStage(q.x, q.y);
    final h = _plan.headingAt(_joinAt);
    _approach = [
      Offset(-100 * _sx, target.dy + 140 * _sy),
      Offset(target.dx - 330 * _sx, target.dy + 110 * _sy),
      target - Offset(math.cos(h), math.sin(h)) * (170 * _sx),
      target,
    ];
    _trail.add(_Trail(Offset.zero, _ms, 0, gap: true));
    _go(_verdict == LaunchVerdict.denied ? _Step.fall : _Step.approach);
  }

  void _tick(Duration elapsed) {
    _ms = elapsed.inMicroseconds / 1000;
    _trail.removeWhere((p) => _ms - p.ms > _trailMs);
    switch (_step) {
      case _Step.pass:
        final u = math.min(1.0, _anim / _passMs);
        _fly(
          _st(_bez(_pass, u)),
          _dir(_pass, u),
          (0.7 + 1.5 * math.pow(u, 1.7).toDouble()) * _sx,
          1 - 0.38 * math.sin(math.pi * u),
        );
        if (u >= 1) _startApproach();
      case _Step.approach:
        final u = math.min(1.0, _sinceStep / _approachMs);
        final e = u * (1.35 - 0.35 * u);
        final s0 = 1.05 * _sx;
        final end = _logoScale * 0.72;
        _fly(
          _bez(_approach, e),
          _dir(_approach, e),
          s0 + (end - s0) * _sm(u),
          1 - 0.3 * math.sin(math.pi * u),
        );
        if (u > 0.4) _mapAt ??= _ms;
        _cloudAlpha = 1 - math.max(0, u - 0.3) / 0.7;
        if (u >= 1) _go(_Step.follow);
      case _Step.follow:
        final v = math.min(1.0, _sinceStep / _followMs);
        final s = _joinAt + _join * (1 - (1 - v) * (1 - v));
        final k = _sm((v - 0.55) / 0.45);
        final q = _plan.poseAlong(
          s,
          _plan.headingAt(math.min(_plan.length, s)),
          k,
        );
        _inkTo = s;
        _planeAt = Offset(q.x, q.y);
        _planeTurn = q.rotation + FlightPlan.heading;
        _planeScale = q.scale;
        _planeBank = 1;
        _planeInLogo = true;
        _mark(_toStage(q.x, q.y), _planeTurn, _logoScale * q.scale);
        if (v >= 1) {
          _inkTo = _plan.length;
          _restInLogo();
          _logoAt = _ms;
          _go(_Step.wait);
        }
      case _Step.fall:
        _falling();
      case _Step.wait:
        _restInLogo();
        _waiting();
      case _Step.out:
        if (!_landed && _ms - _outAt! >= 1800) {
          _landed = true;
          _ticker.stop();
          widget.onLanded(!_gaveUp);
        }
      case _Step.crash:
        _crashing();
    }
    setState(() {});
  }

  void _waiting() {
    final since = _ms - _logoAt!;
    final verdict = _verdict;
    if (verdict != null && _sinceStep > 350) {
      if (verdict == LaunchVerdict.denied) {
        _go(_Step.crash);
      } else {
        _leave();
      }
      return;
    }
    if (widget.mayGiveUp && _ms > math.max(6000, _logoAt! + 3500)) {
      _gaveUp = true;
      _leave();
      return;
    }
    if (_hintAt == null && (since > 1500 || (_tapped && since > 300))) {
      _hintAt = _ms;
    }
  }

  void _leave() {
    _outAt = _ms;
    _go(_Step.out);
  }

  void _falling() {
    final c = _sinceStep;
    const tc = 300.0;
    double eased(double u) => u * (1.35 - 0.35 * u);
    final ee = c < tc
        ? eased(c / _approachMs)
        : eased(tc / _approachMs) + (1 - math.exp(-(c - tc) / 260)) * 0.14;
    final p = _bez(_approach, ee);
    final th0 = _dir(_approach, ee);
    var turn = th0;
    var dx = 0.0;
    var dy = 0.0;
    if (c > tc) {
      final k = c - tc;
      if (k < 380) {
        turn += math.sin(k / 34) * 0.16 * (1 - k / 380);
        dx = math.sin(k / 22) * 2.5;
      } else {
        final f = (k - 380) / 1000;
        dy = f * f * 820 * _sy;
        final g = math.min(1.0, f * 1.4);
        turn = th0 + (1.35 - th0) * (1 - (1 - g) * (1 - g));
      }
    }
    final at = p + Offset(dx, dy);
    _fly(
      at,
      turn,
      1.05 * _sx,
      1 - 0.25 * math.sin(math.min(1.0, c / 600) * math.pi),
      mark: dy < 40,
    );
    _cloudAlpha = math.max(0, 1 - c / 900);
    if (_deniedAt == null && at.dy > _size.height + 100) _denied();
  }

  void _crashing() {
    final c = _sinceStep;
    var dx = 0.0;
    var dy = 0.0;
    var r = 0.0;
    if (c < 500) {
      dx = math.sin(c / 28) * 3 * (1 - c / 500);
      r = math.sin(c / 40) * 7;
    } else {
      final k = math.min(1.0, (c - 500) / 1100);
      r = 70 * (1 - (1 - k) * (1 - k));
      dy = k * k * 140;
    }
    _restInLogo(dx: dx, dy: dy, turn: r * math.pi / 180);
    if (c > 1300) {
      final f = (c - 1300) * _speed;
      _planeOpacity = (1 - f / 300).clamp(0.0, 1.0);
      _inkOpacity = 1 - 0.7 * (f / 800).clamp(0.0, 1.0);
    }
    if (c > 1900 && _deniedAt == null) _denied();
    if (_deniedAt != null) {
      _logoFade = 1 - 0.85 * ((_ms - _deniedAt!) / (500 * _speed)).clamp(0.0, 1.0);
    }
  }

  void _denied() {
    _deniedAt = _ms;
    if (widget.deniedPanel == null) {
      Timer(const Duration(milliseconds: 250), () {
        if (mounted) widget.onDenied?.call();
      });
    }
    if (widget.deniedPanel != null) {
      Timer(const Duration(milliseconds: 1800), () {
        if (mounted) _ticker.stop();
      });
    }
  }

  double _fadeIn(double? at, double ms) =>
      at == null ? 0 : ((_ms - at) / ms).clamp(0.0, 1.0);

  double get _breath {
    final k = ((_anim - _stepAt) % 1500) / 1500;
    return 0.5 - 0.5 * math.cos(k * 2 * math.pi);
  }

  double get _halo {
    if (_step == _Step.wait) return ((_sinceStep - 350) / 330).clamp(0.0, 1.0);
    if (_step == _Step.out) return (1 - _sinceStep / 250).clamp(0.0, 1.0);
    return 0;
  }

  double get _dark {
    final at = _outAt;
    if (at == null) return 0;
    final k = ((_ms - at - 400) / 1400).clamp(0.0, 1.0);
    return const Cubic(0.55, 0, 0.35, 1).transform(k);
  }

  TextStyle _style(AppTextStyle s, Color color) =>
      s.of(context).copyWith(color: color);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        final bg = Color.lerp(widget.from, _K.bg, (_ms / 500).clamp(0.0, 1.0))!;
        final hint = _step == _Step.wait ? _fadeIn(_hintAt, 350) : 0.0;
        final textTop =
            _logoOrigin.dy + _textBounds.top * _logoScale;
        final denied = _deniedAt == null || widget.deniedPanel == null
            ? 0.0
            : ((_ms - _deniedAt! - 250 * _speed) / (500 * _speed)).clamp(
                0.0,
                1.0,
              );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapped = true,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScenePainter(this, bg),
                ),
              ),
              if (hint > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: textTop - 40 + 6 * (1 - Curves.easeOut.transform(hint)),
                  child: Center(
                    child: Opacity(opacity: hint, child: _buildHint()),
                  ),
                ),
              if (denied > 0)
                Positioned.fill(
                  child: Opacity(opacity: denied, child: widget.deniedPanel),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHint() {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: const Color(0xFFFFFFFF),
        shape: AppShape.full.copyWith(
          side: const BorderSide(color: _K.hintBorder, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 7,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: _K.accent.withValues(alpha: 0.35 + 0.65 * _breath),
                  shape: AppShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '正在確認帳號，馬上就好',
              style: _style(AppTextStyle.caption1, _K.hintText),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.s, this.bg);

  final _LaunchFlightState s;
  final Color bg;

  static final Path _cloud = () {
    final path = Path();
    for (final (dx, dy, r) in const [
      (0.0, 0.0, 1.0),
      (-.9, .25, .7),
      (.95, .2, .75),
      (-.35, -.45, .7),
      (.45, -.4, .6),
      (-1.6, .45, .45),
      (1.7, .45, .45),
    ]) {
      path.addOval(Rect.fromCircle(center: Offset(dx, dy), radius: r));
    }
    return path..addRect(const Rect.fromLTWH(-1.9, .2, 3.8, .55));
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    _paintClouds(canvas, back: true);
    _paintTrail(canvas);
    _paintLogo(canvas);
    if (!s._planeInLogo) {
      _paintPlane(canvas, s._planeAt, s._planeTurn, s._planeScale, s._planeBank);
    }
    _paintClouds(canvas, back: false);
    final dark = s._dark;
    if (dark > 0) {
      final rest = s._plan.poseAlong(s._plan.length, FlightPlan.heading, 1);
      final c = s._toStage(rest.x, rest.y);
      final reach = [
        c,
        Offset(size.width - c.dx, c.dy),
        Offset(c.dx, size.height - c.dy),
        Offset(size.width - c.dx, size.height - c.dy),
      ].map((o) => o.distance).reduce(math.max);
      canvas.drawCircle(c, reach * dark, Paint()..color = _K.ink);
    }
  }

  void _paintClouds(Canvas canvas, {required bool back}) {
    if (s._cloudAlpha <= 0) return;
    final sec = s._anim / 1000;
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(
        alpha: (back ? 0.95 : 0.92) * s._cloudAlpha,
      );
    final clouds = back
        ? _LaunchFlightState._clouds
        : [if (sec < 1.1) _LaunchFlightState._front];
    for (final c in clouds) {
      canvas
        ..save()
        ..translate(
          (c.x - 520 * c.depth * sec) * s._sx,
          (c.y + 170 * c.depth * sec) * s._sy,
        )
        ..scale(c.r * s._sx)
        ..drawPath(_cloud, paint)
        ..restore();
    }
  }

  void _paintTrail(Canvas canvas) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final t = s._trail;
    for (var i = 1; i < t.length; i++) {
      if (t[i].gap || t[i - 1].gap) continue;
      final a = 1 - (s._ms - t[i].ms) / _LaunchFlightState._trailMs;
      if (a <= 0) continue;
      paint
        ..color = _K.trail.withValues(alpha: 0.42 * a)
        ..strokeWidth = (1.5 + 5 * a) * t[i].width;
      canvas.drawLine(t[i - 1].at, t[i].at, paint);
    }
  }

  void _paintLogo(Canvas canvas) {
    final map = s._fadeIn(s._mapAt, 600) * s._logoFade;
    final inLogo = s._planeInLogo;
    if (map <= 0 && !inLogo) return;
    canvas
      ..save()
      ..translate(s._logoOrigin.dx, s._logoOrigin.dy)
      ..scale(s._logoScale);
    final inkAlpha = s._inkOpacity * s._logoFade;
    if (map > 0) {
      canvas
        ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, map * s._inkOpacity))
        ..drawPicture(s._baseInk)
        ..restore()
        ..drawPath(s._text, Paint()..color = _K.ink.withValues(alpha: map));
    }
    final to = (s._inkTo / FlightPlan.step).floor().clamp(
      0,
      s._plan.sampleCount - 1,
    );
    final from = (s._joinAt / FlightPlan.step).floor();
    if (to > from) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, inkAlpha));
      s._drawInk(canvas, from, to);
      canvas.restore();
    }
    final halo = s._halo;
    if (halo > 0) {
      final b = s._breath;
      _paintPlane(
        canvas,
        s._planeAt,
        s._planeTurn,
        1,
        1,
        stroke: [
          (10 + b * 26, (0.12 + 0.14 * (1 - b)) * halo),
          (6.0, (0.45 + 0.4 * b) * halo),
        ],
      );
    }
    if (inLogo && s._planeOpacity > 0) {
      _paintPlane(
        canvas,
        s._planeAt,
        s._planeTurn,
        s._planeScale,
        1,
        opacity: s._planeOpacity * s._logoFade,
      );
    }
    canvas.restore();
  }

  void _paintPlane(
    Canvas canvas,
    Offset at,
    double turn,
    double scale,
    double bank, {
    double opacity = 1,
    List<(double, double)> stroke = const [],
  }) {
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(turn)
      ..scale(scale, scale * bank)
      ..rotate(-FlightPlan.heading)
      ..translate(-logoPlaneCenterX, -logoPlaneCenterY);
    for (final (width, alpha) in stroke) {
      canvas.drawPath(
        s._plane,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width
          ..color = _K.accent.withValues(alpha: alpha),
      );
    }
    if (stroke.isEmpty) {
      canvas.drawPath(s._plane, Paint()..color = _K.ink.withValues(alpha: opacity));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => true;
}
