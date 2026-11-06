import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lastAccountKey = 'panelLastAccount';

/// Signs in to the panel and imports the account's subscription as the
/// current profile; signing in again refreshes the profile already there.
Future<void> showPanelLogin(WidgetRef ref) async {
  final url = await dialogs.showCommonDialog<String>(
    child: const PanelLoginDialog(),
  );
  if (url == null) return;
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

class PanelLoginDialog extends StatefulWidget {
  const PanelLoginDialog({super.key});

  @override
  State<PanelLoginDialog> createState() => _PanelLoginDialogState();
}

class _PanelLoginDialogState extends State<PanelLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = PanelApi();
  bool _remember = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLastAccount());
  }

  Future<void> _loadLastAccount() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final last = preferences.getString(_lastAccountKey);
      if (last != null && mounted && _emailController.text.isEmpty) {
        _emailController.text = last;
      }
    } catch (e) {
      commonPrint.log('load last account: $e');
    }
  }

  Future<void> _saveLastAccount(String email) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_remember) {
        await preferences.setString(_lastAccountKey, email);
      } else {
        await preferences.remove(_lastAccountKey);
      }
    } catch (e) {
      commonPrint.log('save last account: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (_busy) return;
    if (_formKey.currentState?.validate() == false) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _api.login(email, password);
      await _saveLastAccount(email);
      if (mounted) {
        Navigator.of(context).pop<String>(url);
      }
    } on PanelLoginException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      commonPrint.log('panel login: $e');
      if (mounted) {
        setState(() => _error = '登录失败，请稍后再试');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final error = _error;
    return AlertDialog(
      title: isTestPanel ? '登录 $brandName（测试服）' : '登录 $brandName',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _busy ? null : () => unawaited(_handleLogin()),
          child: Text(_busy ? '登录中…' : '登录'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            TextFormField(
              controller: _emailController,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(hintText: '邮箱'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return '请输入邮箱';
                if (!text.contains('@')) return '邮箱格式不正确';
                return null;
              },
            ),
            SecretTextFormField(
              controller: _passwordController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => unawaited(_handleLogin()),
              decoration: const InputDecoration(hintText: '密码'),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入密码';
                if (value.length < 8) return '密码至少 8 位';
                return null;
              },
            ),
            Row(
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _remember = value ?? true),
                ),
                const Expanded(child: Text('记住账号')),
                TextButton(
                  onPressed: () =>
                      unawaited(dialogs.openUrl(panelRegisterUrl)),
                  child: const Text('注册账号'),
                ),
              ],
            ),
            if (error != null)
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
