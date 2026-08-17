import 'package:flutter/foundation.dart';

const bool _gatewayEnabled = bool.fromEnvironment(
  'NAIWEAVER_BACKEND_GATEWAY',
  defaultValue: true,
);

const String _apiBase = String.fromEnvironment('NAIWEAVER_API_BASE');

bool get useBackendGateway => kIsWeb && _gatewayEnabled;

String backendUrl(String path) {
  final normalized = path.startsWith('/') ? path : '/$path';
  if (_apiBase.isEmpty) return normalized;
  return '${_apiBase.replaceAll(RegExp(r'/$'), '')}$normalized';
}

String novelAiProxyUrl(String service, String path) {
  final normalized = path.startsWith('/') ? path.substring(1) : path;
  return backendUrl('/api/nai/$service/$normalized');
}

const String serverManagedApiKey = 'server-managed';
