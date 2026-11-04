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
      throw const PanelLoginException('登录失败：服务器没有返回订阅信息');
    }
    final authData = data?['auth_data'];
    final url =
        (authData is String ? await _subscribeUrl(authData) : null) ??
        '$panelApiBase/api/v1/client/subscribe?token=$token';
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
      return '无法连接服务器，请检查网络';
    }
    final decoded = _decode(response.data);
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    if (response.statusCode == 500) {
      return '邮箱或密码错误';
    }
    return '登录失败（${response.statusCode ?? '未知错误'}）';
  }
}
