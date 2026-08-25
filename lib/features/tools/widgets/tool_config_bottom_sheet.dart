import 'package:flutter/material.dart';

import '../../../core/theme/theme_extensions.dart';

Future<void> showToolConfigBottomSheet({
  required BuildContext context,
  required WidgetBuilder contentBuilder,
  Listenable? listenable,
}) {
  final t = context.tRead;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.surfaceHigh,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (sheetContext, scrollController) {
        Widget content = SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.viewInsetsOf(sheetContext).bottom +
                MediaQuery.viewPaddingOf(sheetContext).bottom +
                24,
          ),
          child: contentBuilder(sheetContext),
        );
        if (listenable != null) {
          content = ListenableBuilder(
            listenable: listenable,
            builder: (_, _) => SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.viewInsetsOf(sheetContext).bottom +
                    MediaQuery.viewPaddingOf(sheetContext).bottom +
                    24,
              ),
              child: contentBuilder(sheetContext),
            ),
          );
        }
        return content;
      },
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
