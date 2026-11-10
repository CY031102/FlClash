import 'dart:io';

/// Serves the proxy auto-config Windows is pointed at instead of a fixed
/// proxy. The script sends everything to [_port], but it lives in this
/// process: when the app is killed Windows cannot fetch it and connects
/// directly, rather than through a proxy nobody answers.
class PacServer {
  PacServer._();

  static final instance = PacServer._();

  static const path = '/atcskylink.pac';

  HttpServer? _server;
  int _port = 0;
  List<String> _bypass = const [];

  Future<String> serve(int port, List<String> bypass) async {
    _port = port;
    _bypass = bypass;
    final server = _server ??= await _bind();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return 'http://127.0.0.1:${server.port}$path?v=$stamp';
  }

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final response = request.response
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-ns-proxy-autoconfig',
        )
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(script(_port, _bypass));
      response.close();
    });
    return server;
  }

  /// "; DIRECT" lets a browser holding the script fall back once the proxy
  /// itself is gone.
  static String script(int port, List<String> bypass) {
    final rules = StringBuffer();
    for (final pattern in bypass) {
      if (pattern.isEmpty || pattern == '<local>') continue;
      final escaped = pattern.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      rules.writeln('  if (shExpMatch(host, "$escaped")) return "DIRECT";');
    }
    return '''
function FindProxyForURL(url, host) {
  if (isPlainHostName(host)) return "DIRECT";
  if (dnsDomainIs(host, ".local") || dnsDomainIs(host, ".lan") ||
      dnsDomainIs(host, ".internal") || dnsDomainIs(host, ".home.arpa")) {
    return "DIRECT";
  }
$rules  return "PROXY 127.0.0.1:$port; DIRECT";
}
''';
  }
}
