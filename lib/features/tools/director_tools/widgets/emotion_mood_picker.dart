import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/widgets/ui/app_tabs.dart';
import '../models/augment_tool.dart';

class EmotionMoodPicker extends StatelessWidget {
  final EmotionMood selected;
  final ValueChanged<EmotionMood> onSelected;

  const EmotionMoodPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AppSegmented<EmotionMood>(
      options: [
        for (final mood in EmotionMood.values)
          AppOption(value: mood, label: mood.label(l)),
      ],
      selected: selected,
      onChanged: onSelected,
    );
  }
}
