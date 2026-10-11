import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/ui/app_sheet.dart';

/// The one long-press / secondary-click menu for the chips in the generation
/// settings (styles, vibes, character presets, ...).
///
/// Long press always opens this menu, so a gesture never edits on one chip and
/// deletes on the next. Deleting asks for confirmation first.
///
/// [onEdit] and [onDelete] are optional: an entry without a callback is left
/// out. [deleteMessage] is the confirmation text.
Future<void> showChipActions(
  BuildContext context, {
  required String title,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  String? deleteMessage,
}) async {
  final choice = await showAppSheet<_ChipAction>(
    context: context,
    builder: (sheetContext) {
      final t = sheetContext.t;
      final l = sheetContext.l;
      return AppPickerSheet(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              ListTile(
                leading: Icon(
                  Icons.edit_outlined,
                  size: VisionMetrics.iconMedium,
                  color: t.textSecondary,
                ),
                title: Text(l.commonEdit),
                onTap: () => Navigator.pop(sheetContext, _ChipAction.edit),
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  size: VisionMetrics.iconMedium,
                  color: t.accentDanger,
                ),
                title: Text(
                  l.commonDelete,
                  style: TextStyle(color: t.accentDanger),
                ),
                onTap: () => Navigator.pop(sheetContext, _ChipAction.delete),
              ),
          ],
        ),
      );
    },
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case _ChipAction.edit:
      onEdit?.call();
    case _ChipAction.delete:
      final confirmed = await showConfirmDialog(
        context,
        title: context.l.commonDelete,
        message: deleteMessage ?? title,
        confirmLabel: context.l.commonDelete,
        cancelLabel: context.l.commonCancel,
      );
      if (confirmed == true) onDelete?.call();
  }
}

enum _ChipAction { edit, delete }

/// Opens [builder] in an app sheet for content that already pads itself for
/// the keyboard (the editor sheets). The sheet's own keyboard padding would
/// count it twice, so the view insets are hidden from the content.
Future<T?> showSelfPaddedSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showAppSheet<T>(
    context: context,
    builder: (sheetContext) => MediaQuery.removeViewInsets(
      context: sheetContext,
      removeBottom: true,
      child: Builder(builder: builder),
    ),
  );
}
