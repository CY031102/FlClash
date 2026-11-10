import 'package:shared_preferences/shared_preferences.dart';

import 'print.dart';

/// ATCSkylink's own switches, kept beside FlClash's settings rather than in
/// them so the generated config models stay as upstream has them.
abstract final class SkylinkPrefs {
  static const _keepLastState = 'keepLastState';
  static const _keepLastStateAsked = 'keepLastStateAsked';
  static const _lastRunning = 'lastRunning';
  static const _connectGuideDone = 'connectGuideDone';

  static Future<bool> keepLastState() => _bool(_keepLastState);
  static Future<void> setKeepLastState(bool value) =>
      _setBool(_keepLastState, value);

  static Future<bool> keepLastStateAsked() => _bool(_keepLastStateAsked);
  static Future<void> markKeepLastStateAsked() =>
      _setBool(_keepLastStateAsked, true);

  /// Whether the proxy was on when the app last exited.
  static Future<bool> lastRunning() => _bool(_lastRunning);
  static Future<void> setLastRunning(bool value) =>
      _setBool(_lastRunning, value);

  /// The halo asking for the first connection goes once one has succeeded.
  static Future<bool> connectGuideDone() => _bool(_connectGuideDone);
  static Future<void> markConnectGuideDone() =>
      _setBool(_connectGuideDone, true);

  static Future<bool> _bool(String key) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(key) ?? false;
    } catch (e) {
      commonPrint.log('read $key: $e');
      return false;
    }
  }

  static Future<void> _setBool(String key, bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(key, value);
    } catch (e) {
      commonPrint.log('write $key: $e');
    }
  }
}

/// Set from the command line when Windows starts the app at sign-in: the
/// app then stays in the tray and says so with a notification.
bool launchedAtStartup = false;

const startupArgument = '--autostart';
