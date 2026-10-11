import 'package:flutter/foundation.dart';

import 'backend_base_href_stub.dart'
    if (dart.library.js_interop) 'backend_base_href_web.dart';

const bool _gatewayEnabled = bool.fromEnvironment(
  'NAIWEAVER_BACKEND_GATEWAY',
  defaultValue: true,
);

const String _apiBase = String.fromEnvironment('NAIWEAVER_API_BASE');

bool get useBackendGateway => kIsWeb && _gatewayEnabled;

/// Joins [path] onto the gateway origin ([apiBase]) or, when the app is
/// served from a sub-path, onto its `<base href>` path ([baseHref]).
String joinBackendUrl(
  String path, {
  String apiBase = '',
  String baseHref = '',
}) {
  final normalized = path.startsWith('/') ? path : '/$path';
  final prefix = apiBase.isNotEmpty ? apiBase : baseHref;
  return '${prefix.replaceAll(RegExp(r'/+$'), '')}$normalized';
}

String backendUrl(String path) => joinBackendUrl(
  path,
  apiBase: _apiBase,
  baseHref: _apiBase.isEmpty ? platformBaseHrefPath() : '',
);

/// The gateway path that proxies [path] to a NovelAI [service].
String novelAiProxyPath(String service, String path) {
  final normalized = path.startsWith('/') ? path.substring(1) : path;
  return '/api/nai/$service/$normalized';
}

String novelAiProxyUrl(String service, String path) =>
    backendUrl(novelAiProxyPath(service, path));

const String serverManagedApiKey = 'server-managed';
