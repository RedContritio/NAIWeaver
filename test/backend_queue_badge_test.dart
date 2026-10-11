import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/auth/backend_auth_notifier.dart';
import 'package:naiweaver/features/auth/widgets/backend_queue_badge.dart';
import 'package:provider/provider.dart';

import 'support/fake_gateway_adapter.dart';
import 'test_harness.dart';

void main() {
  Future<FakeGatewayAdapter> pumpBadge(
    WidgetTester tester, {
    required bool signedIn,
  }) async {
    final adapter = FakeGatewayAdapter(
      (options) => options.uri.path == '/api/me'
          ? jsonResponse(meJson())
          : jsonResponse({
              'queued': 0,
              'active': 1,
              'estimated_wait_seconds': null,
              'user_queued': false,
              'user_active': false,
            }),
    );
    final client = clientOver(adapter);
    final auth = BackendAuthNotifier(client: client, gateway: true);
    addTearDown(auth.dispose);
    if (signedIn) await tester.runAsync(auth.initialize);
    adapter.requests.clear();
    await pumpHarness(
      tester,
      BackendQueueBadge(client: client, interval: const Duration(seconds: 5)),
      providers: [
        ChangeNotifierProvider<BackendAuthNotifier>.value(value: auth),
      ],
    );
    return adapter;
  }

  testWidgets('a signed-out page does not poll the queue', (tester) async {
    final adapter = await pumpBadge(tester, signedIn: false);

    await tester.pump(const Duration(seconds: 12));

    expect(adapter.requests, isEmpty);
  });

  testWidgets('a signed-in page polls until it is closed', (tester) async {
    final adapter = await pumpBadge(tester, signedIn: true);
    await tester.pump(const Duration(milliseconds: 10));
    expect(adapter.count('GET', '/api/queue'), 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 10));
    expect(adapter.count('GET', '/api/queue'), 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
    expect(adapter.count('GET', '/api/queue'), 2);
  });
}
