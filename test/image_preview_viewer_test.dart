import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/generation/widgets/image_viewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('photo_view pinch gesture increases the rendered image size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final imageBytes = File('assets/logo.png').readAsBytesSync();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(preferences),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: ImagePreviewViewer(
                generatedImage: imageBytes,
                isLoading: false,
                isDragging: false,
                pulseAnimation: const AlwaysStoppedAnimation(0),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.byType(PhotoView), findsOneWidget);
    final imageFinder = find.descendant(
      of: find.byType(PhotoView),
      matching: find.byType(Image),
    );
    final widthBefore = tester.widget<Image>(imageFinder).width!;

    final firstFinger = await tester.startGesture(
      const Offset(350, 300),
      pointer: 1,
    );
    final secondFinger = await tester.startGesture(
      const Offset(450, 300),
      pointer: 2,
    );
    await firstFinger.moveTo(const Offset(300, 300));
    await secondFinger.moveTo(const Offset(500, 300));
    await tester.pump();

    final widthAfter = tester.widget<Image>(imageFinder).width!;
    expect(widthAfter, greaterThan(widthBefore));
    expect(tester.takeException(), isNull);

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('changing image identity replaces the PhotoView image provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final firstBytes = File('assets/logo.png').readAsBytesSync();
    final secondBytes = Uint8List.fromList(firstBytes);

    Widget buildViewer(Uint8List bytes, String identity) {
      return ChangeNotifierProvider(
        create: (_) => ThemeNotifier(preferences),
        child: MaterialApp(
          home: Scaffold(
            body: ImagePreviewViewer(
              generatedImage: bytes,
              imageIdentity: identity,
              isLoading: false,
              isDragging: false,
              pulseAnimation: const AlwaysStoppedAnimation(0),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildViewer(firstBytes, 'first'));
    await tester.pump();
    final firstView = tester.widget<PhotoView>(find.byType(PhotoView));
    expect(firstView.key, const ValueKey<Object>('first'));

    await tester.pumpWidget(buildViewer(secondBytes, 'second'));
    await tester.pump();
    final secondView = tester.widget<PhotoView>(find.byType(PhotoView));
    expect(secondView.key, const ValueKey<Object>('second'));
    expect((secondView.imageProvider as MemoryImage).bytes, same(secondBytes));
  });
}
