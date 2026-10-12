import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/theme_extensions.dart';
import '../theme/vision_metrics.dart';
import '../utils/responsive.dart';
import 'manager_list_tile.dart';

enum UnsavedChangesDecision { save, discard, cancel }

/// Asks what to do with pending edits; dismissing the dialog cancels.
Future<UnsavedChangesDecision> showUnsavedChangesDialog(
  BuildContext context,
) async {
  final decision = await showDialog<UnsavedChangesDecision>(
    context: context,
    builder: (ctx) {
      final t = ctx.tRead;
      final l = ctx.l;
      Widget action(String label, Color color, UnsavedChangesDecision value) {
        return TextButton(
          onPressed: () => Navigator.pop(ctx, value),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(color: color, fontSize: t.buttonSize(9)),
          ),
        );
      }

      return AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.commonUnsavedTitle.toUpperCase(),
          style: TextStyle(
            fontSize: t.titleSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Text(
          l.commonUnsavedMessage,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
        ),
        actions: [
          action(l.commonCancel, t.textDisabled, UnsavedChangesDecision.cancel),
          action(
            l.commonDiscard,
            t.accentDanger,
            UnsavedChangesDecision.discard,
          ),
          action(l.commonSave, t.accent, UnsavedChangesDecision.save),
        ],
      );
    },
  );
  return decision ?? UnsavedChangesDecision.cancel;
}

/// Pending-edit state of a manager plus how to save or drop it. Every action
/// that would leave the edited item (back, opening another item, closing the
/// manager) goes through [resolve] first.
class UnsavedChangesGuard {
  const UnsavedChangesGuard({
    required this.hasChanges,
    required this.onSave,
    required this.onDiscard,
  });

  final bool hasChanges;

  /// Returns false when saving was abandoned (e.g. overwrite declined).
  final Future<bool> Function() onSave;
  final VoidCallback onDiscard;

  /// Whether the caller may continue: nothing pending, saved, or discarded.
  Future<bool> resolve(BuildContext context) async {
    if (!hasChanges) return true;
    switch (await showUnsavedChangesDialog(context)) {
      case UnsavedChangesDecision.save:
        return onSave();
      case UnsavedChangesDecision.discard:
        onDiscard();
        return true;
      case UnsavedChangesDecision.cancel:
        return false;
    }
  }
}

/// List + editor layout shared by the Tools managers.
///
/// Wide screens show both panes side by side. Phones show one pane at a time:
/// the list under [masterHeader], or the editor under a header with a back
/// button. The system/browser back key first returns from the editor to the
/// list instead of closing Tools, and pending edits from [guard] are resolved
/// before the editor is left or Tools is closed.
class ManagerMasterDetailShell extends StatelessWidget {
  const ManagerMasterDetailShell({
    super.key,
    required this.showDetail,
    required this.master,
    required this.detail,
    required this.detailTitle,
    required this.onCloseDetail,
    this.masterHeader,
    this.detailActions = const [],
    this.guard,
    this.masterWidth = 220,
  });

  static const masterPaneKey = ValueKey<String>('manager-master-pane');
  static const detailPaneKey = ValueKey<String>('manager-detail-pane');

  /// Phone layout only: whether the editor replaces the list.
  final bool showDetail;
  final Widget master;
  final Widget detail;
  final String detailTitle;
  final List<Widget> detailActions;

  /// Called once the phone editor may close; the owner flips [showDetail].
  final VoidCallback onCloseDetail;
  final Widget? masterHeader;
  final UnsavedChangesGuard? guard;
  final double masterWidth;

  Future<bool> _resolve(BuildContext context) async =>
      guard == null || await guard!.resolve(context);

  Future<void> _closeDetail(BuildContext context) async {
    if (await _resolve(context) && context.mounted) onCloseDetail();
  }

