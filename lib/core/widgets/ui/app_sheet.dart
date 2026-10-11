import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';
import '../../theme/vision_metrics.dart';
import '../section_title.dart';

const _sheetAnimation = Duration(milliseconds: 150);

/// Shows the app's standard bottom sheet.
///
/// Background, top radius and drag handle come from the theme's
/// `bottomSheetTheme`. The content is scrollable, padded once for the bottom
/// safe area, and lifted above the keyboard. [builder] runs with the sheet's
/// own context, so content that watches a notifier rebuilds while it is open.
///
/// Set [draggable] to let the user resize the sheet between [minSize] and
/// [maxSize] (fractions of the screen height).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool draggable = false,
  double initialSize = 0.6,
  double minSize = 0.3,
  double maxSize = 0.9,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    builder: (sheetContext) => AnimatedPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      duration: _sheetAnimation,
      curve: Curves.easeOut,
      child: draggable
          ? DraggableScrollableSheet(
              initialChildSize: initialSize,
              minChildSize: minSize,
              maxChildSize: maxSize,
              expand: false,
              builder: (ctx, controller) => _SheetScroll(
                controller: controller,
                child: Builder(builder: builder),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * maxSize,
              ),
              child: _SheetScroll(child: Builder(builder: builder)),
            ),
    ),
  );
}

class _SheetScroll extends StatelessWidget {
  const _SheetScroll({required this.child, this.controller});

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      // MediaQuery.padding already excludes the area covered by the keyboard,
      // so the safe area is applied exactly once.
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + VisionMetrics.space24,
      ),
      child: child,
    );
  }
}

/// Standard content for a picker sheet: an optional title above [child].
/// Use inside [showAppSheet].
class AppPickerSheet extends StatelessWidget {
  const AppPickerSheet({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) SectionTitle(title!.toUpperCase(), t: t),
          child,
        ],
      ),
    );
  }
}
