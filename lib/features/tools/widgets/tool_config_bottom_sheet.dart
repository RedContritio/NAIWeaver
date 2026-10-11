import 'package:flutter/material.dart';

import '../../../core/theme/theme_extensions.dart';

/// Shows a tool's settings in a draggable bottom sheet.
///
/// [contentBuilder] runs with the sheet's own context, so content that
/// watches a notifier there rebuilds while the sheet is open.
Future<void> showToolConfigBottomSheet({
  required BuildContext context,
  required WidgetBuilder contentBuilder,
}) {
  final t = context.tRead;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.surfaceHigh,
    // Lift the whole sheet above the keyboard so a focused field stays
    // visible instead of only padding the scrollable content.
    builder: (sheetContext) => AnimatedPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Builder(builder: contentBuilder),
        ),
      ),
    ),
  );
}

class ToolSettingsDock extends StatelessWidget {
  const ToolSettingsDock({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surfaceHigh,
      child: Container(
        key: const ValueKey<String>('tool-settings-dock'),
        height: 44 + MediaQuery.viewPaddingOf(context).bottom,
        padding: EdgeInsets.only(
          right: 10,
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.borderSubtle)),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(Icons.tune, size: 19, color: t.accentEdit),
        ),
      ),
    );
  }
}
