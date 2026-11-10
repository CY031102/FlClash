import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/skylink_prefs.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/account/boarding_pass_login.dart';
import 'package:fl_clash/views/account/flight_plan.dart';
import 'package:fl_clash/views/account/logo_data.dart';
import 'package:fl_clash/views/account/login.dart';
import 'package:fl_clash/views/disclaimer.dart';
import 'package:fl_clash/views/home/service_terms.dart';
import 'package:fl_clash/views/home/skylink_motion.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class _C {
  static const bg = Color(0xFF191D2B);
  static const surface = Color(0xFF252B3E);
  static const surfaceHi = Color(0xFF323A52);
  static const text = Color(0xFFF3F5FA);
  static const muted = Color(0xFF8C95AD);
  static const faint = Color(0xFF646C85);
  static const accent = Color(0xFF3DB4F2);
  static const danger = Color(0xFFFF6B7E);
  static const success = Color(0xFF35D39A);
  static const warning = Color(0xFFF2B84B);
}

const _calm = Motion.curve;

enum _Link { off, connecting, connected, trouble }

typedef _HomeView = ({
  _Link link,
  String? blocked,
  ({String text, Color color})? alert,
  String status,
  bool lapsed,
  String node,
  String account,
});

/// The whole app for its users: one switch that, on, reaches Google.
class SkylinkHome extends ConsumerStatefulWidget {
  const SkylinkHome({super.key});

  @override
  ConsumerState<SkylinkHome> createState() => _SkylinkHomeState();
}

