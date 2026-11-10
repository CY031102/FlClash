import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/account/boarding_pass_login.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart' show TextSpan;
import 'package:tray/tray.dart';

import 'app_localizations.dart';
import 'dialog.dart';
import 'app_ports.dart';
import 'constant.dart';
import 'keyboard.dart';
import 'provider_reader.dart';
import 'skylink_prefs.dart';
import 'system.dart';
import 'window.dart';

class AppTray implements TrayPort {
  static AppTray? _instance;

  final bool isMacOS;
  final bool isWindows;

  bool _isShutDown = false;

  AppTray._internal({required this.isMacOS, required this.isWindows});

  factory AppTray() {
    _instance ??= AppTray._internal(
      isMacOS: system.isMacOS,
      isWindows: system.isWindows,
    );
    return _instance!;
  }

  @visibleForTesting
  factory AppTray.forPlatform({
    required bool isMacOS,
    required bool isWindows,
  }) {
    return AppTray._internal(isMacOS: isMacOS, isWindows: isWindows);
  }

  String get _trayIconSuffix {
    return isWindows ? 'ico' : 'png';
  }

  bool _isTemplate(bool monochrome) => isMacOS && monochrome;

  String _trayIconDir(bool monochrome) {
    if (isWindows) {
      return 'assets/images/tray/windows';
    }
    return _isTemplate(monochrome)
        ? 'assets/images/tray/macos'
        : 'assets/images/tray/unix';
  }

  String getTrayIcon({
    required bool isStart,
    required bool tunEnable,
    required bool safeMode,
    bool monochrome = true,
  }) {
    final status = switch ((
      safeMode,
      _isTemplate(monochrome) || !isStart,
      tunEnable,
    )) {
      (true, _, _) => 4,
      (false, true, _) => 1,
      (false, false, false) => 2,
      (false, false, true) => 3,
    };
    return '${_trayIconDir(monochrome)}/status_$status.$_trayIconSuffix';
  }

  @override
  Future<void> shutdown() async {
    _isShutDown = true;
    // Removing a status item makes macOS forget where the user dragged it in
    // the menu bar; one that goes away with the process keeps its place.
    if (isMacOS) {
      return;
    }
    await Tray.instance.hide();
  }

  @override
  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  }) async {
    if (_isShutDown) {
      return;
    }
    await Tray.instance.show(
      TraySpec(
        icon: TrayIcon.asset(
          getTrayIcon(
            isStart: trayState.isStart && !trayState.suspended,
            tunEnable: trayState.tunEnable,
            safeMode: trayState.safeMode,
            monochrome: trayState.monochromeTrayIcon,
          ),
          isTemplate: _isTemplate(trayState.monochromeTrayIcon),
          size: isMacOS ? 18 : 16,
        ),
        toolTip: trayState.safeMode
            ? currentAppLocalizations.safeModeAppTitle(appName)
            : appName,
        menu: _buildMenu(trayState: trayState, read: read),
      ),
    );
    await updateTitle(showTrayTitle: trayState.showTrayTitle, traffic: traffic);
  }

  Future<void> notify({required String title, required String body}) async {
    if (_isShutDown) {
      return;
    }
    await Tray.instance.notify(title: title, body: body);
  }

  Future<void> updateTitle({
    required bool showTrayTitle,
    required Traffic traffic,
  }) async {
    if (_isShutDown || !isMacOS) {
      return;
    }
    await Tray.instance.setTitle(showTrayTitle ? traffic.trayTitle : '');
  }

  List<TrayMenuItem> _buildMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    final commonAction = read(commonActionProvider.notifier);
    final systemAction = read(systemActionProvider.notifier);
    final appLocalizations = currentAppLocalizations;
    String? shortcut(HotAction action) => _shortcut(trayState, action);
    final showItem = TrayMenuAction(
      label: appLocalizations.show,
      detail: shortcut(HotAction.view),
      onSelected: () {
        showMainWindow();
      },
    );
    final exitItem = TrayMenuAction(
      label: appLocalizations.exit,
      detail: shortcut(HotAction.exit),
      onSelected: () {
        _exit(trayState: trayState, read: read);
      },
    );

    final signedIn = read(profilesProvider).isNotEmpty;
    return [
      showItem,
      if (signedIn || trayState.isStart)
        TrayMenuAction(
          label: trayState.isStart ? '斷開' : '連線',
          detail: shortcut(HotAction.start),
          onSelected: commonAction.toggleRunning,
        ),
      const TrayMenuSeparator(),
      exitItem,
    ];
  }

  /// The first exit with the proxy still on asks whether to come back that
  /// way; the answer, either way, is asked for only once.
  Future<void> _exit({
    required TrayState trayState,
    required ProviderReader read,
  }) async {
    final systemAction = read(systemActionProvider.notifier);
    if (trayState.isStart && !await SkylinkPrefs.keepLastStateAsked()) {
      await SkylinkPrefs.markKeepLastStateAsked();
      await window?.show();
      final keep = await dialogs.showMessage(
        title: '下次打開時自動連線？',
        message: const TextSpan(
          text:
              '現在是已連線的狀態。開啟「保持最後狀態」後，退出時是什麼狀態，'
              '下次打開 ATCSkylink 就會回到什麼狀態。\n\n'
              '以後可以點右上角的頭像修改。',
        ),
        confirmText: '開啟',
        cancelText: '不用了',
      );
      if (keep == true) await SkylinkPrefs.setKeepLastState(true);
    }
    await systemAction.handleExit();
  }

  String? _shortcut(TrayState trayState, HotAction action) {
    final hotKey = trayState.hotKeys[action];
    final key = hotKey?.key;
    if (hotKey == null || key == null) {
      return null;
    }
    return ShortcutLabels(
      isMacOS: isMacOS,
      isWindows: isWindows,
    ).text(hotKey.modifiers, key);
  }
}

final appTray = system.isDesktop ? AppTray() : null;
