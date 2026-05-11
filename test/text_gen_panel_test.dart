import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/text_gen/providers/text_gen_notifier.dart';
import 'package:naiweaver/features/text_gen/widgets/text_gen_panel.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake [TextGenService] that yields a scripted token stream, optionally with
/// a controllable delay so tests can interrupt mid-stream.
class FakeTextGenService implements TextGenService {
  final List<String> tokens;
  final Duration tokenDelay;
  int generateCalls = 0;

  FakeTextGenService(this.tokens, {this.tokenDelay = Duration.zero});

  @override
  String get providerId => 'fake';

  @override
  Stream<String> generateStream(TextGenRequest req) async* {
    generateCalls++;
    for (final tk in tokens) {
      if (tokenDelay > Duration.zero) await Future.delayed(tokenDelay);
      yield tk;
    }
  }

  @override
  Future<String> generate(TextGenRequest req) async => tokens.join();
}

Future<void> pumpPanel(
  WidgetTester tester, {
  required TextGenNotifier notifier,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final prefsService = PreferencesService(prefs, const FlutterSecureStorage());

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier(prefsService)),
        ChangeNotifierProvider<TextGenNotifier>.value(value: notifier),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TextGenPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders with input field and Generate button', (tester) async {
    final notifier = TextGenNotifier()
      ..updateService(FakeTextGenService(['hi']));
    await pumpPanel(tester, notifier: notifier);

    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('typing in the input updates the notifier', (tester) async {
    final notifier = TextGenNotifier()
      ..updateService(FakeTextGenService(['x']));
    await pumpPanel(tester, notifier: notifier);

    final inputField = find.byType(TextField).first;
    await tester.enterText(inputField, 'The old lighthouse keeper said,');
    await tester.pump();

    expect(notifier.input, 'The old lighthouse keeper said,');
  });

  testWidgets('Generate streams output and flips isGenerating', (tester) async {
    final notifier = TextGenNotifier()
      ..updateService(
          FakeTextGenService(['Hello', ' ', 'world'], tokenDelay: const Duration(milliseconds: 20)));
    await pumpPanel(tester, notifier: notifier);

    await tester.enterText(find.byType(TextField).first, 'Continue: ');
    await tester.pump();

    expect(notifier.isGenerating, isFalse);

    // Tap Generate but don't settle yet — we want to observe the in-flight state.
    await tester.tap(find.text('Generate'));
    await tester.pump(); // start generating
    expect(notifier.isGenerating, isTrue);

    await tester.pump(const Duration(milliseconds: 30)); // first token
    expect(notifier.output, 'Hello');

    await tester.pumpAndSettle(); // drain the rest
    expect(notifier.output, 'Hello world');
    expect(notifier.isGenerating, isFalse);
    expect(notifier.history, isNotEmpty);
    // The Generate button label is back.
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('Cancel stops the stream, partial output retained', (tester) async {
    final notifier = TextGenNotifier()
      ..updateService(FakeTextGenService(
          ['a', 'b', 'c', 'd', 'e'],
          tokenDelay: const Duration(milliseconds: 50)));
    await pumpPanel(tester, notifier: notifier);

    await tester.enterText(find.byType(TextField).first, 'go');
    await tester.pump();

    await tester.tap(find.text('Generate'));
    await tester.pump();
    expect(notifier.isGenerating, isTrue);

    await tester.pump(const Duration(milliseconds: 60)); // ~1 token in
    final partial = notifier.output;
    expect(partial, isNotEmpty);

    // A Cancel button is now showing.
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(notifier.isGenerating, isFalse);
    expect(notifier.output, partial); // unchanged after cancel

    // Let any leftover timers fire; output must not grow.
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.output, partial);
  });

  testWidgets('Generate with no service set surfaces an error', (tester) async {
    final notifier = TextGenNotifier(); // no service
    await pumpPanel(tester, notifier: notifier);

    await tester.enterText(find.byType(TextField).first, 'something');
    await tester.pump();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(notifier.lastError, isNotNull);
    expect(notifier.isGenerating, isFalse);
  });
}
