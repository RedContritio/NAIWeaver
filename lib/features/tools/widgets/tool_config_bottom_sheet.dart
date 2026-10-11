import 'package:flutter/material.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/utils/responsive.dart';
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

/// The one way every tool workspace (Img2Img, Enhance, Director Tools) exposes
/// its settings.
///
/// - Touch-sized windows (compact and medium): the body fills the screen and a
///   [ToolSettingsDock] at the bottom opens the settings in a sheet. The dock
///   sits where the thumb is; a header button would compete with the
///   workspace's primary action for room.
/// - Expanded windows and up: the settings stay open in a side panel.
///
/// [settingsBuilder] runs once per placement with that placement's context
/// (the sheet's own context inside the sheet), so it can `watch` a notifier.
class ToolSettingsLayout extends StatelessWidget {
  const ToolSettingsLayout({
    super.key,
    required this.body,
    required this.settingsBuilder,
    required this.settingsTooltip,
    this.header,
    this.sidePanelWidth = 300,
    this.scrollSidePanel = true,
  });

  /// The workspace content (image area, toolbars).
  final Widget body;

  /// Builds the settings content.
  final WidgetBuilder settingsBuilder;

  /// Tooltip of the dock button that opens the settings sheet.
  final String settingsTooltip;

  /// Optional header shown above the body.
  final Widget? header;
  final double sidePanelWidth;

  /// Wrap the side panel in a scroll view; set to false when the content
  /// scrolls itself.
  final bool scrollSidePanel;

  @override
  Widget build(BuildContext context) {
    final touch = windowSizeClassOf(context).isTouchSized;
    return Column(
      children: [
        ?header,
        Expanded(
          child: touch
              ? body
              : Row(
                  children: [
                    Expanded(flex: 3, child: body),
                    SizedBox(
                      width: sidePanelWidth,
                      child: scrollSidePanel
                          ? SingleChildScrollView(
                              child: Builder(builder: settingsBuilder),
                            )
                          : Builder(builder: settingsBuilder),
                    ),
                  ],
                ),
        ),
        if (touch)
          ToolSettingsDock(
            tooltip: settingsTooltip,
            onPressed: () => showToolConfigBottomSheet(
              context: context,
              contentBuilder: settingsBuilder,
            ),
          ),
      ],
    );
  }
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
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      color: t.surfaceHigh,
      child: Container(
        key: const ValueKey<String>('tool-settings-dock'),
        height: context.touchSize + bottomInset,
        padding: EdgeInsets.only(
          right: VisionMetrics.space8,
          bottom: bottomInset,
        ),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.borderSubtle)),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(
            Icons.tune,
            size: VisionMetrics.iconMedium,
            color: t.accentEdit,
          ),
        ),
      ),
    );
  }
}
