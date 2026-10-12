@TestOn('browser')
library;

import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/browser_native_selectable_text.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area.dart';
import 'package:naiweaver/features/generation/widgets/browser_photo_swipe_viewer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_platform_view_test_support.dart';

void main() {
  testPlatformViewWidgets(
    'DOM-backed widgets never register a view factory per instance',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
      final controllers = [TextEditingController(), TextEditingController()];
      for (final controller in controllers) {
        addTearDown(controller.dispose);
      }
      const image = BrowserPhotoSwipeItem(
        id: 'a',
        url: 'https://example.invalid/a.png',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(preferences),
          child: MaterialApp(
            home: ListView(
              children: [
                for (final controller in controllers)
                  BrowserNativeTextArea(
                    controller: controller,
                    height: 80,
                    fallback: const SizedBox(),
                  ),
                for (final text in ['first', 'second'])
                  BrowserNativeSelectableText(text: text),
                for (var index = 0; index < 2; index++)
                  SizedBox(
                    height: 120,
                    child: BrowserPhotoSwipeViewer(
                      items: const [image],
                      selectedId: 'a',
                      onSelect: (_) {},
                      fallback: const SizedBox(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      final views = tester.widgetList<HtmlElementView>(
        find.byType(HtmlElementView),
      );
      expect(views, hasLength(6));
      expect(views.map((view) => view.viewType).toSet(), {
        ui_web.PlatformViewRegistry.defaultVisibleViewType,
      });
    },
  );
}