  Future<void> _handleBlockedPop(BuildContext context, bool detailOpen) async {
    // A blocked pop also blocks the hub's drawer from closing; close it first.
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null &&
        (scaffold.isDrawerOpen || scaffold.isEndDrawerOpen)) {
      scaffold.closeDrawer();
      scaffold.closeEndDrawer();
      return;
    }
    if (detailOpen) {
      await _closeDetail(context);
    } else if (await _resolve(context) && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mobile = windowSizeClassOf(context) == WindowSizeClass.compact;
    final detailOpen = mobile && showDetail;
    final divider = Divider(height: 1, color: t.textMinimal);

    final Widget body;
    if (mobile) {
      final header = detailOpen
          ? ManagerHeader(
              title: detailTitle,
              onBack: () => _closeDetail(context),
              actions: detailActions,
            )
          : masterHeader;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header, divider],
          Expanded(
            child: KeyedSubtree(
              key: detailOpen ? detailPaneKey : masterPaneKey,
              child: detailOpen ? detail : master,
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (masterHeader != null) ...[masterHeader!, divider],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: masterWidth,
                  child: KeyedSubtree(key: masterPaneKey, child: master),
                ),
                VerticalDivider(width: 1, color: t.textMinimal),
                Expanded(
                  child: KeyedSubtree(key: detailPaneKey, child: detail),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final blocksPop = detailOpen || (guard?.hasChanges ?? false);
    return PopScope<Object?>(
      canPop: !blocksPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && blocksPop) _handleBlockedPop(context, detailOpen);
      },
      child: body,
    );
  }
}

/// Header of a manager pane. With [onBack] it is the compact editor header
/// (back button + item name); without, the manager's title block.
class ManagerHeader extends StatelessWidget {
  const ManagerHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  static const titleKey = ValueKey<String>('manager-header-title');

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final compact = onBack != null;
    final titleText = Text(
      title,
      key: titleKey,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: compact
          ? TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(11),
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            )
          : TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(16),
              letterSpacing: 4,
              fontWeight: FontWeight.w900,
            ),
    );

    return Container(
      width: double.infinity,
      padding: compact
          ? const EdgeInsets.all(VisionMetrics.space4)
          : const EdgeInsets.fromLTRB(
              VisionMetrics.space16,
              VisionMetrics.space12,
              VisionMetrics.space8,
              VisionMetrics.space12,
            ),
      color: compact ? t.surfaceMid : t.surfaceHigh,
      child: Row(
        children: [
          if (onBack != null) ...[
            ManagerIconButton(
              icon: Icons.arrow_back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
            ),
            const SizedBox(width: VisionMetrics.space4),
          ],
          Expanded(
            child: subtitle == null
                ? titleText
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      titleText,
                      const SizedBox(height: VisionMetrics.space4),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.hintText,
                          fontSize: t.fontSize(9),
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: VisionMetrics.space8),
            ...actions,
          ],
        ],
      ),
    );
  }
}

/// "Save changes" action for a master header with pending edits.
class ManagerSaveChangesButton extends StatelessWidget {
  const ManagerSaveChangesButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        Icons.save_outlined,
        size: VisionMetrics.iconSmall,
        color: t.textPrimary,
      ),
      label: Text(
        context.l.commonSaveChanges,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: t.fontSize(10),
          letterSpacing: 1,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: t.borderSubtle,
        padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space16),
      ),
    );
  }
}

class ManagerCountToolbar extends StatelessWidget {
  const ManagerCountToolbar({
    super.key,
    required this.countLabel,
    required this.countStyle,
    required this.clearStyle,
    this.clearLabel,
    this.onClear,
  });

  static const toolbarKey = ValueKey<String>('manager-count-toolbar');

  final String countLabel;
  final String? clearLabel;
  final VoidCallback? onClear;
  final TextStyle countStyle;
  final TextStyle clearStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: toolbarKey,
      padding: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space16,
        vertical: VisionMetrics.space4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onClear != null && clearLabel != null) ...[
            TextButton(
              onPressed: onClear,
              child: Text(clearLabel!, style: clearStyle),
            ),
            const SizedBox(width: VisionMetrics.space8),
          ],
          Flexible(
            child: Text(
              countLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: countStyle,
            ),
          ),
        ],
      ),
    );
  }
}
