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
