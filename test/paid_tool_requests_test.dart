import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_exception.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';

import 'support/fake_gateway_adapter.dart';

// PNG signature plus padding: enough for the client's image sanity check.
final _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 1];

List<int> _zipOf(List<int> image) {
  final archive = Archive()
    ..addFile(ArchiveFile('image_0.png', image.length, image));
  return ZipEncoder().encode(archive);
}

ResponseBody _toolHandler(RequestOptions options) {
  switch (options.uri.path) {
    case '/api/me':
      return jsonResponse(meJson());
    case '/api/nai/image/ai/upscale':
    case '/api/nai/image/ai/augment-image':
      return bytesResponse(_zipOf(_png));
    case '/api/nai/image/ai/encode-vibe':
      return bytesResponse([1, 2, 3]);
  }
  return jsonResponse(gatewayError(BackendErrorCode.notFound), status: 404);
}

void main() {
  Future<void> callEachTool(NovelAIService service) async {
    await service.upscaleImage(imageBase64: 'x', width: 64, height: 64);
    await service.augmentImage(
      imageBase64: 'x',
      width: 64,
      height: 64,
      reqType: 'bg-removal',
    );
    await service.encodeVibeImage(imageBase64: 'x');
  }

  test('each paid tool is sent once with its key and price', () async {
    final adapter = FakeGatewayAdapter(_toolHandler);
    final service = NovelAIService(
      '',
      client: clientOver(adapter),
      gateway: true,
    );

    await callEachTool(service);

    final posts = adapter.requests.where((r) => r.method == 'POST').toList();
    expect(posts, hasLength(3));
    final expectedPoints = {
      '/api/nai/image/ai/upscale': '10',
      '/api/nai/image/ai/augment-image': '80',
      '/api/nai/image/ai/encode-vibe': '2',
    };
    for (final post in posts) {
      expect(
        post.headers['X-NAIWeaver-Expected-Points'],
        expectedPoints[post.uri.path],
      );
      expect(post.headers['Idempotency-Key'], hasLength(greaterThan(7)));
    }
    final keys = posts.map((r) => r.headers['Idempotency-Key']).toSet();
    expect(keys, hasLength(3), reason: 'every user action gets a new key');
  });

  test('a rejected paid tool is not sent a second time', () async {
    final adapter = FakeGatewayAdapter((options) {
      if (options.uri.path == '/api/me') return jsonResponse(meJson());
      return jsonResponse(
        gatewayError(BackendErrorCode.upstreamError),
        status: 502,
      );
    });
    final service = NovelAIService(
      '',
      client: clientOver(adapter),
      gateway: true,
    );

    await expectLater(
      service.upscaleImage(imageBase64: 'x', width: 64, height: 64),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          'code',
          BackendErrorCode.upstreamError,
        ),
      ),
    );
    expect(adapter.count('POST', '/api/nai/image/ai/upscale'), 1);
  });

  test('a changed price surfaces as a typed error with the quote', () async {
    final adapter = FakeGatewayAdapter((options) {
      if (options.uri.path == '/api/me') return jsonResponse(meJson());
      return jsonResponse(
        gatewayError(
          BackendErrorCode.quoteChanged,
          extra: {
            'quote': {
              'mode': 'paid',
              'points': 12,
              'reasons': ['paid_tool'],
            },
          },
        ),
        status: 409,
      );
    });
    final service = NovelAIService(
      '',
      client: clientOver(adapter),
      gateway: true,
    );

    await expectLater(
      service.encodeVibeImage(imageBase64: 'x'),
      throwsA(
        isA<QuoteChangedException>().having((e) => e.points, 'points', 12),
      ),
    );
    expect(adapter.count('POST', '/api/nai/image/ai/encode-vibe'), 1);
  });

  test('a points_insufficient tool error keeps its code', () async {
    final adapter = FakeGatewayAdapter((options) {
      if (options.uri.path == '/api/me') return jsonResponse(meJson());
      return jsonResponse(
        gatewayError(
          BackendErrorCode.pointsInsufficient,
          extra: {'point_kind': 'red', 'required': 80, 'remaining': 3},
        ),
        status: 409,
      );
    });
    final service = NovelAIService(
      '',
      client: clientOver(adapter),
      gateway: true,
    );

    await expectLater(
      service.augmentImage(
        imageBase64: 'x',
        width: 64,
        height: 64,
        reqType: 'bg-removal',
      ),
      throwsA(
        isA<BackendException>()
            .having((e) => e.code, 'code', BackendErrorCode.pointsInsufficient)
            .having((e) => e.pointKind, 'point kind', 'red'),
      ),
    );
  });
}
