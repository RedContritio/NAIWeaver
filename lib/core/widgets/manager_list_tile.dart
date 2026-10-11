import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';

/// Smallest hit area for any action in a manager list or header.
const double kManagerTouchTarget = 40;

ButtonStyle _managerButtonStyle() => IconButton.styleFrom(
  fixedSize: const Size.square(kManagerTouchTarget),
  minimumSize: const Size.square(kManagerTouchTarget),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

/// Icon action with a fixed [kManagerTouchTarget] hit area on every platform.
class ManagerIconButton extends StatelessWidget {
  const ManagerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color ?? context.t.textDisabled),
      tooltip: tooltip,
      onPressed: onPressed,
      style: _managerButtonStyle(),
    );
  }
}

/// One entry of a list row's overflow menu.
class ManagerListAction {
  const ManagerListAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Label row above a manager list, with its list-level actions.
class ManagerListHeader extends StatelessWidget {
  const ManagerListHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(8),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Row of a manager list. The title always truncates to one line, and every
/// per-item action lives in an always-visible overflow menu so it is equally
/// reachable by mouse and touch (no hover-only or selection-only buttons).
class ManagerListTile extends StatelessWidget {
  const ManagerListTile({
    super.key,
    required this.title,
    this.titleStyle,
    this.subtitle,
    this.subtitleStyle,
    this.leading,
    this.dragIndex,
    this.selected = false,
    this.onTap,
    this.inlineActions = const [],
    this.menuActions = const [],
  });

  static const titleKey = ValueKey<String>('manager-list-tile-title');
  static const menuKey = ValueKey<String>('manager-list-tile-menu');

  final String title;

  /// Merged over the default title style; truncation is not overridable.
  final TextStyle? titleStyle;
  final String? subtitle;
  final TextStyle? subtitleStyle;
  final Widget? leading;

  /// When set, a drag handle for a [ReorderableListView] slot is shown.
  final int? dragIndex;
  final bool selected;
  final VoidCallback? onTap;

  /// Frequent toggles kept beside the menu; use [ManagerIconButton].
  final List<Widget> inlineActions;
  final List<ManagerListAction> menuActions;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final textColor = selected ? t.textPrimary : t.secondaryText;
    return Material(
      color: selected ? t.borderSubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kManagerTouchTarget),
          child: Padding(
            padding: EdgeInsets.only(
              left: dragIndex == null ? 12 : 0,
              right: 4,
              top: 2,
              bottom: 2,
            ),
            child: Row(
              children: [
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: SizedBox.square(
                      dimension: kManagerTouchTarget,
                      child: Icon(
                        Icons.drag_handle,
                        size: 16,
                        color: t.textDisabled,
                      ),
                    ),
                  ),
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: titleKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: t.fontSize(11),
                          letterSpacing: 1,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ).merge(titleStyle),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? t.textTertiary : t.textMinimal,
                              fontSize: t.fontSize(7),
                              letterSpacing: 1,
                            ).merge(subtitleStyle),
                          ),
                        ),
                    ],
                  ),
                ),
                ...inlineActions,
                if (menuActions.isNotEmpty)
                  PopupMenuButton<int>(
                    key: menuKey,
                    icon: Icon(Icons.more_vert, size: 18, color: t.textDisabled),
                    color: t.surfaceHigh,
                    style: _managerButtonStyle(),
                    onSelected: (index) => menuActions[index].onSelected(),
                    itemBuilder: (_) => [
                      for (var i = 0; i < menuActions.length; i++)
                        PopupMenuItem<int>(
                          value: i,
                          child: _MenuEntry(action: menuActions[i]),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({required this.action});

  final ManagerListAction action;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = action.destructive ? t.accentDanger : t.textSecondary;
    return Row(
      children: [
        Icon(action.icon, size: 16, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            action.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: t.fontSize(10),
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}
