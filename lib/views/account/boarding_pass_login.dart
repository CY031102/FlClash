import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'flight_plan.dart';
import 'login.dart';
import 'logo_data.dart';

/// Shown over the whole app while it is true: on a first launch with no
/// profile, and when the user chooses to sign in from the profiles page.
final loginGateVisible = ValueNotifier<bool>(false);

void openLoginGate() => loginGateVisible.value = true;

class LoginGate extends StatelessWidget {
  const LoginGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: loginGateVisible,
      builder: (context, visible, child) => Stack(
        children: [
          child!,
          if (visible)
            Positioned.fill(
              child: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const BoardingPassLogin()),
                ],
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}

abstract final class _C {
  static const bg = Color(0xFF191D2B);
  static const surface = Color(0xFF252B3E);
  static const surfaceHi = Color(0xFF323A52);
  static const text = Color(0xFFF3F5FA);
  static const muted = Color(0xFF8C95AD);
  static const accent = Color(0xFF3DB4F2);
  static const danger = Color(0xFFFF6B7E);
  static const success = Color(0xFF35D39A);
  static const warning = Color(0xFFF2B84B);
}

enum _Phase { idle, pull, expand, fly, hover, leave, crash }

enum _Server { checking, ok, down }

class BoardingPassLogin extends ConsumerStatefulWidget {
  const BoardingPassLogin({super.key});

