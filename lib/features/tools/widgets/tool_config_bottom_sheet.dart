import 'package:flutter/material.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/ui/app_sheet.dart';

/// Shows a tool's settings in a draggable bottom sheet.
///
/// [contentBuilder] runs with the sheet's own context, so content that
/// watches a notifier there rebuilds while the sheet is open.
Future<void> showToolConfigBottomSheet({
  required BuildContext context,
  required WidgetBuilder contentBuilder,
}) {
  return showAppSheet<void>(
    context: context,
    builder: contentBuilder,
    draggable: true,
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