class _SkylinkHomeState extends ConsumerState<SkylinkHome>
    with SingleTickerProviderStateMixin {
  static const _probeUrl = 'https://www.google.com/generate_204';
  static const _probeEvery = Duration(seconds: 30);

  late final Ticker _ticker = createTicker(_tick);
  final _plane = parseOutline(logoPlanePath);
  double _seconds = 0;
  double _drift = 0;

  _Link _link = _Link.off;
  Timer? _probeTimer;
  int _probeRun = 0;
  int _failures = 0;
  bool _toggling = false;

  bool _menuOpen = false;
  bool _nodesOpen = false;
  String? _tip;
  Timer? _tipTimer;
  String _initial = '';
  bool _loggingOut = false;
  bool _awaitingNetwork = false;
  _HomeView? _frozen;
  bool _guide = false;
  bool _keepLastState = false;
  bool _hover = false;
  final _switchKey = GlobalKey();
  bool _termsOpen = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    unawaited(_loadInitial());
    unawaited(_loadPrefs());
    ref.listenManual(isStartProvider, (_, running) => _onRunning(running));
    if (ref.read(isStartProvider)) _onRunning(true);
    launchNotice.addListener(_onLaunchNotice);
    loginGateVisible.addListener(_onGate);
    HardwareKeyboard.instance.addHandler(_onKey);
    networkOffline.addListener(_onNetwork);
  }

  /// Losing the network really disconnects, so the screen never claims a
  /// connection there is not; the app reconnects once the network is back
  /// unless the user turns it off meanwhile.
  void _onNetwork() {
    final setup = ref.read(setupActionProvider.notifier);
    if (networkOffline.value) {
      if (!ref.read(isStartProvider)) return;
      setState(() => _awaitingNetwork = true);
      unawaited(setup.setRunning(false));
      return;
    }
    if (!_awaitingNetwork) return;
    setState(() => _awaitingNetwork = false);
    if (ref.read(profilesProvider).isNotEmpty && !loginGateVisible.value) {
      setState(() => _link = _Link.connecting);
      unawaited(setup.setRunning(true));
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        loginGateVisible.value ||
        !(_menuOpen || _nodesOpen || _termsOpen)) {
      return false;
    }
    setState(() => _menuOpen = _nodesOpen = _termsOpen = false);
    return true;
  }

  void _onGate() {
    if (!loginGateVisible.value) unawaited(_loadInitial());
  }

  void _onLaunchNotice() {
    final text = launchNotice.value;
    if (text == null) return;
    launchNotice.value = null;
    _showTip(text);
  }

  Future<void> _loadPrefs() async {
    final guide = !await SkylinkPrefs.connectGuideDone();
    final keep = await SkylinkPrefs.keepLastState();
    if (!mounted) return;
    setState(() {
      _guide = guide;
      _keepLastState = keep;
    });
  }

  Future<void> _loadInitial() async {
    final email = await loadSignedInAccount() ?? await loadLastPanelAccount();
    if (!mounted) return;
    setState(() {
      _initial = email == null || email.isEmpty
          ? ''
          : email.characters.first.toUpperCase();
    });
  }

  @override
  void dispose() {
    launchNotice.removeListener(_onLaunchNotice);
    loginGateVisible.removeListener(_onGate);
    HardwareKeyboard.instance.removeHandler(_onKey);
    networkOffline.removeListener(_onNetwork);
    _ticker.dispose();
    _probeTimer?.cancel();
    _tipTimer?.cancel();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final next = elapsed.inMicroseconds / 1e6;
    final dt = next - _seconds;
    _seconds = next;
    final target = _link == _Link.connected ? 1.0 : 0.0;
    final step = dt / 1.6;
    _drift = target > _drift
        ? math.min(target, _drift + step)
        : math.max(target, _drift - step);
    final moving =
        _drift > 0 ||
        _link == _Link.connecting ||
        _link == _Link.connected ||
        (_guide && _link == _Link.off);
    if (moving) setState(() {});
  }

  void _onRunning(bool running) {
    _probeTimer?.cancel();
    _probeRun++;
    if (!running) {
      setState(() => _link = _Link.off);
      return;
    }
    setState(() => _link = _Link.connecting);
    _failures = 0;
    unawaited(_probe(_probeRun));
  }

  /// Through our own proxy, so "connected" means the user can reach Google.
  Future<void> _probe(int run) async {
    final port = ref.read(patchClashConfigProvider).mixedPort;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
    var ok = false;
    try {
      final request = await client
          .getUrl(Uri.parse(_probeUrl))
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      ok = response.statusCode < 400;
    } catch (e) {
      commonPrint.log('probe: $e');
    } finally {
      client.close(force: true);
    }
    if (!mounted || run != _probeRun || !ref.read(isStartProvider)) return;
    if (ok) {
      final wasConnecting = _link == _Link.connecting;
      _failures = 0;
      setState(() {
        _link = _Link.connected;
        if (_guide) {
          _guide = false;
          unawaited(SkylinkPrefs.markConnectGuideDone());
        }
      });
      if (wasConnecting) _showTip('已確認可以打開 Google');
      _reportStartup(connected: true);
      _probeTimer = Timer(_probeEvery, () => unawaited(_probe(run)));
      return;
    }
    _failures++;
    final giveUp = _link == _Link.connecting ? _failures >= 3 : _failures >= 2;
    if (giveUp) {
      setState(() => _link = _Link.trouble);
      _reportStartup(connected: false);
    }
    _probeTimer = Timer(
      Duration(seconds: _link == _Link.connected ? 5 : 4),
      () => unawaited(_probe(run)),
    );
  }

  Future<void> _toggle() async {
    if (_toggling) return;
    if (_awaitingNetwork) {
      setState(() => _awaitingNetwork = false);
      _showTip('已取消自動連線');
      return;
    }
    if (_blocked != null) {
      _showTip(_blocked!);
      return;
    }
    _toggling = true;
    setState(() {
      _menuOpen = false;
      _nodesOpen = false;
      if (!ref.read(isStartProvider)) _link = _Link.connecting;
    });
    try {
      ref.read(commonActionProvider.notifier).toggleRunning();
    } finally {
      _toggling = false;
    }
  }

  void _reportStartup({required bool connected}) {
    if (!startupReport.value) return;
    startupReport.value = false;
    unawaited(
      appTray?.notify(
        title: connected ? '$brandName 已在背景連線' : '$brandName 在背景運行中',
        body: connected ? '現在可以正常上網' : '暫時無法連線，點一下圖示查看',
      ),
    );
  }

  void _showTip(String text) {
    _tipTimer?.cancel();
    setState(() => _tip = text);
    _tipTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _tip = null);
    });
  }

  SubscriptionInfo? get _info =>
      ref.read(currentProfileProvider.select((p) => p?.subscriptionInfo));

  bool get _expired {
    final info = _info;
    if (info == null || info.expire == 0) return false;
    return DateTime.fromMillisecondsSinceEpoch(
      info.expire * 1000,
    ).isBefore(DateTime.now());
  }

  bool get _outOfData {
    final info = _info;
    if (info == null || info.total == 0) return false;
    return info.upload + info.download >= info.total;
  }

  String? get _blocked {
    if (ref.read(currentProfileProvider) == null) return '請先登入';
    if (_expired) return '套餐已過期，續費後即可使用';
    if (_outOfData) return '流量已用完，續費後即可使用';
    return null;
  }

  String _accountLine() {
    final info = _info;
    if (info == null) return '';
    final parts = <String>[];
    if (info.expire > 0) {
      final end = DateTime.fromMillisecondsSinceEpoch(info.expire * 1000);
      if (end.isBefore(DateTime.now())) {
        parts.add('已於 ${end.month} 月 ${end.day} 日到期');
      } else {
        final days = end.difference(DateTime.now()).inHours / 24;
        parts.add(days < 1 ? '今天到期' : '${days.ceil()} 天後到期');
      }
    }
    if (info.total > 0) {
      final left = math.max(0, info.total - info.upload - info.download);
      parts.add('還剩 ${_size(left)}');
    }
    return parts.join(' · ');
  }

  static String _size(int bytes) {
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).floor()} GB';
    return '${(bytes / (1024 * 1024)).floor()} MB';
  }

  ({String text, Color color})? _alert() {
    final info = _info;
    if (info == null) return null;
    if (_expired) return (text: '套餐已過期', color: _C.danger);
    if (_outOfData) return (text: '流量已用完', color: _C.danger);
    if (info.total > 0) {
      final left = info.total - info.upload - info.download;
      if (left < info.total * 0.1) {
        return (text: '流量只剩 ${_size(left)}', color: _C.warning);
      }
    }
    if (info.expire > 0) {
      final days = DateTime.fromMillisecondsSinceEpoch(
        info.expire * 1000,
      ).difference(DateTime.now()).inHours / 24;
      if (days <= 3) {
        return (text: '套餐 ${days.ceil()} 天後到期', color: _C.warning);
      }
    }
    return null;
  }

  Group? get _global => ref
      .read(groupsProvider)
      .where((g) => g.name == GroupName.GLOBAL.name)
      .firstOrNull;

  static const _notNodes = {
    'Direct',
    'Reject',
    'RejectDrop',
    'Pass',
    'Compatible',
    'Selector',
    'URLTest',
    'Fallback',
    'LoadBalance',
    'Relay',
  };

  List<Proxy> _nodes() => [
    for (final p in _global?.all ?? const <Proxy>[])
      if (!_notNodes.contains(p.type)) p,
  ];

  String _nodeLine() {
    final global = _global;
    final now = global?.now;
    if (now == null || now.isEmpty) return '自動';
    final picked = global!.all.where((p) => p.name == now).firstOrNull;
    if (picked != null && _notNodes.contains(picked.type)) {
      final inner = picked.now;
      final region = inner == null ? null : regionOf(inner);
      return region == null ? '自動' : '$region · 自動';
    }
    return now;
  }

  void _pickNode(String name) {
    setState(() => _nodesOpen = false);
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(GroupName.GLOBAL.name, name);
    _showTip('已固定使用「$name」');
  }

  void _pickAuto() {
    setState(() => _nodesOpen = false);
    final auto = _global?.all
        .where((p) => p.type == 'URLTest' || p.type == 'Fallback')
        .firstOrNull;
    if (auto != null) {
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxyDebounce(GroupName.GLOBAL.name, auto.name);
    }
    _showTip('自動選擇');
  }

  Future<void> _logout() async {
    setState(() {
      _menuOpen = false;
      _nodesOpen = false;
      _awaitingNetwork = false;
      _loggingOut = true;
    });
    final shown = Future<void>.delayed(const Duration(milliseconds: 2400));
    try {
      if (ref.read(isStartProvider)) {
        await ref.read(setupActionProvider.notifier).setRunning(false);
      }
      final profilesAction = ref.read(profilesActionProvider.notifier);
      for (final profile in [...ref.read(profilesProvider)]) {
        await profilesAction.deleteProfile(profile.id);
      }
      await savePanelAuthData(null);
      await saveSignedInAccount(null);
    } catch (e) {
      commonPrint.log('logout: $e');
    }
    await shown;
    unawaited(ref.read(systemActionProvider.notifier).updateTray());
    openLoginGate(rise: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _loggingOut = false);
  }

  /// What the screen shows, held still while signing out takes the account
  /// apart underneath the curtain.
  _HomeView _view() {
    final link = _link;
    final blocked = _blocked;
    return (
      link: link,
      blocked: blocked,
      alert: _alert(),
      status: switch (link) {
        _ when _awaitingNetwork => '等待網路…',
        _ when blocked != null && link == _Link.off => '無法連線',
        _Link.off => '未連線',
        _Link.connecting => '連線中…',
        _Link.connected => '已連線',
        _Link.trouble => '連線異常',
      },
      lapsed: _expired || _outOfData,
      node: _nodeLine(),
      account: _accountLine(),
    );
  }

  Offset _switchCentre() {
    final box = _switchKey.currentContext?.findRenderObject();
    final home = context.findRenderObject();
    if (box is! RenderBox || home is! RenderBox) {
      return const Offset(320, 150);
    }
    return box.localToGlobal(box.size.center(Offset.zero), ancestor: home);
  }

  void _openSite(String path) {
    setState(() => _menuOpen = false);
    unawaited(dialogs.openUrl('$panelApiBase/#/$path'));
  }

  TextStyle _style(AppTextStyle s, Color color, {bool strong = false}) =>
      s.of(context, emphasized: strong).copyWith(color: color);

  @override
  Widget build(BuildContext context) {
    ref.watch(currentProfileProvider);
    ref.watch(groupsProvider);
    final view = _loggingOut ? _frozen ??= _view() : _frozen = _view();
    final (:link, :blocked, :alert, :status, :lapsed, :node, :account) = view;
    return ColoredBox(
      color: _C.bg,
      child: DefaultTextStyle(
        style: _style(AppTextStyle.subheadline, _C.text),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_menuOpen || _nodesOpen) {
                    setState(() => _menuOpen = _nodesOpen = false);
                  }
                },
              ),
            ),
            Positioned(
              left: 22,
              top: 14,
              child: Text(
                brandName,
                style: _style(AppTextStyle.headline, _C.text, strong: true),
              ),
            ),
            Positioned(
              right: 18,
              top: 10,
              child: _Avatar(
                initial: _initial,
                lapsed: lapsed,
                onTap: () => setState(() {
                  _nodesOpen = false;
                  _menuOpen = !_menuOpen;
                }),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.05),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Switch(
                    key: _switchKey,
                    link: link,
                    disabled: blocked != null,
                    seconds: _seconds,
                    drift: _drift,
                    plane: _plane,
                    guide: _guide && link == _Link.off && blocked == null,
                    hover: _hover,
                    onHover: (over) => setState(() => _hover = over),
                    onTap: () => unawaited(_toggle()),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    status,
                    style: _style(
                      AppTextStyle.title2,
                      link == _Link.trouble ? _C.warning : _C.text,
                      strong: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_guide && link == _Link.off && blocked == null)
                    Text(
                      '點一下飛機開始連線',
                      style: _style(AppTextStyle.footnote, _C.accent),
                    )
                  else
                    _Pressable(
                      onTap: () => setState(() {
                        _menuOpen = false;
                        _nodesOpen = !_nodesOpen;
                      }),
                      child: Text(
                        '$node  ›',
                        style: _style(AppTextStyle.footnote, _C.muted),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    account,
                    style: _style(AppTextStyle.caption1, _C.faint),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 34,
                    child: alert == null
                        ? null
                        : _Pill(
                            text: alert.text,
                            action: '續費 →',
                            color: alert.color,
                            onTap: () => _openSite('plan'),
                          ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: ValueListenableBuilder<bool>(
                valueListenable: networkOffline,
                builder: (context, offline, tip) => offline
                    ? Text(
                        offlineMessage,
                        textAlign: TextAlign.center,
                        style: _style(AppTextStyle.caption1, _C.warning),
                      )
                    : tip!,
                child: AnimatedOpacity(
                  opacity: _tip == null ? 0 : 1,
                  duration: const Duration(milliseconds: 400),
                  curve: _calm,
                  child: Text(
                    _tip ?? '',
                    textAlign: TextAlign.center,
                    style: _style(AppTextStyle.caption1, _C.faint),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 48,
              width: 236,
              child: Reveal(
                visible: _menuOpen,
                alignment: Alignment.topRight,
                child: _Panel(
                  children: [
                    _MenuRow('方案與續費', onTap: () => _openSite('plan')),
                    _MenuRow('客服', onTap: () => _openSite('ticket')),
                    const _MenuDivider(),
                    _CheckRow(
                      '開機自啟動',
                      note: '電腦開機後自動打開 $brandName，停在工作列角落',
                      checked: ref.watch(
                        appSettingProvider.select((s) => s.autoLaunch),
                      ),
                      onTap: ref
                          .read(systemActionProvider.notifier)
                          .updateAutoLaunch,
                    ),
                    _CheckRow(
                      '保持最後狀態',
                      note: '退出時是什麼狀態，下次打開就回到什麼狀態',
                      checked: _keepLastState,
                      onTap: () {
                        setState(() => _keepLastState = !_keepLastState);
                        unawaited(SkylinkPrefs.setKeepLastState(_keepLastState));
                        unawaited(SkylinkPrefs.markKeepLastStateAsked());
                      },
                    ),
                    const _MenuDivider(),
                    _MenuRow(
                      '登出',
                      color: _C.danger,
                      onTap: () => unawaited(_logout()),
                    ),
                    _MenuRow(
                      '規範聲明',
                      color: _C.muted,
                      onTap: () => setState(() {
                        _menuOpen = false;
                        _termsOpen = true;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.4),
              child: Reveal(
                visible: _nodesOpen,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 300,
                  child: _NodeList(
                    nodes: _nodes(),
                    current: _global?.now,
                    onAuto: _pickAuto,
                    onPick: _pickNode,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Reveal(
                visible: _termsOpen,
                from: 1,
                slide: const Offset(0, 16),
                duration: Motion.medium,
                reverseDuration: Motion.short,
                child: _Terms(onClose: () => setState(() => _termsOpen = false)),
              ),
            ),
            if (_loggingOut)
              Positioned.fill(
                child: AbsorbPointer(
                  child: _LogoutCurtain(centre: _switchCentre()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "香港 01" → 香港; names the panel gives in Chinese, English or flags.
String? regionOf(String name) {
  const regions = {
    '香港': ['香港', 'HK', 'Hong Kong', '🇭🇰'],
    '台灣': ['台灣', '台湾', 'TW', 'Taiwan', '🇹🇼'],
    '日本': ['日本', 'JP', 'Japan', '🇯🇵'],
    '新加坡': ['新加坡', 'SG', 'Singapore', '🇸🇬'],
    '韓國': ['韓國', '韩国', 'KR', 'Korea', '🇰🇷'],
    '美國': ['美國', '美国', 'US', 'United States', '🇺🇸'],
    '英國': ['英國', '英国', 'UK', 'GB', '🇬🇧'],
    '德國': ['德國', '德国', 'DE', 'Germany', '🇩🇪'],
    '加拿大': ['加拿大', 'CA', 'Canada', '🇨🇦'],
  };
  for (final MapEntry(:key, :value) in regions.entries) {
    for (final word in value) {
      final latin = RegExp(r'^[A-Za-z ]+$').hasMatch(word);
      final hit = latin
          ? RegExp('(^|[^A-Za-z])${RegExp.escape(word)}([^A-Za-z]|\$)')
                .hasMatch(name)
          : name.contains(word);
      if (hit) return key;
    }
  }
  return null;
}

class _Switch extends StatelessWidget {
  const _Switch({
    super.key,
    required this.link,
    required this.disabled,
    required this.seconds,
    required this.drift,
    required this.plane,
    required this.onTap,
    this.guide = false,
    this.hover = false,
    this.onHover,
  });

  final _Link link;
  final bool disabled;
  final double seconds;
  final double drift;
  final Path plane;
  final VoidCallback onTap;

  /// A halo spreading from the ring, asking for the first connection.
  final bool guide;
  final bool hover;
  final ValueChanged<bool>? onHover;

  @override
  Widget build(BuildContext context) {
    final on = link == _Link.connected || link == _Link.trouble;
    final busy = link == _Link.connecting;
    final lit = !on && !busy && hover ? 1.0 : 0.0;
    final fill = on ? _C.accent : Color.lerp(_C.surface, _C.surfaceHi, 0.5 * lit)!;
    final glow = on ? 0.03 * math.sin(seconds * 2 * math.pi / 11) : 0.0;
    final breathe = busy ? (math.sin(seconds * 2 * math.pi / 1.6) + 1) / 2 : 0.0;
    final ringColor = on || busy
        ? _C.accent
        : Color.lerp(_C.surfaceHi, _C.accent, 0.45 * lit)!;
    final planeColor = on
        ? _C.bg
        : (busy ? _C.accent : Color.lerp(_C.muted, _C.text, 0.4 * lit)!);
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: SizedBox.square(
            dimension: 140,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (guide && !on && !busy)
                  CustomPaint(
                    size: const Size.square(140),
                    painter: _HaloPainter(seconds),
                  ),
                Transform.scale(
                  scale: 1 + 0.1 * breathe,
                  child: Opacity(
                    opacity: busy ? 1 - 0.65 * breathe : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 900),
                      curve: _calm,
                      width: 140,
                      height: 140,
                      decoration: ShapeDecoration(
                        shape: CircleBorder(
                          side: BorderSide(color: ringColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: Motion.medium,
                  curve: _calm,
                  width: 128,
                  height: 128,
                  decoration: ShapeDecoration(
                    color: Color.lerp(
                      fill,
                      glow >= 0 ? const Color(0xFFFFFFFF) : _C.bg,
                      glow.abs(),
                    ),
                    shape: AppShape.circle,
                  ),
                ),
                CustomPaint(
                  size: const Size.square(58),
                  painter: _PlanePainter(
                    plane: plane,
                    color: planeColor,
                    offset: _driftOffset(seconds) * drift,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Along the wings, never turning: two slow sines whose periods never line
  /// up, so the drift does not visibly repeat.
  static Offset _driftOffset(double t) {
    final heading = logoPlaneHeadingDegrees * math.pi / 180;
    final wing = Offset(-math.sin(heading), math.cos(heading));
    final d =
        1.7 * math.sin(t * 2 * math.pi / 6) +
        0.8 * math.sin(t * 2 * math.pi / 9.4 + math.pi);
    return wing * d;
  }
}

/// Separate Archive's guide halo, slowed to this screen's pace: a ring
/// leaves the switch's edge, spreads a little, thins and melts into the
/// background, then rests before the next.
class _HaloPainter extends CustomPainter {
  const _HaloPainter(this.seconds);

  final double seconds;

  static const _spread = 2.4;
  static const _rest = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final cycle = seconds % (_spread + _rest);
    if (cycle >= _spread) return;
    final e = (1 - math.cos(math.pi * cycle / _spread)) / 2;
    final radius = size.width / 2 + 2 + 14 * e;
    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 - 1.6 * e
        ..color = Color.lerp(_C.accent, _C.bg, math.pow(e, 0.8).toDouble())!,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.seconds != seconds;
}

class _PlanePainter extends CustomPainter {
  const _PlanePainter({
    required this.plane,
    required this.color,
    required this.offset,
  });

  final Path plane;
  final Color color;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = plane.getBounds();
    final scale = size.width / bounds.longestSide;
    canvas
      ..translate(offset.dx, offset.dy)
      ..translate(
        (size.width - bounds.width * scale) / 2,
        (size.height - bounds.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top)
      ..drawPath(plane, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlanePainter old) =>
      old.color != color || old.offset != offset;
}

/// The light on the avatar: breathing red with no network, steady red when
/// the plan has lapsed, steady green otherwise.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.lapsed,
    required this.onTap,
  });

  final String initial;
  final bool lapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: SizedBox.square(
        dimension: 30,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const ShapeDecoration(
                  color: _C.surface,
                  shape: AppShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .copyWith(color: _C.muted),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: ValueListenableBuilder<bool>(
                valueListenable: networkOffline,
                builder: (context, offline, _) => StatusDot(
                  color: offline || lapsed ? _C.danger : _C.success,
                  breathing: offline,
                  dimension: 11,
                  ring: _C.bg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pressable extends StatelessWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.action,
    required this.color,
    required this.onTap,
  });

  final String text;
  final String action;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.footnote.of(context).copyWith(color: color);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: _C.surface,
        shape: AppShape.all(17),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: style),
            const SizedBox(width: 12),
            _Pressable(
              onTap: onTap,
              child: Text(
                action,
                style: style.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: _C.surface, shape: AppShape.all(14)),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: _C.surfaceHi),
      ),
    );
  }
}

/// A switch in the menu with a line under it saying what it does.
class _CheckRow extends StatelessWidget {
  const _CheckRow(
    this.text, {
    required this.note,
    required this.checked,
    required this.onTap,
  });

  final String text;
  final String note;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedContainer(
                duration: Motion.short,
                curve: _calm,
                width: 16,
                height: 16,
                decoration: ShapeDecoration(
                  color: checked ? _C.accent : const Color(0x00000000),
                  shape: AppShape.all(5).copyWith(
                    side: BorderSide(
                      color: checked ? _C.accent : _C.muted,
                      width: 1.5,
                    ),
                  ),
                ),
                child: checked
                    ? const GlyphIcon(AppGlyphs.check, size: 12, color: _C.bg)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: _C.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: _C.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.text, {required this.onTap, this.color = _C.text});

  final String text;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          text,
          style: AppTextStyle.footnote.of(context).copyWith(color: color),
        ),
      ),
    );
  }
}

class _NodeList extends StatelessWidget {
  const _NodeList({
    required this.nodes,
    required this.current,
    required this.onAuto,
    required this.onPick,
  });

  final List<Proxy> nodes;
  final String? current;
  final VoidCallback onAuto;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final header = AppTextStyle.caption2
        .of(context)
        .copyWith(color: _C.muted, letterSpacing: 1);
    final row = AppTextStyle.footnote.of(context);
    final byRegion = <String, List<Proxy>>{};
    for (final node in nodes) {
      byRegion.putIfAbsent(regionOf(node.name) ?? '其他', () => []).add(node);
    }
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 3),
      child: Text(text, style: header),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: _Panel(
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title('推薦'),
                  _Pressable(
                    onTap: onAuto,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '自動選擇',
                              style: row.copyWith(color: _C.text),
                            ),
                          ),
                          Text(
                            '同地區優先',
                            style: row.copyWith(color: _C.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final MapEntry(key: region, value: list)
                      in byRegion.entries) ...[
                    title(region),
                    for (final node in list)
                      _Pressable(
                        onTap: () => onPick(node.name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            node.name,
                            style: row.copyWith(
                              color: node.name == current ? _C.accent : _C.text,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ATCSkylink's terms, which signing in accepts, then FlClash's disclaimer
/// and the notice its licence asks a modified copy to carry.
class _Terms extends StatelessWidget {
  const _Terms({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final title = AppTextStyle.headline
        .of(context, emphasized: true)
        .copyWith(color: _C.text);
    final heading = AppTextStyle.footnote
        .of(context, emphasized: true)
        .copyWith(color: _C.text);
    final body = AppTextStyle.caption1.of(context).copyWith(color: _C.muted);
    final section = AppTextStyle.caption2
        .of(context)
        .copyWith(color: _C.accent, letterSpacing: 1);
    Widget term(({String title, String content}) t) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title, style: heading),
          const SizedBox(height: 4),
          Text(t.content, style: body),
        ],
      ),
    );
    return ColoredBox(
      color: _C.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 18, 8),
            child: Row(
              children: [
                Text('規範聲明', style: title),
                const Spacer(),
                _Pressable(
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      '關閉',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: _C.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SmoothScrollList(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
              children: [
                Text('登入即表示你同意以下條款。', style: body),
                const SizedBox(height: 14),
                for (final t in serviceTerms) term(t),
                const SizedBox(height: 6),
                Text('FLCLASH 免責聲明', style: section),
                const SizedBox(height: 10),
                for (final t in disclaimerTerms(currentAppLocalizations))
                  term(t),
                const SizedBox(height: 6),
                Text('開源說明', style: section),
                const SizedBox(height: 10),
                Text(openSourceNotice, style: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sign-out runs the launch backwards: the dark gathers back into the plane,
/// leaving the light sky the flight is drawn on while the account is let go.
class _LogoutCurtain extends StatefulWidget {
  const _LogoutCurtain({required this.centre});

  final Offset centre;

  @override
  State<_LogoutCurtain> createState() => _LogoutCurtainState();
}

class _LogoutCurtainState extends State<_LogoutCurtain>
    with SingleTickerProviderStateMixin {
  static const _sky = Color(0xFFE9EEF5);
  static const _ink = Color(0xFF191D2B);
  static const _soft = Color(0xFF4A5570);

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _between(double ms, double from, double length) =>
      ((ms - from) / length).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final title = AppTextStyle.headline
        .of(context, emphasized: true)
        .copyWith(color: _ink);
    final note = AppTextStyle.footnote.of(context).copyWith(color: _soft);
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final ms = _controller.value * 1250;
          final cover = Motion.curve.transform(_between(ms, 0, 300));
          final gather = const Cubic(
            0.55,
            0,
            0.35,
            1,
          ).transform(_between(ms, 250, 800));
          final words = Motion.curve.transform(_between(ms, 850, 400));
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CurtainPainter(
                    centre: widget.centre,
                    cover: cover,
                    gather: gather,
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: words,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('正在登出…', style: title),
                      const SizedBox(height: 8),
                      Text('正在斷開連線並清除訂閱', style: note),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            StatusDot(
                              color: _soft,
                              breathing: words > 0,
                              half: Duration(milliseconds: 600 + i * 120),
                              dimension: 6,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CurtainPainter extends CustomPainter {
  const _CurtainPainter({
    required this.centre,
    required this.cover,
    required this.gather,
  });

  final Offset centre;
  final double cover;
  final double gather;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = [
      centre,
      Offset(size.width - centre.dx, centre.dy),
      Offset(centre.dx, size.height - centre.dy),
      Offset(size.width - centre.dx, size.height - centre.dy),
    ].map((o) => o.distance).reduce(math.max);
    if (gather > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = _LogoutCurtainState._sky,
      );
    }
    canvas.drawCircle(
      centre,
      reach * (1 - gather),
      Paint()..color = _C.bg.withValues(alpha: gather > 0 ? 1 : cover),
    );
  }

  @override
  bool shouldRepaint(_CurtainPainter oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.gather != gather ||
      oldDelegate.centre != centre;
}
