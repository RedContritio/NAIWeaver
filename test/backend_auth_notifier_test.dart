import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_exception.dart';
import 'package:naiweaver/core/services/backend_client.dart';
import 'package:naiweaver/features/auth/backend_auth_notifier.dart';

import 'support/fake_gateway_adapter.dart';

class _FakeNavigation implements BackendAuthNavigation {
  final opened = <Uri>[];
  var reloads = 0;

  @override
  Uri get currentPage => Uri.parse('https://weaver.example/app/?tab=history');

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }

  @override
  void reload() => reloads++;
}

typedef _Handler = ResponseBody Function(RequestOptions options);

void main() {
  late _FakeNavigation navigation;
  late FakeGatewayAdapter adapter;
  late BackendClient client;
  late BackendAuthNotifier auth;
  late _Handler meHandler;
  late _Handler logoutHandler;
  late _Handler otherHandler;

  setUp(() {
    navigation = _FakeNavigation();
    meHandler = (_) => jsonResponse(meJson());
    logoutHandler = (_) => jsonResponse({'ok': true});
    otherHandler = (_) => jsonResponse({});
    adapter = FakeGatewayAdapter(
      (options) => switch (options.uri.path) {
        '/api/me' => meHandler(options),
        '/api/logout' => logoutHandler(options),
        _ => otherHandler(options),
      },
    );
    client = clientOver(adapter);
    auth = BackendAuthNotifier(
      client: client,
      navigation: navigation,
      gateway: true,
    );
    addTearDown(auth.dispose);
  });

  ResponseBody sessionGone(RequestOptions _) => jsonResponse(
    gatewayError(BackendErrorCode.notAuthenticated),
    status: 401,
  );

  test('signing in loads the user and the image rules', () async {
    await auth.initialize();

    expect(auth.user?.id, 7);
    expect(auth.rules?.batchLimit, 8);
    expect(auth.rules?.toolCaps.upscale, 10);
    expect(client.imageRules?.toolCaps.encodeVibe, 2);
  });

  test('a native build never talks to the gateway', () async {
    final native = BackendAuthNotifier(
      client: client,
      navigation: navigation,
      gateway: false,
    );
    addTearDown(native.dispose);

    await native.initialize();

    expect(adapter.requests, isEmpty);
    expect(native.isLoading, isFalse);
  });

  group('a failed refresh', () {
    setUp(() => auth.initialize());

    test('keeps the user when the identity provider is down', () async {
      meHandler = (_) => jsonResponse(
        gatewayError(BackendErrorCode.authUnavailable),
        status: 503,
      );

      await auth.refreshSession();

      expect(auth.user?.id, 7);
      expect(auth.sessionExpired, isFalse);
      expect(auth.refreshError?.code, BackendErrorCode.authUnavailable);
    });

    test('keeps the user when the network is down', () async {
      meHandler = (o) => throw connectionFailure(o);

      await auth.refreshSession();

      expect(auth.user?.id, 7);
      expect(auth.sessionExpired, isFalse);
      expect(auth.refreshError?.isNetworkError, isTrue);
    });

    test('flags an expired session without leaving the page', () async {
      meHandler = sessionGone;

      await auth.refreshSession();

      expect(auth.user?.id, 7);
      expect(auth.sessionExpired, isTrue);
      expect(navigation.opened, isEmpty);
    });
  });

  group('requests made while signed in', () {
    setUp(() => auth.initialize());

    test('a lost session raises the expired flow', () async {
      otherHandler = sessionGone;

      await expectLater(
        client.get<dynamic>('/api/history'),
        throwsA(isA<BackendException>()),
      );

      expect(auth.sessionExpired, isTrue);
    });

    test('an upstream failure does not', () async {
      otherHandler = (_) => jsonResponse(
        gatewayError(BackendErrorCode.upstreamError),
        status: 502,
      );

      await expectLater(
        client.post<dynamic>('/api/nai/image/ai/upscale', data: {}),
        throwsA(isA<BackendException>()),
      );

      expect(auth.sessionExpired, isFalse);
    });
  });

  test('signing in again returns to the current page', () async {
    await auth.login();

    final uri = navigation.opened.single;
    expect(uri.path, '/auth/login');
    expect(uri.queryParameters['return_to'], '/app/?tab=history');
  });

  group('signing out', () {
    setUp(() => auth.initialize());

    test('a failed request keeps the user and says so', () async {
      logoutHandler = (_) => jsonResponse(
        gatewayError(BackendErrorCode.serviceUnavailable),
        status: 503,
      );

      await auth.logout();

      expect(auth.user?.id, 7);
      expect(auth.logoutFailed, isTrue);
      expect(navigation.reloads, 0);
    });

    test('success clears the user and reloads the page', () async {
      await auth.logout();

      expect(auth.user, isNull);
      expect(client.imageRules, isNull);
      expect(navigation.reloads, 1);
    });
  });
}
