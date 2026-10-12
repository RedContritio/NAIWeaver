import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_exception.dart';
import 'package:naiweaver/core/gateway/backend_gateway.dart';
import 'package:naiweaver/core/services/backend_client.dart';

import 'support/fake_gateway_adapter.dart';

void main() {
  group('error parsing', () {
    test('a JSON error keeps its code, message and extra fields', () async {
      final adapter = FakeGatewayAdapter(
        (_) => jsonResponse(
          gatewayError(
            BackendErrorCode.pointsInsufficient,
            message: 'not enough',
            extra: {'point_kind': 'red', 'required': 5, 'remaining': 1},
          ),
          status: 409,
        ),
      );

      await expectLater(
        clientOver(adapter).post<dynamic>('/api/x', data: {}),
        throwsA(
          isA<BackendException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.code, 'code', 'points_insufficient')
              .having((e) => e.message, 'message', 'not enough')
              .having((e) => e.pointKind, 'point_kind', 'red')
              .having((e) => e.details['required'], 'required', 5),
        ),
      );
    });

    test('an error body requested as bytes is decoded too', () async {
      final adapter = FakeGatewayAdapter(
        (_) => jsonResponse(
          gatewayError(BackendErrorCode.pointsInsufficient),
          status: 409,
        ),
      );

      await expectLater(
        clientOver(adapter).post<List<int>>(
          '/api/nai/image/ai/upscale',
          options: Options(responseType: ResponseType.bytes),
        ),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            BackendErrorCode.pointsInsufficient,
          ),
        ),
      );
    });

    test('a quote_changed error carries the server quote', () async {
      final adapter = FakeGatewayAdapter(
        (_) => jsonResponse(
          gatewayError(
            BackendErrorCode.quoteChanged,
            extra: {
              'quote': {'mode': 'paid', 'points': 12},
            },
          ),
          status: 409,
        ),
      );

      await expectLater(
        clientOver(adapter).post<dynamic>('/api/x', data: {}),
        throwsA(
          isA<QuoteChangedException>()
              .having((e) => e.mode, 'mode', 'paid')
              .having((e) => e.points, 'points', 12),
        ),
      );
    });

    test('a non-JSON error body still yields a typed exception', () async {
      final adapter = FakeGatewayAdapter(
        (_) => htmlResponse('<html>Bad Gateway</html>'),
      );

      await expectLater(
        clientOver(adapter).get<dynamic>('/api/x'),
        throwsA(
          isA<BackendException>()
              .having((e) => e.statusCode, 'status', 502)
              .having((e) => e.code, 'code', BackendErrorCode.http)
              .having((e) => e.message, 'message', isEmpty),
        ),
      );
    });

    test('an unreachable server is a network error without status', () async {
      final adapter = FakeGatewayAdapter((o) => throw connectionFailure(o));

      await expectLater(
        clientOver(adapter).post<dynamic>('/api/x', data: {}),
        throwsA(
          isA<BackendException>()
              .having((e) => e.statusCode, 'status', isNull)
              .having((e) => e.isNetworkError, 'network', isTrue),
        ),
      );
    });
  });

  group('retries', () {
    test('a GET is retried after a transient failure', () async {
      var calls = 0;
      final adapter = FakeGatewayAdapter((options) {
        calls++;
        if (calls < 3) return jsonResponse(gatewayError('x'), status: 503);
        return jsonResponse({'ok': true});
      });

      final response = await clientOver(adapter).get<dynamic>('/api/x');

      expect(response.data, {'ok': true});
      expect(adapter.requests, hasLength(3));
    });

    test('a GET gives up after its retries', () async {
      final adapter = FakeGatewayAdapter((o) => throw connectionFailure(o));

      await expectLater(
        clientOver(adapter).get<dynamic>('/api/x'),
        throwsA(isA<BackendException>()),
      );
      expect(adapter.requests, hasLength(3));
    });

    test('a POST is never sent twice', () async {
      for (final failure in <ResponseBody Function(RequestOptions)>[
        (_) => jsonResponse(gatewayError('x'), status: 503),
        (o) => throw connectionFailure(o),
      ]) {
        final adapter = FakeGatewayAdapter(failure);

        await expectLater(
          clientOver(adapter).post<dynamic>('/api/x', data: {}),
          throwsA(isA<BackendException>()),
        );
        expect(adapter.requests, hasLength(1));
      }
    });
  });

  group('session handling', () {
    test('a not_authenticated 401 is reported', () async {
      final adapter = FakeGatewayAdapter(
        (_) => jsonResponse(
          gatewayError(BackendErrorCode.notAuthenticated),
          status: 401,
        ),
      );
      var reports = 0;
      final client = clientOver(adapter)..onNotAuthenticated = () => reports++;

      await expectLater(
        client.get<dynamic>('/api/x'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.isNotAuthenticated,
            'not authenticated',
            isTrue,
          ),
        ),
      );
      expect(reports, 1);
    });

    test('an upstream failure is not a lost session', () async {
      final adapter = FakeGatewayAdapter(
        (_) => jsonResponse(
          gatewayError(BackendErrorCode.upstreamError),
          status: 502,
        ),
      );
      var reports = 0;
      final client = clientOver(adapter)..onNotAuthenticated = () => reports++;

      await expectLater(
        client.post<dynamic>('/api/x', data: {}),
        throwsA(isA<BackendException>()),
      );
      expect(reports, 0);
    });

    test('a caller that owns the 401 can opt out of the report', () async {
      final adapter = FakeGatewayAdapter(
        (_) => jsonResponse(
          gatewayError(BackendErrorCode.notAuthenticated),
          status: 401,
        ),
      );
      var reports = 0;
      final client = clientOver(adapter)..onNotAuthenticated = () => reports++;

      await expectLater(
        client.get<dynamic>(
          '/api/me',
          options: Options(extra: {backendSkipAuthCallbackKey: true}),
        ),
        throwsA(isA<BackendException>()),
      );
      expect(reports, 0);
    });
  });

  test('urls follow the base href of a sub-path deployment', () {
    expect(joinBackendUrl('/api/me'), '/api/me');
    expect(joinBackendUrl('/api/me', baseHref: '/weaver'), '/weaver/api/me');
    expect(
      joinBackendUrl('api/me', apiBase: 'https://gw.example/'),
      'https://gw.example/api/me',
    );
  });
}
