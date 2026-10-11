import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/widgets/ui/app_tabs.dart';
import '../models/augment_tool.dart';

class ToolSelector extends StatelessWidget {
  final AugmentTool selected;
  final ValueChanged<AugmentTool> onSelected;

  const ToolSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AppSegmented<AugmentTool>(
      options: [
        for (final tool in AugmentTool.values)
          AppOption(value: tool, label: tool.label(l), icon: tool.icon),
      ],
      selected: selected,
      onChanged: onSelected,
    );
  }
}
