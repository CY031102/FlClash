import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'boarding_pass_login.dart';

const _lastAccountKey = 'panelLastAccount';

const panelForgotPasswordUrl = '$panelApiBase/#/forgetPassword';

/// Opens the boarding pass sign-in over the app.
void showPanelLogin(WidgetRef ref) => openLoginGate();

/// Imports the account's subscription as the current profile; signing in
/// again refreshes the profile already there.
Future<void> importPanelSubscription(WidgetRef ref, String url) async {
  final profilesAction = ref.read(profilesActionProvider.notifier);
  final existing = ref
      .read(profilesProvider)
      .firstWhereOrNull((profile) => profile.url == url);
  if (existing != null) {
    ref.read(currentProfileIdProvider.notifier).value = existing.id;
    await profilesAction.updateProfile(existing, showLoading: true);
    return;
  }
  await profilesAction.addProfileFromLink(url, label: brandName);
  final added = ref
      .read(profilesProvider)
      .firstWhereOrNull((profile) => profile.url == url);
  if (added != null) {
    ref.read(currentProfileIdProvider.notifier).value = added.id;
  }
}

Future<String?> loadLastPanelAccount() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_lastAccountKey);
  } catch (e) {
    commonPrint.log('load last account: $e');
    return null;
  }
}

Future<void> saveLastPanelAccount(String email, {required bool remember}) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    if (remember) {
      await preferences.setString(_lastAccountKey, email);
    } else {
      await preferences.remove(_lastAccountKey);
    }
  } catch (e) {
    commonPrint.log('save last account: $e');
  }
}
