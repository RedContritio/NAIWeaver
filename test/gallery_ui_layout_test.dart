import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/gallery/ui/gallery_layout.dart';

void main() {
  testWidgets('gallery detail panel is capped and vertically scrollable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GalleryDetailPanelViewport(
              mobile: true,
              background: BoxDecoration(color: Colors.black),
              padding: EdgeInsets.zero,
              child: SizedBox(width: 400, height: 1000),
            ),
          ),
        ),
      ),
    );

    final panel = find.byType(GalleryDetailPanelViewport);
    expect(tester.getSize(panel).height, 186);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(GalleryDetailPanelViewport.scrollViewKey),
    );
    expect(scrollView.scrollDirection, Axis.vertical);
    expect(tester.takeException(), isNull);
  });

  test('gallery grid reserves bulk action space only in selection mode', () {
    expect(galleryGridBottomInset(false), 8);
    expect(galleryGridBottomInset(true), 80);
  });
}
