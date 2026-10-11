import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/backend_auth_api.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/auth/backend_auth_notifier.dart';
import 'package:naiweaver/features/history/server_history_screen.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gateway_adapter.dart';

/// An in-memory gateway with the real history semantics
/// (docs/GATEWAY_CONTRACT.md §7): `total` and the offset count batches, every
/// row carries a `batch_id`, and a single image has `batch_size` 1.
class _Gateway {
  _Gateway(this.batches);

  /// Newest first; each batch is a list of rows.
  final List<List<Map<String, dynamic>>> batches;
  bool failHistory = false;
  bool failUsers = false;
  String? failDeleteWith;
  final List<String> deleteCalls = [];
  final List<int> historyOffsets = [];

  ResponseBody handle(RequestOptions options) {
    final path = options.uri.path;
    if (options.method == 'GET' && path == '/api/history') {
      if (failHistory) {
        return jsonResponse(gatewayError('internal_error'), status: 500);
      }
      final offset = int.parse(options.uri.queryParameters['offset']!);
      final limit = int.parse(options.uri.queryParameters['limit']!);
      historyOffsets.add(offset);
      final page = batches.skip(offset).take(limit);
      return jsonResponse({
        'items': [for (final batch in page) ...batch],
        'total': batches.length,
        'limit': limit,
        'offset': offset,
      });
    }
    if (options.method == 'GET' && path == '/api/admin/users') {
      if (failUsers) {
        return jsonResponse(gatewayError('internal_error'), status: 500);
      }
      return jsonResponse({
        'items': [
          {'id': 1, 'username': 'admin', 'is_admin': true},
          {'id': 7, 'username': 'owner', 'is_admin': false},
        ],
      });
    }
    if (options.method == 'DELETE') {
      final failure = failDeleteWith;
      if (failure != null) {
        return jsonResponse(gatewayError(failure), status: 409);
      }
      deleteCalls.add(path);
      final id = path.split('/').last;
      if (path.startsWith('/api/history/batches/')) {
        batches.removeWhere((batch) => batch.first['batch_id'] == id);
      } else {
        for (final batch in batches) {
          batch.removeWhere((row) => row['id'] == id);
        }
        batches.removeWhere((batch) => batch.isEmpty);
      }
      return jsonResponse({'ok': true});
    }
    return jsonResponse(gatewayError('not_found'), status: 404);
  }
}

Map<String, dynamic> _row(
  String id, {
  String? batchId,
  int index = 0,
  int size = 1,
  String status = 'succeeded',
  String? errorCode,
}) => {
  'id': id,
  'user_id': 7,
  'username': 'owner',
  'batch_id': batchId ?? 'batch-of-$id',
  'batch_index': index,
  'batch_size': size,
  'status': status,
  'error_code': errorCode,
  'mode': 'free',
  'points_charged': 0,
  'prompt': 'a prompt',
  'negative_prompt': '',
  'width': 832,
  'height': 1216,
  'steps': 28,
  'scale': 5,
  'sampler': 'k_euler',
  'seed': 1,
  'request_json': '{}',
  'has_image': status == 'succeeded',
  'created_at': '2026-08-25T12:00:00Z',
  'completed_at': null,
};

/// [count] single-image batches `s00`, `s01`, ... newest first.
List<List<Map<String, dynamic>>> _singles(int count) => [
  for (var i = 0; i < count; i += 1) [_row('s${i.toString().padLeft(2, '0')}')],
];

class _Auth extends BackendAuthNotifier {
  _Auth({this.admin = false});

  final bool admin;

