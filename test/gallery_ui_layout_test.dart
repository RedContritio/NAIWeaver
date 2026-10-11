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

  test('gallery grid clears the home indicator and the bulk action bar', () {
    // Not selecting: only the safe area (e.g. iPhone home indicator).
    expect(galleryGridBottomInset(safeAreaBottom: 34), 42);
    expect(galleryGridBottomInset(safeAreaBottom: 0), 8);
    // Selecting: the bar sits 34 + 16 above the edge and is 54 tall.
    expect(
      galleryGridBottomInset(safeAreaBottom: 34, actionBarExtent: 34 + 16 + 54),
      112,
    );
  });

  testWidgets('HeightReporter reports the laid-out height', (tester) async {
    final heights = <double>[];
    var height = 54.0;
    late StateSetter setHeight;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHeight = setState;
          return Align(
            child: HeightReporter(
              onHeight: heights.add,
              child: SizedBox(width: 100, height: height),
            ),
          );
        },
      ),
    );
    await tester.pump();
    expect(heights, [54]);

    setHeight(() => height = 72);
    await tester.pump();
    await tester.pump();
    expect(heights, [54, 72]);
  });
}
