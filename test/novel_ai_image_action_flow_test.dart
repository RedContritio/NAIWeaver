import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_image_action_service.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/gallery/services/tool_result_saver.dart';
import 'package:naiweaver/features/gallery/ui/novel_ai_image_action_flow.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Upscale requests stay pending until the test completes them.
class _PendingNovelAiService extends NovelAIService {
  _PendingNovelAiService() : super('');

  final requests = <Completer<Uint8List>>[];

  @override
  Future<Uint8List> upscaleImage({
    required String imageBase64,
    required int width,
    required int height,
    int scale = 2,
  }) {
    final request = Completer<Uint8List>();
    requests.add(request);
    return request.future;
  }
}

class _Harness {
  _Harness({bool saveFails = false})
    : service = _PendingNovelAiService(),
      _saveFails = saveFails;

  final _PendingNovelAiService service;
  final bool _saveFails;
  final flow = NovelAiImageActionFlow();
  final results = <Uint8List>[];
  int sourceReads = 0;

  NovelAiImageActionService get actions => NovelAiImageActionService(
    service,
    gatewayMode: true,
    readImageSize: (_) async => (512, 512),
    saver: ToolResultSaver(
      web: false,
      writeToGallery: (bytes, name, {sourceBytes}) async {
        if (_saveFails) throw StateError('disk full');
      },
    ),
  );

  /// Mirrors the detail view: request, then save and report the save.
  void start(BuildContext context) {
    final actions = this.actions;
    flow.run(
      context,
      service: actions,
      action: NovelAiImageAction.upscale,
      permissionGranted: true,
      apiKey: '',
      readSource: () async {
        sourceReads++;
        return Uint8List.fromList([1, 2, 3]);
      },
      onResult: (source, result) async {
        results.add(result);
        final outcome = await actions.save(
          result,
          'NAI_UP_x.png',
          sourceBytes: source,
        );
        if (context.mounted) showToolResultSaveFeedback(context, outcome);
      },
    );
  }
}

/// A root page with a detail page pushed on top, like gallery -> detail.
Future<void> _pumpDetailPage(WidgetTester tester, _Harness harness) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(preferences),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('gallery')),
      ),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => harness.start(context),
            child: const Text('NAI UPSCALE'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a double tap sends one paid request', (tester) async {
    final harness = _Harness();
    await _pumpDetailPage(tester, harness);

    await tester.tap(find.text('NAI UPSCALE'));
    await tester.tap(find.text('NAI UPSCALE'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('NAI UPSCALE'), warnIfMissed: false);
    await tester.pump();

    expect(harness.sourceReads, 1);
    expect(harness.service.requests, hasLength(1));
    expect(find.text('UPSCALING VIA API...'), findsOneWidget);

    harness.service.requests.single.complete(Uint8List.fromList([9]));
    await tester.pumpAndSettle();

    expect(harness.results, hasLength(1));
    expect(find.text('UPSCALING VIA API...'), findsNothing);
    expect(find.text('NAI UPSCALE'), findsOneWidget, reason: 'detail stays');
  });

  testWidgets('back during the request neither closes the dialog nor the '
      'detail page', (tester) async {
    final harness = _Harness();
    await _pumpDetailPage(tester, harness);

    await tester.tap(find.text('NAI UPSCALE'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    // The spinner never settles while the request is pending.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('UPSCALING VIA API...'), findsOneWidget);

    harness.service.requests.single.complete(Uint8List.fromList([9]));
    await tester.pumpAndSettle();

    expect(find.text('UPSCALING VIA API...'), findsNothing);
    expect(find.text('NAI UPSCALE'), findsOneWidget);
    expect(find.text('gallery'), findsNothing);
  });

  testWidgets('a failed request closes only its dialog', (tester) async {
    final harness = _Harness();
    await _pumpDetailPage(tester, harness);

    await tester.tap(find.text('NAI UPSCALE'));
    await tester.pump();
    harness.service.requests.single.completeError(Exception('502'));
    await tester.pumpAndSettle();

    expect(harness.results, isEmpty);
    expect(find.text('UPSCALING VIA API...'), findsNothing);
    expect(find.text('NAI UPSCALE'), findsOneWidget);
    expect(find.text('API upscale failed'), findsOneWidget);

    // The guard is released: the next tap sends a new request.
    await tester.tap(find.text('NAI UPSCALE'));
    await tester.pump();
    expect(harness.service.requests, hasLength(2));
  });

  testWidgets('a failed save is reported as a save failure', (tester) async {
    final harness = _Harness(saveFails: true);
    await _pumpDetailPage(tester, harness);

    await tester.tap(find.text('NAI UPSCALE'));
    await tester.pump();
    harness.service.requests.single.complete(Uint8List.fromList([9]));
    await tester.pumpAndSettle();

    expect(find.text('NAI UPSCALE'), findsOneWidget);
    expect(find.textContaining('Result not saved'), findsOneWidget);
    expect(find.text('API upscale failed'), findsNothing);
  });
}
