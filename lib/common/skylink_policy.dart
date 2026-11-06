import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:prism_ui/prism_ui.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Clash clients default to 7890, so a second one on the machine would take
/// it; ours starts on a port few programs use and moves on if it is held.
const _preferredPort = 52790;

/// Settings the app holds whatever was saved: users never see them.
Future<void> applySkylinkPolicy(WidgetRef ref) async {
  if (Platform.isWindows) await _clearStaleProxy();
  ref.read(setupActionProvider.notifier).changeMode(Mode.global);
  ref
      .read(appSettingProvider.notifier)
      .update(
        (state) => state.copyWith(minimizeOnExit: true, autoCheckUpdate: false),
      );
  ref
      .read(themeSettingProvider.notifier)
      .update((state) => state.copyWith(themeMode: ThemeMode.dark));
  ref
      .read(networkSettingProvider.notifier)
      .update((state) => state.copyWith(systemProxy: true));
  final config = ref.read(patchClashConfigProvider);
  final port = await _freePort(
    config.mixedPort == defaultMixedPort ? _preferredPort : config.mixedPort,
    running: ref.read(isStartProvider),
  );
  ref
      .read(patchClashConfigProvider.notifier)
      .update(
        (state) => state.copyWith(
          mixedPort: port,
          tun: state.tun.copyWith(enable: false),
        ),
      );
}

/// A force-quit or power loss leaves Windows pointing at a port nobody
/// listens on; the runner's own mode clears that, and only that.
Future<void> _clearStaleProxy() async {
  try {
    await Process.run(Platform.resolvedExecutable, ['--clear-stale-proxy']);
  } catch (e) {
    commonPrint.log('clear stale proxy: $e');
  }
}

Future<int> _freePort(int wanted, {required bool running}) async {
  if (running) return wanted;
  for (var port = wanted; port < wanted + 20; port++) {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return port;
    } on SocketException {
      continue;
    }
  }
  return wanted;
}
