import 'package:flutter/material.dart';

class ManagerMasterDetailShell extends StatelessWidget {
  const ManagerMasterDetailShell({
    super.key,
    required this.mobile,
    required this.showDetail,
    required this.masterHeader,
    required this.detailHeader,
    required this.master,
    required this.detail,
    required this.dividerColor,
    this.showMasterHeaderOnMobile = true,
  });

  static const activeHeaderKey = ValueKey<String>('manager-active-header');
  static const masterPaneKey = ValueKey<String>('manager-master-pane');
  static const detailPaneKey = ValueKey<String>('manager-detail-pane');

  final bool mobile;
  final bool showDetail;
  final Widget masterHeader;
  final Widget detailHeader;
  final Widget master;
  final Widget detail;
  final Color dividerColor;
  final bool showMasterHeaderOnMobile;

  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return Column(
        children: [
          if (showDetail || showMasterHeaderOnMobile) ...[
            KeyedSubtree(
              key: activeHeaderKey,
              child: showDetail ? detailHeader : masterHeader,
            ),
            Divider(height: 1, color: dividerColor),
          ],
          Expanded(
            child: KeyedSubtree(
              key: showDetail ? detailPaneKey : masterPaneKey,
              child: showDetail ? detail : master,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        masterHeader,
        Divider(height: 1, color: dividerColor),
        Expanded(
          child: Row(
            children: [
              KeyedSubtree(key: masterPaneKey, child: master),
              VerticalDivider(width: 1, color: dividerColor),
              Expanded(
                child: KeyedSubtree(key: detailPaneKey, child: detail),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ManagerDetailHeader extends StatelessWidget {
  const ManagerDetailHeader({
    super.key,
    required this.title,
    required this.backgroundColor,
    required this.textStyle,
    required this.iconColor,
    required this.onBack,
    this.actions = const [],
  });

  static const titleKey = ValueKey<String>('manager-detail-header-title');

  final String title;
  final Color backgroundColor;
  final TextStyle textStyle;
  final Color iconColor;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: backgroundColor,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: 18, color: iconColor),
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              key: titleKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          ...actions,
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onClear != null && clearLabel != null) ...[
            TextButton(
              onPressed: onClear,
              child: Text(clearLabel!, style: clearStyle),
            ),
            const SizedBox(width: 8),
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