  @override
  ConsumerState<BoardingPassLogin> createState() => _BoardingPassLoginState();
}

class _BoardingPassLoginState extends ConsumerState<BoardingPassLogin>
    with SingleTickerProviderStateMixin {
  static const _passWidth = 470.0;
  static const _passHeight = 214.0;
  static const _stubWidth = 86.0;
  static const _tearDistance = 70.0;
  static const _pullMs = 300;
  static const _expandMs = 850;
  static const _earliestCrashMs = 1200;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _api = PanelApi();
  final _plan = FlightPlan.instance;
  final _plane = parseOutline(logoPlanePath);
  final _text = parseOutline(logoTextPath)..fillType = PathFillType.evenOdd;
  late final _ink = _InkCache(_plan);
  late final Ticker _ticker = createTicker(_tick);

  Duration _now = Duration.zero;
  Duration _base = Duration.zero;
  _Phase _phase = _Phase.idle;
  Duration _phaseAt = Duration.zero;
  _Server _server = _Server.checking;
  bool _remember = true;
  bool _obscure = true;

  double _drag = 0;
  double _snapFrom = 0;
  Duration? _snapAt;
  _StubPose _stubFrom = const _StubPose();
  Duration? _wiggleAt;
  Duration? _stampAt;
  String? _error;
  int _badField = 0;

  bool _loginDone = false;
  String? _loginFailure;
  Duration _flyAt = Duration.zero;
  Duration _hoverAt = Duration.zero;
  PlanePose? _crashPose;

  bool get _busy => _phase != _Phase.idle;

  bool get _canClose => ref.read(profilesProvider).isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccount());
    unawaited(_checkServer());
  }

  Future<void> _loadAccount() async {
    final last = await loadLastPanelAccount();
    if (last != null && mounted && _email.text.isEmpty) {
      _email.text = last;
    }
  }

  Future<void> _checkServer() async {
    final ok = await _api.ping();
    if (mounted) setState(() => _server = ok ? _Server.ok : _Server.down);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ink.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// The ticker restarts from zero; [_now] carries on from where it stopped
  /// so moments recorded while it was idle stay in the past.
  void _run() {
    if (!_ticker.isActive) {
      _base = _now;
      _ticker.start();
    }
  }

  int _since(Duration at) => (_now - at).inMilliseconds;

  void _go(_Phase phase) {
    _phase = phase;
    _phaseAt = _now;
  }

  void _tick(Duration elapsed) {
    _now = _base + elapsed;
    switch (_phase) {
      case _Phase.idle:
        final animating = [_snapAt, _wiggleAt, _stampAt]
            .whereType<Duration>()
            .any((at) => _since(at) < 800);
        if (!animating) _ticker.stop();
      case _Phase.pull:
        if (_since(_phaseAt) >= _pullMs) _startExpand();
      case _Phase.expand:
        if (_since(_phaseAt) >= _expandMs) {
          _flyAt = _now;
          _ink.reset();
          _go(_Phase.fly);
        }
      case _Phase.fly:
        final frame = _since(_flyAt) / 1000 * FlightPlan.fps;
        final pose = _plan.poseAt(frame);
        if (_loginFailure != null && _since(_flyAt) >= _earliestCrashMs) {
          _startCrash(pose);
        } else {
          _ink.advanceTo(pose.distance);
          if (frame >= _plan.frameCount) {
            _ink.advanceTo(_plan.length);
            _hoverAt = _now;
            _go(_Phase.hover);
          }
        }
      case _Phase.hover:
        if (_loginFailure != null) {
          _startCrash(_plan.poseAt(_plan.frameCount.toDouble()));
        } else if (_loginDone && _since(_hoverAt) > 1000) {
          _go(_Phase.leave);
        }
      case _Phase.leave:
        if (_since(_phaseAt) >= 600) {
          _ticker.stop();
          loginGateVisible.value = false;
          return;
        }
      case _Phase.crash:
        if (_since(_phaseAt) >= 4500) {
          _phase = _Phase.idle;
          _showRefusal(_loginFailure ?? '登入失敗，請稍後再試', 0);
        }
    }
    setState(() {});
  }

  String? _validate() {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _badField = 1;
      return '請輸入正確的電子郵件';
    }
    if (_password.text.isEmpty) {
      _badField = 2;
      return '請輸入密碼';
    }
    if (_password.text.length < 8) {
      _badField = 2;
      return '密碼至少 8 位';
    }
    return null;
  }

  void _clearError() {
    if (_error == null && _stampAt == null) return;
    setState(() {
      _error = null;
      _stampAt = null;
      _badField = 0;
    });
  }

  void _showRefusal(String message, int badField) {
    _error = message;
    _badField = badField;
    _stampAt = _now;
    _run();
  }

  void _tear({required bool dragged}) {
    if (_busy) return;
    _run();
    final invalid = _validate();
    if (invalid != null) {
      _snapFrom = _drag;
      _snapAt = _now;
      _drag = 0;
      _wiggleAt = _now;
      setState(() => _showRefusal(invalid, _badField));
      return;
    }
    setState(() {
      _error = null;
      _stampAt = null;
      _badField = 0;
      _loginDone = false;
      _loginFailure = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_signIn(_email.text.trim(), _password.text));
    if (dragged) {
      _stubFrom = _StubPose.dragged(_drag);
      _startExpand();
    } else {
      _stubFrom = const _StubPose();
      _go(_Phase.pull);
    }
  }

  void _startExpand() {
    if (_phase == _Phase.pull) _stubFrom = const _StubPose.pulled();
    _drag = 0;
    _go(_Phase.expand);
  }

  void _startCrash(PlanePose pose) {
    _crashPose = pose;
    _go(_Phase.crash);
  }

  Future<void> _signIn(String email, String password) async {
    try {
      final url = await _api.login(email, password);
      await saveLastPanelAccount(email, remember: _remember);
      await importPanelSubscription(ref, url);
      ref.read(currentPageLabelProvider.notifier).value = PageLabel.dashboard;
      _loginDone = true;
    } on PanelLoginException catch (e) {
      _loginFailure = e.message;
    } catch (e) {
      commonPrint.log('panel login: $e');
      _loginFailure = '登入失敗，請稍後再試';
    }
  }

  _StubPose _stubPose() {
    switch (_phase) {
      case _Phase.idle:
        var dx = _drag;
        final snapAt = _snapAt;
        if (snapAt != null && _drag == 0) {
          final k = (_since(snapAt) / 350).clamp(0.0, 1.0);
          dx = _snapFrom * (1 - Curves.easeOutBack.transform(k));
        }
        var pose = _StubPose.dragged(dx);
        final wiggleAt = _wiggleAt;
        if (wiggleAt != null && _since(wiggleAt) < 350) {
          final t = _since(wiggleAt) / 350;
          pose = pose.rotated(math.sin(t * math.pi * 2) * 3 * (1 - t));
        }
        return pose;
      case _Phase.pull:
        final k = Curves.easeIn.transform(
          (_since(_phaseAt) / _pullMs).clamp(0.0, 1.0),
        );
        return _StubPose.lerp(const _StubPose(), const _StubPose.pulled(), k);
      case _Phase.crash:
        final t = _since(_phaseAt);
        if (t >= 3800) {
          final k = Curves.easeOutBack.transform(
            ((t - 3800) / 700).clamp(0.0, 1.0),
          );
          return _StubPose.lerp(const _StubPose.flown(), const _StubPose(), k);
        }
        return const _StubPose.flown();
      case _Phase.expand:
        final k = Curves.easeIn.transform(
          (_since(_phaseAt) / 750).clamp(0.0, 1.0),
        );
        return _StubPose.lerp(_stubFrom, const _StubPose.flown(), k);
      case _Phase.fly:
      case _Phase.hover:
      case _Phase.leave:
        return const _StubPose.flown();
    }
  }

  double _blobProgress() {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.pull:
        return 0;
      case _Phase.expand:
        return const Cubic(0.55, 0, 0.35, 1).transform(
          (_since(_phaseAt) / _expandMs).clamp(0.0, 1.0),
        );
      case _Phase.fly:
      case _Phase.hover:
      case _Phase.leave:
        return 1;
      case _Phase.crash:
        final t = _since(_phaseAt);
        if (t < 3000) return 1;
        return 1 -
            const Cubic(0.5, 0, 0.3, 1).transform(
              ((t - 3000) / 800).clamp(0.0, 1.0),
            );
    }
  }

  double _logoOpacity() {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.pull:
        return 0;
      case _Phase.expand:
        return 0;
      case _Phase.fly:
        return (_since(_flyAt) / 350).clamp(0.0, 1.0);
      case _Phase.hover:
      case _Phase.leave:
        return 1;
      case _Phase.crash:
        final t = _since(_phaseAt);
        return t < 3000 ? 1 : (1 - (t - 3000) / 600).clamp(0.0, 1.0);
    }
  }

  double _shake() {
    final at = _stampAt;
    if (at == null) return 0;
    final t = _since(at) / 450;
    if (t >= 1) return 0;
    return math.sin(t * math.pi * 4) * 8 * (1 - t);
  }

  _FlightFrame _flightFrame() {
    if (_phase == _Phase.crash) {
      final p = _crashPose!;
      final t = _since(_phaseAt).toDouble();
      var dx = 0.0;
      var dy = 0.0;
      var extra = 0.0;
      var down = math.pi / 2 - p.rotation - logoPlaneHeadingDegrees * math.pi / 180;
      down = math.atan2(math.sin(down), math.cos(down));
      if (t < 600) {
        dx = math.sin(t / 30) * 2 * (1 - t / 600);
        extra = math.sin(t / 45) * 6 * math.pi / 180;
      } else {
        final k = math.min(1.0, (t - 600) / 1400);
        extra = down * (1 - math.pow(1 - k, 2));
        dy = k * k * 90;
      }
      return _FlightFrame(
        pose: p,
        dx: dx,
        dy: dy,
        extraRotation: extra,
        planeOpacity: t < 2000 ? 1 : (1 - (t - 2000) / 300).clamp(0.0, 1.0),
        inkOpacity: t < 2000 ? 1 : 1 - 0.7 * ((t - 2000) / 1000).clamp(0.0, 1.0),
        textOpacity: 0,
        puff: t >= 2000 ? ((t - 2000) / 1200).clamp(0.0, 1.0) : null,
        puffAt: Offset(p.x, p.y + 90 + 15),
      );
    }
    if (_phase == _Phase.fly) {
      return _FlightFrame(
        pose: _plan.poseAt(_since(_flyAt) / 1000 * FlightPlan.fps),
      );
    }
    final rest = _plan.poseAt(_plan.frameCount.toDouble());
    final t = _since(_hoverAt).toDouble();
    return _FlightFrame(
      pose: rest,
      dy: math.sin(t / 500) * 5 * FlightPlan.smoothStep(t / 800),
      textOpacity: (t / 800).clamp(0.0, 1.0),
    );
  }

  TextStyle _style(AppTextStyle s, Color color, {bool strong = false}) =>
      s.of(context, emphasized: strong).copyWith(color: color);

  @override
  Widget build(BuildContext context) {
    final leaving = _phase == _Phase.leave
        ? 1 - (_since(_phaseAt) / 600).clamp(0.0, 1.0)
        : 1.0;
    return Opacity(
      opacity: leaving,
      child: ColoredBox(
        color: _C.bg,
        child: DefaultTextStyle(
          style: _style(AppTextStyle.subheadline, _C.text),
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              final passLeft = (size.width - _passWidth) / 2;
              final passTop = math.max(64.0, (size.height - _passHeight) / 2 - 30);
              final tear = Offset(
                passLeft + _passWidth - _stubWidth + 2,
                passTop + _passHeight / 2,
              );
              final reach = [
                tear,
                Offset(size.width - tear.dx, tear.dy),
                Offset(tear.dx, size.height - tear.dy),
                Offset(size.width - tear.dx, size.height - tear.dy),
              ].map((o) => o.distance).reduce(math.max);
              final blob = _blobProgress();
              final logo = _logoOpacity();
              final logoWidth = math.min(
                size.width * 0.55,
                size.height * 0.78 * logoViewWidth / logoViewHeight,
              );
              return Stack(
                children: [
                  _buildHeader(),
                  Positioned(
                    left: passLeft + _shake(),
                    top: passTop,
                    width: _passWidth,
                    height: _passHeight,
                    child: _buildPass(),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: passTop + _passHeight + 18,
                    child: AnimatedOpacity(
                      opacity: _error == null ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _error ?? '',
                        textAlign: TextAlign.center,
                        style: _style(AppTextStyle.footnote, _C.danger),
                      ),
                    ),
                  ),
                  Positioned(
                    left: passLeft,
                    width: _passWidth,
                    top: passTop + _passHeight + 48,
                    child: _buildLinks(),
                  ),
                  if (blob > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BlobPainter(tear, reach * blob),
                        ),
                      ),
                    ),
                  if (logo > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Opacity(
                            opacity: logo,
                            child: SizedBox(
                              width: logoWidth,
                              height: logoWidth * logoViewHeight / logoViewWidth,
                              child: CustomPaint(
                                painter: _FlightPainter(
                                  ink: _ink,
                                  plane: _plane,
                                  text: _text,
                                  frame: _flightFrame(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final (color, label) = switch (_server) {
      _Server.checking => (_C.warning, '正在檢查伺服器…'),
      _Server.ok => (_C.success, '伺服器正常'),
      _Server.down => (_C.danger, '無法連線到伺服器'),
    };
    return Positioned(
      left: 22,
      right: 18,
      top: 16,
      child: Row(
        children: [
          Text(
            brandName,
            style: _style(AppTextStyle.headline, _C.text, strong: true),
          ),
          const Spacer(),
          SizedBox.square(
            dimension: 8,
            child: DecoratedBox(
              decoration: ShapeDecoration(color: color, shape: AppShape.circle),
            ),
          ),
          const SizedBox(width: 7),
          Text(label, style: _style(AppTextStyle.caption1, _C.muted)),
          if (_canClose && !_busy) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => loginGateVisible.value = false,
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GlyphIcon(AppGlyphs.close, size: 20, color: _C.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: _style(
        AppTextStyle.caption2,
        _C.muted,
      ).copyWith(letterSpacing: 1),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool bad,
    bool obscure = false,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
    Widget? trailing,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: bad ? _C.danger : _C.surfaceHi),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: EditableText(
                controller: controller,
                focusNode: focusNode,
                readOnly: _busy,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: obscure
                    ? TextInputType.visiblePassword
                    : TextInputType.emailAddress,
                textInputAction: action,
                onChanged: (_) => _clearError(),
                onSubmitted: onSubmitted,
                style: _style(AppTextStyle.subheadline, _C.text),
                cursorColor: _C.accent,
                backgroundCursorColor: _C.muted,
                selectionColor: _C.accent.withValues(alpha: 0.35),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildPass() {
    final stub = _stubPose();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          right: _stubWidth,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: _C.surface,
              shape: AppShape.of(
                const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'BOARDING PASS 登機證',
                        style: _style(
                          AppTextStyle.footnote,
                          _C.accent,
                          strong: true,
                        ).copyWith(letterSpacing: 1),
                      ),
                      if (isTestPanel) ...[
                        const SizedBox(width: 8),
                        Text(
                          '測試服',
                          style: _style(AppTextStyle.caption2, _C.warning),
                        ),
                      ],
                      const Spacer(),
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _PlaneIconPainter(_plane, _C.accent),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _label('PASSENGER 乘客 · 電子郵件'),
                  _field(
                    controller: _email,
                    focusNode: _emailFocus,
                    bad: _badField == 1,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 10),
                  _label('PASSCODE 通行碼 · 密碼'),
                  _field(
                    controller: _password,
                    focusNode: _passwordFocus,
                    bad: _badField == 2,
                    obscure: _obscure,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _tear(dragged: false),
                    trailing: GestureDetector(
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GlyphIcon(
                          _obscure ? AppGlyphs.eye : AppGlyphs.eyeOff,
                          size: 18,
                          color: _C.muted,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      for (final (k, v) in const [
                        ('FROM', 'HOME'),
                        ('TO', 'WORLD'),
                        ('GATE', 'A1'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _label(k),
                              Text(
                                v,
                                style: _style(
                                  AppTextStyle.callout,
                                  _C.text,
                                  strong: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(right: 16 + _stubWidth, top: 70, child: _buildStamp()),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: _stubWidth,
          child: Transform(
            alignment: Alignment.bottomLeft,
            transform: Matrix4.translationValues(stub.dx, stub.dy, 0)
              ..rotateZ(stub.angle * math.pi / 180),
            child: _buildStub(),
          ),
        ),
      ],
    );
  }

  Widget _buildStamp() {
    final at = _stampAt;
    if (at == null) return const SizedBox.shrink();
    final k = (_since(at) / 250).clamp(0.0, 1.0);
    final scale = 2.5 - 1.5 * Curves.easeOutBack.transform(k);
    return IgnorePointer(
      child: Opacity(
        opacity: k,
        child: Transform.rotate(
          angle: -14 * math.pi / 180,
          child: Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShape.all(8).copyWith(
                  side: const BorderSide(color: _C.danger, width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  '拒絕登機',
                  style: _style(
                    AppTextStyle.callout,
                    _C.danger,
                    strong: true,
                  ).copyWith(letterSpacing: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStub() {
    return MouseRegion(
      cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tear(dragged: false),
        onHorizontalDragStart: (_) {
          if (_busy) return;
          _snapAt = null;
        },
        onHorizontalDragUpdate: (d) {
          if (_busy) return;
          setState(() => _drag = math.max(0, _drag + d.delta.dx));
        },
        onHorizontalDragEnd: (_) {
          if (_busy) return;
          if (_drag > _tearDistance) {
            _tear(dragged: true);
          } else {
            _snapFrom = _drag;
            _snapAt = _now;
            _drag = 0;
            _run();
          }
        },
        child: CustomPaint(
          painter: const _StubPainter(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const GlyphIcon(
                AppGlyphs.chevronForward,
                size: 22,
                color: _C.bg,
              ),
              const SizedBox(height: 8),
              for (final ch in '撕下登機'.characters)
                Text(
                  ch,
                  style: _style(AppTextStyle.subheadline, _C.bg, strong: true),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinks() {
    final link = _style(AppTextStyle.caption1, _C.accent);
    final muted = _style(AppTextStyle.caption1, _C.muted);
    return Row(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: Checkbox(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? true),
          ),
        ),
        const SizedBox(width: 2),
        Text('記住帳號', style: muted),
        const Spacer(),
        _Link(
          text: '忘記密碼？',
          style: muted,
          onTap: () => unawaited(dialogs.openUrl(panelForgotPasswordUrl)),
        ),
        Text('  ·  還沒有帳號？', style: muted),
        _Link(
          text: '註冊',
          style: link,
          onTap: () => unawaited(dialogs.openUrl(panelRegisterUrl)),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.text, required this.style, required this.onTap});

  final String text;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(text, style: style),
      ),
    );
  }
}

class _StubPose {
  const _StubPose({this.dx = 0, this.dy = 0, this.angle = 0});

  const _StubPose.pulled() : dx = 8, dy = 0, angle = 5;

  const _StubPose.flown() : dx = 140, dy = 300, angle = 40;

  factory _StubPose.dragged(double drag) =>
      _StubPose(dx: drag * 0.7, angle: math.min(14, drag * 0.12));

  final double dx;
  final double dy;

  /// Degrees, about the stub's bottom-left corner.
  final double angle;

  _StubPose rotated(double degrees) =>
      _StubPose(dx: dx, dy: dy, angle: angle + degrees);

  static _StubPose lerp(_StubPose a, _StubPose b, double t) => _StubPose(
    dx: a.dx + (b.dx - a.dx) * t,
    dy: a.dy + (b.dy - a.dy) * t,
    angle: a.angle + (b.angle - a.angle) * t,
  );
}

class _StubPainter extends CustomPainter {
  const _StubPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shape = AppShape.of(
      const BorderRadius.horizontal(right: Radius.circular(16)),
    );
    canvas.drawPath(
      shape.getOuterPath(Offset.zero & size),
      Paint()..color = _C.accent,
    );
    final dash = Paint()
      ..color = _C.bg
      ..strokeWidth = 2;
    for (var y = 4.0; y < size.height - 4; y += 9) {
      canvas.drawLine(Offset(1, y), Offset(1, math.min(y + 5, size.height)), dash);
    }
  }

  @override
  bool shouldRepaint(_StubPainter oldDelegate) => false;
}

class _PlaneIconPainter extends CustomPainter {
  const _PlaneIconPainter(this.plane, this.color);

  final Path plane;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = plane.getBounds();
    final scale = size.width / bounds.longestSide;
    canvas
      ..translate(
        (size.width - bounds.width * scale) / 2,
        (size.height - bounds.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    canvas.drawPath(plane, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlaneIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.centre, this.radius);

  final Offset centre;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(centre, radius, Paint()..color = _C.accent);
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.centre != centre;
}

class _FlightFrame {
  const _FlightFrame({
    required this.pose,
    this.dx = 0,
    this.dy = 0,
    this.extraRotation = 0,
    this.planeOpacity = 1,
    this.inkOpacity = 1,
    this.textOpacity = 0,
    this.puff,
    this.puffAt = Offset.zero,
  });

  final PlanePose pose;
  final double dx;
  final double dy;
  final double extraRotation;
  final double planeOpacity;
  final double inkOpacity;
  final double textOpacity;

  /// 0 to 1 through the smoke after a crash; null before it.
  final double? puff;
  final Offset puffAt;
}

/// The line drawn so far, kept as a picture so each frame adds only the
/// segments the pen covered since the last one.
class _InkCache {
  _InkCache(this.plan);

  final FlightPlan plan;
  ui.Picture? _picture;
  int _drawn = 0;

  ui.Picture? get picture => _picture;

  void reset() {
    _picture?.dispose();
    _picture = null;
    _drawn = 0;
  }

  void advanceTo(double distance) {
    final to = math.min(
      plan.sampleCount - 1,
      (distance / FlightPlan.step).floor(),
    );
    if (to <= _drawn) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final old = _picture;
    if (old != null) canvas.drawPicture(old);
    final paint = Paint()
      ..color = _C.bg
      ..strokeCap = StrokeCap.round;
    for (var i = _drawn; i < to; i++) {
      paint.strokeWidth = (plan.widths[i] + plan.widths[i + 1]) / 2;
      canvas.drawLine(
        Offset(plan.xs[i], plan.ys[i]),
        Offset(plan.xs[i + 1], plan.ys[i + 1]),
        paint,
      );
    }
    _picture = recorder.endRecording();
    old?.dispose();
    _drawn = to;
  }

  void dispose() => _picture?.dispose();
}

class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.ink,
    required this.plane,
    required this.text,
    required this.frame,
  });

  final _InkCache ink;
  final Path plane;
  final Path text;
  final _FlightFrame frame;

  static final _puffs = List.generate(7, (i) {
    final r = math.Random(i * 7919 + 3);
    return (
      dx: r.nextDouble() * 120 - 60,
      dy: -50 - r.nextDouble() * 80,
      size: 24 + r.nextDouble() * 36,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / logoViewWidth);
    final picture = ink.picture;
    if (picture != null && frame.inkOpacity > 0) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(0, 0, 0, frame.inkOpacity),
      );
      canvas.drawPicture(picture);
      canvas.restore();
    }
    if (frame.textOpacity > 0) {
      canvas.drawPath(
        text,
        Paint()..color = _C.bg.withValues(alpha: frame.textOpacity),
      );
    }
    if (frame.planeOpacity > 0) {
      final p = frame.pose;
      canvas
        ..save()
        ..translate(p.x + frame.dx, p.y + frame.dy)
        ..rotate(p.rotation + frame.extraRotation)
        ..scale(p.scale)
        ..translate(-logoPlaneCenterX, -logoPlaneCenterY)
        ..drawPath(
          plane,
          Paint()..color = _C.bg.withValues(alpha: frame.planeOpacity),
        )
        ..restore();
    }
    final puff = frame.puff;
    if (puff != null && puff < 1) {
      final e = Curves.easeOut.transform(puff);
      for (final c in _puffs) {
        canvas.drawCircle(
          frame.puffAt + Offset(c.dx * e, c.dy * e),
          c.size / 2 * (1 + 1.4 * e),
          Paint()..color = _C.bg.withValues(alpha: 0.45 * (1 - puff)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FlightPainter oldDelegate) => true;
}
