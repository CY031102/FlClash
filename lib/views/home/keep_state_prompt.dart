import 'package:fl_clash/common/brand.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

import 'skylink_motion.dart';

abstract final class _P {
  static const bg = Color(0xFF191D2B);
  static const surface = Color(0xFF252B3E);
  static const surfaceHi = Color(0xFF323A52);
  static const text = Color(0xFFF3F5FA);
  static const body = Color(0xFFC5CBDB);
  static const muted = Color(0xFF8C95AD);
  static const faint = Color(0xFF646C85);
  static const accent = Color(0xFF3DB4F2);
  static const success = Color(0xFF35D39A);
}

/// Asked once, on the first exit with the proxy still on. A looping
/// demonstration above the words shows where the answer can be changed.
class KeepStatePrompt extends StatelessWidget {
  const KeepStatePrompt({
    super.key,
    required this.initial,
    required this.onAnswer,
  });

  final String initial;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    TextStyle style(AppTextStyle s, Color color, {bool strong = false}) =>
        s.of(context, emphasized: strong).copyWith(color: color);
    Widget button(String label, Color fill, Color ink, bool answer) => Expanded(
      child: GestureDetector(
        onTap: () => onAnswer(answer),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: DecoratedBox(
            decoration: ShapeDecoration(color: fill, shape: AppShape.all(11)),
            child: SizedBox(
              height: 38,
              child: Center(
                child: Text(
                  label,
                  style: style(AppTextStyle.subheadline, ink, strong: answer),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: const Color(0xB80D1019),
      child: Center(
        child: SizedBox(
          width: 336,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: _P.surface,
              shape: AppShape.all(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Demonstration(initial: initial),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '下次打開時自動連線？',
                          style: style(
                            AppTextStyle.headline,
                            _P.text,
                            strong: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '現在是已連線的狀態。\n'
                          '開啟「保持最後狀態」後，\n'
                          '下次打開會回到退出時的狀態。',
                          style: style(
                            AppTextStyle.footnote,
                            _P.body,
                          ).copyWith(height: 1.75),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '以後可以在頭像的「設定」裡修改',
                          style: style(AppTextStyle.caption1, _P.muted),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            button('不用了', _P.surfaceHi, _P.text, false),
                            const SizedBox(width: 10),
                            button('開啟', _P.accent, _P.bg, true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The home screen in small: a cursor taps the avatar, then 設定, then ticks
/// 保持最後狀態, and it starts over.
class _Demonstration extends StatefulWidget {
  const _Demonstration({required this.initial});

  final String initial;

  @override
  State<_Demonstration> createState() => _DemonstrationState();
}

class _DemonstrationState extends State<_Demonstration>
    with SingleTickerProviderStateMixin {
  static const _loopMs = 6600.0;
  static const _width = 308.0;
  static const _height = 124.0;
  static const _start = Offset(84, 92);
  static const _avatar = Offset(283, 22);
  static const _settings = Offset(214, 94);
  static const _tick = Offset(165, 94);

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _span(double ms, double from, double to) =>
      Motion.curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final small = AppTextStyle.caption2.of(context);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: AppShape.all(12)),
      child: SizedBox(
        height: _height,
        child: ColoredBox(
          color: _P.bg,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final ms = _controller.value * _loopMs;
              final cursor = Offset.lerp(
                Offset.lerp(
                  Offset.lerp(_start, _avatar, _span(ms, 600, 1300)),
                  _settings,
                  _span(ms, 2200, 2900),
                ),
                _tick,
                _span(ms, 3600, 4300),
              )!;
              final out = 1 - _span(ms, 6000, 6400);
              final menu = _span(ms, 1550, 1730) * out;
              final page = _span(ms, 3050, 3300);
              final ticked = ms >= 4450;
              final tap = [1400.0, 3000.0, 4450.0]
                  .map((at) => (ms - at) / 500)
                  .where((k) => k >= 0 && k < 1)
                  .firstOrNull;
              return Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: 11,
                    child: Text(
                      brandName,
                      style: small.copyWith(color: _P.faint),
                    ),
                  ),
                  const Positioned(
                    left: (_width - 56) / 2,
                    top: 34,
                    child: SizedBox.square(
                      dimension: 56,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: Color(0xFF2C4F6E),
                          shape: CircleBorder(
                            side: BorderSide(color: _P.bg, width: 4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 9,
                    child: _MiniAvatar(initial: widget.initial, style: small),
                  ),
                  if (menu > 0)
                    Positioned(
                      right: 10,
                      top: 38,
                      child: Opacity(
                        opacity: menu,
                        child: _MiniMenu(
                          page: page,
                          ticked: ticked,
                          style: small,
                        ),
                      ),
                    ),
                  if (tap != null)
                    Positioned(
                      left: cursor.dx - 18,
                      top: cursor.dy - 18,
                      child: SizedBox.square(
                        dimension: 36,
                        child: Transform.scale(
                          scale: 0.5 + 0.65 * tap,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: CircleBorder(
                                side: BorderSide(
                                  color: _P.accent.withValues(
                                    alpha: 0.9 * (1 - tap),
                                  ),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: cursor.dx,
                    top: cursor.dy,
                    child: Opacity(
                      opacity: _span(ms, 200, 500) * out,
                      child: const CustomPaint(
                        size: Size(12, 17),
                        painter: _CursorPainter(),
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
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.initial, required this.style});

  final String initial;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const ShapeDecoration(
                color: _P.surface,
                shape: AppShape.circle,
              ),
              child: Center(
                child: Text(initial, style: style.copyWith(color: _P.muted)),
              ),
            ),
          ),
          const Positioned(
            right: -2,
            bottom: -2,
            child: StatusDot(color: _P.success, dimension: 9, ring: _P.bg),
          ),
        ],
      ),
    );
  }
}

class _MiniMenu extends StatelessWidget {
  const _MiniMenu({
    required this.page,
    required this.ticked,
    required this.style,
  });

  /// 0 on the menu, 1 on its settings page.
  final double page;
  final bool ticked;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    Widget row(String text, {Widget? lead, bool arrow = false}) => SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 6)],
            Expanded(
              child: Text(text, style: style.copyWith(color: _P.text)),
            ),
            if (arrow) Text('›', style: style.copyWith(color: _P.muted)),
          ],
        ),
      ),
    );
    Widget box(bool on) => SizedBox.square(
      dimension: 10,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: on ? _P.accent : const Color(0x00000000),
          shape: AppShape.all(3).copyWith(
            side: BorderSide(color: on ? _P.accent : _P.muted, width: 1.2),
          ),
        ),
      ),
    );
    final first = Column(
      mainAxisSize: MainAxisSize.min,
      children: [row('方案與續費'), row('客服'), row('設定', arrow: true)],
    );
    final second = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row('‹  設定'),
        row('開機自啟動', lead: box(false)),
        row('保持最後狀態', lead: box(ticked)),
      ],
    );
    return DecoratedBox(
      decoration: ShapeDecoration(color: _P.surface, shape: AppShape.all(9)),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 120 + 30 * page,
          child: Stack(
            children: [
              Opacity(opacity: 1 - page, child: first),
              Opacity(opacity: page, child: second),
            ],
          ),
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  const _CursorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arrow = Path()
      ..moveTo(0, 0)
      ..lineTo(0, h * 0.82)
      ..lineTo(w * 0.3, h * 0.62)
      ..lineTo(w * 0.52, h)
      ..lineTo(w * 0.72, h * 0.92)
      ..lineTo(w * 0.5, h * 0.56)
      ..lineTo(w * 0.86, h * 0.56)
      ..close();
    canvas
      ..drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = _P.bg,
      )
      ..drawPath(arrow, Paint()..color = _P.text);
  }

  @override
  bool shouldRepaint(_CursorPainter oldDelegate) => false;
}
