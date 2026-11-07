import 'dart:async';
import 'dart:io';

import 'network_simulation.dart';

/// Puts every `dart:io` [HttpClient] (and so `package:http`, Dio and raw
/// `HttpClient` code) under [NetworkSimulation]. A client the app builds
/// from its own [HttpOverrides] is still wrapped: this one chains to the
/// override that was installed before it.
void installHttpOverrides() {
  if (HttpOverrides.current is _SimulatedOverrides) return;
  HttpOverrides.global = _SimulatedOverrides(HttpOverrides.current);
}

bool get httpOverridesActive => HttpOverrides.current is _SimulatedOverrides;

class _SimulatedOverrides extends HttpOverrides {
  _SimulatedOverrides(this._previous);

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _SimulatedClient(
    _previous?.createHttpClient(context) ?? super.createHttpClient(context),
  );

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      _previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}

class _SimulatedClient implements HttpClient {
  _SimulatedClient(this._inner);

  final HttpClient _inner;

  /// Waits the simulated latency, or fails as a phone with no network does.
  Future<T> _through<T>(Uri url, Future<T> Function() send) async {
    if (NetworkSimulation.offline) {
      throw const SocketException(
        '[FlutterPilot] Network simulated offline',
        osError: OSError('Network is unreachable', 101),
      );
    }
    final latency = NetworkSimulation.latency;
    if (latency != null) await Future<void>.delayed(latency);
    if (NetworkSimulation.shouldFail()) {
      final code = NetworkSimulation.statusCode;
      if (code != null && code >= 400) {
        throw HttpException(
          '[FlutterPilot] Simulated HTTP error $code',
          uri: url,
        );
      }
      throw const SocketException(
        '[FlutterPilot] Simulated network chaos error',
        osError: OSError('Connection reset by peer', 104),
      );
    }
    return send();
  }

  Uri _url(String host, int port, String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _through(url, () => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _through(
    _url(host, port, path),
    () => _inner.open(method, host, port, path),
  );

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);

  // Settings and the rest go straight to the real client.
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials c) =>
      _inner.addCredentials(url, realm, c);
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials c,
  ) => _inner.addProxyCredentials(host, port, realm, c);
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? cb,
  ) => _inner.badCertificateCallback = cb;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set keyLog(Function(String line)? cb) => _inner.keyLog = cb;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}
