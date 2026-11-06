import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/brand.dart';

class PanelLoginException implements Exception {
  const PanelLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PanelApi {
  PanelApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: panelApiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;

  /// Whether the panel answers at all, for the sign-in screen's status light.
  Future<bool> ping() async {
    try {
      final res = await _dio.get<dynamic>('/api/v1/guest/comm/config');
      return (res.statusCode ?? 0) < 400;
    } on DioException catch (e) {
      return (e.response?.statusCode ?? 600) < 500;
    }
  }

  /// Signs in and returns the subscription link to import.
  Future<String> login(String email, String password) async {
    final Map<String, dynamic>? data;
    try {
      final res = await _dio.post<dynamic>(
        '/api/v1/passport/auth/login',
        data: {'email': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      data = _dataOf(res.data);
    } on DioException catch (e) {
      throw PanelLoginException(_messageOf(e));
    }
    final token = data?['token'];
    if (token is! String || token.isEmpty) {
      throw const PanelLoginException('登入失敗：伺服器沒有回傳訂閱資訊');
    }
    final authData = data?['auth_data'];
    final url =
        (authData is String ? await _subscribeUrl(authData) : null) ??
        '$panelSubscribeBase/api/v1/client/subscribe?token=$token';
    return withSubscribeFlag(url);
  }

  /// The panel's own link is preferred: its subscribe host can differ from
  /// the API host.
  Future<String?> _subscribeUrl(String authData) async {
    try {
      final res = await _dio.get<dynamic>(
        '/api/v1/user/getSubscribe',
        options: Options(headers: {'Authorization': authData}),
      );
      final url = _dataOf(res.data)?['subscribe_url'];
      return url is String && url.startsWith('http') ? url : null;
    } on DioException {
      return null;
    }
  }

  static String withSubscribeFlag(String url) {
    final uri = Uri.parse(url);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'flag': panelSubscribeFlag,
          },
        )
        .toString();
  }

  static Map<String, dynamic>? _dataOf(Object? body) {
    final decoded = _decode(body);
    if (decoded is! Map) return null;
    final data = decoded['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Object? _decode(Object? body) {
    if (body is! String) return body;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String _messageOf(DioException e) {
    final response = e.response;
    if (response == null) {
      return '無法連線到伺服器，請檢查網路';
    }
    final decoded = _decode(response.data);
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) {
        return _traditional(message);
      }
    }
    if (response.statusCode == 500) {
      return '電子郵件或密碼錯誤';
    }
    return '登入失敗（${response.statusCode ?? '未知錯誤'}）';
  }

  /// V2Board answers in Simplified Chinese; the common sign-in replies are
  /// shown in Traditional, anything else as the panel wrote it.
  static String _traditional(String message) {
    if (message.contains('次数')) return '密碼錯誤次數過多，請稍後再試';
    if (message.contains('密码') || message.contains('邮箱')) {
      return '電子郵件或密碼錯誤';
    }
    if (message.contains('停止使用') || message.contains('封禁')) {
      return '此帳號已被停用';
    }
    return message;
  }
}