  @override
  AuthUser? get user => AuthUser(
    id: admin ? 1 : 7,
    username: admin ? 'admin' : 'owner',
    isAdmin: admin,
    permissions: const [],
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Gateway gateway, {
  bool admin = false,
}) async {
  // Tall enough that all 20 cards of a page are built.
  tester.view.physicalSize = const Size(1000, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
  final adapter = FakeGatewayAdapter(gateway.handle);
  final api = BackendHistoryApi(client: clientOver(adapter));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(preferences),
        ),
        ChangeNotifierProvider<BackendAuthNotifier>(
          create: (_) => _Auth(admin: admin),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ServerHistoryScreen(api: api),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _card(String key) => find.byKey(ValueKey('history-entry-$key'));

Future<void> _openMenu(WidgetTester tester, String cardKey) async {
  await tester.tap(
    find.descendant(
      of: _card(cardKey),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _deleteViaMenu(WidgetTester tester, String cardKey) async {
  await _openMenu(tester, cardKey);
  await tester.tap(find.text('Delete').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
  await tester.pumpAndSettle();
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('single images and batches group by batch_size', (tester) async {
    final gateway = _Gateway([
      [
        _row('b0', batchId: 'batch-a', index: 0, size: 3),
        _row('b1', batchId: 'batch-a', index: 1, size: 3),
        _row('b2', batchId: 'batch-a', index: 2, size: 3),
      ],
      [_row('solo')],
    ]);
    await _pump(tester, gateway);

    expect(_card('batch:batch-a'), findsOneWidget);
    expect(_card('item:solo'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-badge')), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a delete re-reads the current page without a skip or repeat', (
    tester,
  ) async {
    final gateway = _Gateway(_singles(45));
    await _pump(tester, gateway);
    expect(find.textContaining('1-20 / 45'), findsOneWidget);

    await _deleteViaMenu(tester, 'item:s00');

    // s20 slid up from page 2; the next page must start at s21.
    expect(gateway.historyOffsets.last, 0);
    expect(_card('item:s00'), findsNothing);
    expect(_card('item:s01'), findsOneWidget);
    expect(_card('item:s20'), findsOneWidget);
    expect(find.textContaining('1-20 / 44'), findsOneWidget);
    await _tapTooltip(tester, 'Next page');
    expect(_card('item:s20'), findsNothing);
    expect(_card('item:s21'), findsOneWidget);
    expect(_card('item:s40'), findsOneWidget);
    expect(find.textContaining('21-40 / 44'), findsOneWidget);
  });

  testWidgets('deleting the only entry of the last page steps back a page', (
    tester,
  ) async {
    final gateway = _Gateway(_singles(21));
    await _pump(tester, gateway);
    await _tapTooltip(tester, 'Next page');
    expect(_card('item:s20'), findsOneWidget);

    await _deleteViaMenu(tester, 'item:s20');

    expect(find.textContaining('1-20 / 20'), findsOneWidget);
    expect(_card('item:s19'), findsOneWidget);
  });

  testWidgets('emptying page 0 loads the next batches instead of an empty '
      'state', (tester) async {
    final gateway = _Gateway(_singles(22));
    await _pump(tester, gateway);
    // Another session removed everything on the page but the first entry.
    gateway.batches.removeRange(1, 20);

    await _deleteViaMenu(tester, 'item:s00');

    expect(find.text('No server history yet'), findsNothing);
    expect(_card('item:s20'), findsOneWidget);
    expect(_card('item:s21'), findsOneWidget);
    expect(find.textContaining('1-2 / 2'), findsOneWidget);
  });

  testWidgets('a queued or running entry cannot be deleted', (tester) async {
    final gateway = _Gateway([
      [_row('active', status: 'running')],
    ]);
    await _pump(tester, gateway);

    await _openMenu(tester, 'item:active');
    await tester.tap(
      find.text('Still queued or running; it can be deleted once it finishes.'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.deleteCalls, isEmpty);
  });

  testWidgets('a failed delete names its cause instead of an export error', (
    tester,
  ) async {
    final gateway = _Gateway(_singles(1))..failDeleteWith = 'task_active';
    await _pump(tester, gateway);

    await _deleteViaMenu(tester, 'item:s00');

    expect(
      find.text('Delete failed: This item is still queued or running.'),
      findsOneWidget,
    );
    expect(find.textContaining('Export failed'), findsNothing);
    expect(_card('item:s00'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the list and offers a retry', (
    tester,
  ) async {
    final gateway = _Gateway(_singles(3));
    await _pump(tester, gateway);

    gateway.failHistory = true;
    await _tapTooltip(tester, 'Refresh');

    expect(_card('item:s00'), findsOneWidget);
    expect(find.textContaining('Could not load history'), findsOneWidget);

    gateway.failHistory = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load history'), findsNothing);
    expect(_card('item:s00'), findsOneWidget);
  });

  testWidgets('a failed page turn leaves the page number alone', (
    tester,
  ) async {
    final gateway = _Gateway(_singles(25));
    await _pump(tester, gateway);

    gateway.failHistory = true;
    await _tapTooltip(tester, 'Next page');

    expect(find.textContaining('1 / 2'), findsOneWidget);
    expect(_card('item:s00'), findsOneWidget);
    expect(find.textContaining('Could not load history'), findsOneWidget);

    gateway.failHistory = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 / 2'), findsOneWidget);
    expect(_card('item:s20'), findsOneWidget);
  });

  testWidgets('an admin still gets the history when the user list fails', (
    tester,
  ) async {
    final gateway = _Gateway(_singles(2))..failUsers = true;
    await _pump(tester, gateway, admin: true);

    expect(_card('item:s00'), findsOneWidget);
    expect(find.textContaining('Could not load history'), findsNothing);
    expect(
      find.text(
        'The user list could not be loaded, so the user filter is unavailable.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an interrupted item says nothing was charged', (tester) async {
    final gateway = _Gateway([
      [_row('cut', status: 'failed', errorCode: 'interrupted')],
    ]);
    await _pump(tester, gateway);

    expect(find.textContaining('You were not charged'), findsOneWidget);
    expect(find.textContaining('retry'), findsOneWidget);
  });
}
