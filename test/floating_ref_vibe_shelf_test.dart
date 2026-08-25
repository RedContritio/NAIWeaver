import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/director_ref/widgets/director_ref_shelf.dart';
import 'package:naiweaver/features/generation/widgets/vibe_transfer_shelf.dart';
import 'package:naiweaver/features/vibe_transfer/providers/vibe_transfer_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('empty ref and vibe shelves only occupy their button width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeNotifier(preferences)),
          ChangeNotifierProvider(create: (_) => DirectorRefNotifier()),
          ChangeNotifierProvider(create: (_) => VibeTransferNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [DirectorRefShelf(), VibeTransferShelf()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(DirectorRefShelf)).width, lessThan(80));
    expect(tester.getSize(find.byType(VibeTransferShelf)).width, lessThan(80));
  });
}
