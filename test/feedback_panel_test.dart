import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/backend_feedback_api.dart';
import 'package:naiweaver/core/services/client_diagnostics.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/tools/widgets/feedback_panel.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFeedbackApi implements FeedbackApi {
  String? description;
  Map<String, dynamic>? clientContext;
  List<Map<String, dynamic>>? diagnostics;

  @override
  Future<FeedbackSubmission> submit({
    required String description,
    required Map<String, dynamic> clientContext,
    required List<Map<String, dynamic>> diagnostics,
  }) async {
    this.description = description;
    this.clientContext = clientContext;
    this.diagnostics = diagnostics;
    return const FeedbackSubmission(id: 'fb_test_ticket', createdAt: 'now');
  }
}

void main() {
  testWidgets('feedback button submits the diagnostic snapshot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final api = _FakeFeedbackApi();
    final diagnostics = ClientDiagnostics()..record('keyboard_focus');

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
          home: Scaffold(
            body: FeedbackPanel(
              api: api,
              diagnostics: diagnostics,
              gatewayAvailable: true,
              clientContextCollector: () async => {
                'app_version': 'test',
                'web': true,
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(FeedbackPanel.descriptionKey),
      'Keyboard closed',
    );
    await tester.tap(find.byKey(FeedbackPanel.submitKey));
    await tester.pumpAndSettle();

    expect(api.description, 'Keyboard closed');
    expect(api.clientContext?['app_version'], 'test');
    expect(api.clientContext?['diagnostic_session_id'], isNotEmpty);
    expect(api.clientContext?['diagnostic_event_capacity'], 1200);
    expect(
      api.diagnostics?.map((item) => item['event']),
      containsAll(['keyboard_focus', 'feedback_panel_opened']),
    );
    expect(api.diagnostics?.first['sequence'], isA<int>());
    expect(find.byKey(FeedbackPanel.ticketKey), findsOneWidget);
    expect(find.byKey(FeedbackPanel.copyTicketKey), findsOneWidget);

    // Headless Chrome rejects clipboard writes because there is no granted
    // clipboard permission. The native selectable DOM itself is covered by
    // browser_native_selectable_text_test.dart.
    if (!kIsWeb) {
      await tester.tap(find.byKey(FeedbackPanel.copyTicketKey));
      await tester.pumpAndSettle();
      expect(find.text('Ticket ID copied'), findsOneWidget);
    }
  });
}
