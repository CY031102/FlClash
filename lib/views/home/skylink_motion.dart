import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// The three lengths and one curve every ATCSkylink screen moves on, so
/// anything new moves like what is already there.
abstract final class Motion {
  static const short = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const long = Duration(milliseconds: 400);

  /// easeInOutSine.
  static const curve = Cubic(0.37, 0, 0.63, 1);
}

/// Fades and grows its child in from [alignment] while [visible], and back
/// out faster when it is dismissed; nothing is built while fully hidden.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.center,
    this.from = 0.95,
    this.slide = Offset.zero,
    this.duration = Motion.short,
    this.reverseDuration = const Duration(milliseconds: 100),
  });

  final bool visible;
  final Widget child;
  final Alignment alignment;
  final double from;
  final Offset slide;
  final Duration duration;
  final Duration reverseDuration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.value == 0) return const SizedBox.shrink();
        final v = Motion.curve.transform(_controller.value);
        return IgnorePointer(
          ignoring: !widget.visible,
          child: Opacity(
            opacity: v,
            child: Transform.translate(
              offset: widget.slide * (1 - v),
              child: Transform.scale(
                scale: widget.from + (1 - widget.from) * v,
                alignment: widget.alignment,
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A status light: steady, or breathing a second up and a second down.
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.breathing = false,
    this.half = const Duration(milliseconds: 1000),
    this.dimension = 8,
    this.ring,
  });

  final Color color;
  final bool breathing;
  final Duration half;
  final double dimension;

  /// Drawn around the light to set it off from what it sits on.
  final Color? ring;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.half,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.half;
    if (widget.breathing != oldWidget.breathing ||
        widget.half != oldWidget.half) {
      _sync();
    }
  }

  void _sync() {
    if (widget.breathing) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = widget.ring;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = widget.breathing
            ? 0.15 + 0.85 * Motion.curve.transform(_controller.value)
            : 1.0;
        return SizedBox.square(
          dimension: widget.dimension,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: widget.color.withValues(alpha: alpha),
              shape: ring == null
                  ? AppShape.circle
                  : CircleBorder(side: BorderSide(color: ring, width: 2)),
            ),
          ),
        );
      },
    );
  }
}

/// A list the mouse wheel glides instead of jumping a notch at a time, with
/// its top and bottom edges fading into what is behind it.
class SmoothScrollList extends StatefulWidget {
  const SmoothScrollList({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  State<SmoothScrollList> createState() => _SmoothScrollListState();
}

class _SmoothScrollListState extends State<SmoothScrollList> {
  final _controller = ScrollController();
  double? _target;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final position = _controller.position;
    final target = ((_target ?? position.pixels) + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _target = target;
    _controller
        .animateTo(target, duration: Motion.medium, curve: Curves.easeOutCubic)
        .whenComplete(() {
          if (_controller.hasClients &&
              (_controller.position.pixels - target).abs() < 0.5) {
            _target = null;
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onSignal,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, 0.06, 0.94, 1],
        ).createShader(bounds),
        child: ListView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.padding,
          children: widget.children,
        ),
      ),
    );
  }
}

/// Centres [child] as if [tail] were not there; the tail hangs off its right
/// edge, so "連線中" sits under the switch whatever follows it.
class Hanging extends StatelessWidget {
  const Hanging({super.key, required this.child, this.tail});

  final Widget child;
  final Widget? tail;

  @override
  Widget build(BuildContext context) {
    final tail = this.tail;
    if (tail == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: FractionalTranslation(
            translation: const Offset(1, 0),
            child: Align(alignment: Alignment.centerLeft, child: tail),
          ),
        ),
      ],
    );
  }
}

/// Text that changes like a breath: it dims, becomes the new words at its
/// faintest, and brightens again, never moving.
class BreathText extends StatefulWidget {
  const BreathText({
    super.key,
    required this.text,
    required this.style,
    this.tail,
  });

  final String text;
  final TextStyle style;
  final Widget? tail;

  @override
  State<BreathText> createState() => _BreathTextState();
}

class _BreathTextState extends State<BreathText>
    with SingleTickerProviderStateMixin {
  static const _dim = Duration(milliseconds: 260);
  static const _rise = Duration(milliseconds: 420);
  static const _floor = 0.12;

  late final _controller = AnimationController(vsync: this, value: 1);
  late String _text = widget.text;
  late TextStyle _style = widget.style;
  late Widget? _tail = widget.tail;
  bool _dimming = false;

  @override
  void didUpdateWidget(BreathText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _text) {
      _style = widget.style;
      _tail = widget.tail;
      return;
    }
    if (_dimming) return;
    _dimming = true;
    _controller.animateTo(0, duration: _dim, curve: Motion.curve).whenComplete(
      () {
        if (!mounted) return;
        setState(() {
          _dimming = false;
          _text = widget.text;
          _style = widget.style;
          _tail = widget.tail;
        });
        _controller.animateTo(1, duration: _rise, curve: Motion.curve);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _floor + (1 - _floor) * _controller.value,
        child: child,
      ),
      child: Hanging(tail: _tail, child: Text(_text, style: _style)),
    );
  }
}

/// Three dots that light one after another, then start over.
class WaitingDots extends StatefulWidget {
  const WaitingDots({super.key, required this.style});

  final TextStyle style;

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots>
    with SingleTickerProviderStateMixin {
  static const _stepMs = 450.0;
  static const _fadeMs = 400.0;
  static const _faint = 0.15;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacity(int dot, double ms) {
    final on = (dot + 1) * _stepMs;
    final k = ms >= on
        ? ((ms - on) / _fadeMs).clamp(0.0, 1.0)
        : 1 - (ms / _fadeMs).clamp(0.0, 1.0);
    return _faint + (1 - _faint) * Motion.curve.transform(k);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.style.color ?? const Color(0xFFFFFFFF);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _controller.value * 1800;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Text(
                '.',
                style: widget.style.copyWith(
                  color: color.withValues(alpha: _opacity(i, ms)),
                ),
              ),
          ],
        );
      },
    );
  }
}
