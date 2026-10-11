import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:naiweaver/core/services/backend_client.dart';

/// A stand-in for the network below Dio: every request is recorded and
/// answered by [handler], so the real client, interceptors and APIs run.
class FakeGatewayAdapter implements HttpClientAdapter {
  FakeGatewayAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.uri.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object body, {int status = 200}) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(jsonEncode(body)))),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ResponseBody bytesResponse(List<int> body, {int status = 200}) => ResponseBody(
  Stream.value(Uint8List.fromList(body)),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/octet-stream'],
  },
);

ResponseBody htmlResponse(String body, {int status = 502}) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(body))),
  status,
  headers: {
    Headers.contentTypeHeader: ['text/html'],
  },
);

Map<String, dynamic> gatewayError(
  String code, {
  String message = 'human readable',
  Map<String, dynamic> extra = const {},
}) => {
  'detail': {'code': code, 'message': message, ...extra},
};

DioException connectionFailure(RequestOptions options) => DioException(
  requestOptions: options,
  type: DioExceptionType.connectionError,
);

/// A [BackendClient] on top of [adapter] that retries without waiting.
BackendClient clientOver(FakeGatewayAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return BackendClient(
    dio: dio,
    retryDelays: const [Duration.zero, Duration.zero],
  );
}

/// `rules.image` as `GET /api/me` returns it (docs/GATEWAY_CONTRACT.md §2).
Map<String, dynamic> rulesJson({
  int batchLimit = 8,
  Map<String, int> toolCaps = const {
    'upscale': 10,
    'augment': 80,
    'encode_vibe': 2,
  },
}) => {
  'image': {
    'free_sizes': [
      [832, 1216],
      [1216, 832],
      [1024, 1024],
    ],
    'free_max_steps': 28,
    'max_steps': 50,
    'max_dimension': 2048,
    'allowed_samplers': ['k_euler_ancestral'],
    'batch_limit': batchLimit,
    'green_point_discount': 0,
    'free_allowance_exhausted': false,
    'pricing': {
      'area_coefficient': 2.951823174884865e-6,
      'step_area_coefficient': 5.753298233447344e-7,
      'smea_multiplier': 1.2,
      'smea_dyn_multiplier': 1.4,
      'min_points': 2,
      'director_reference_points': 5,
      'free_vibe_count': 4,
      'extra_vibe_points': 2,
    },
    'tool_caps': toolCaps,
  },
};

Map<String, dynamic> meJson({int id = 7, int batchLimit = 8}) => {
  'user': {
    'id': id,
    'username': 'tester',
    'is_admin': false,
    'permissions': ['image.generate.free'],
  },
  'rules': rulesJson(batchLimit: batchLimit),
};
