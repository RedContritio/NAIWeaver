import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';
import '../../theme/vision_metrics.dart';

/// One option of an [AppTabBar] or [AppSegmented].
class AppOption<T> {
  const AppOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Underlined tab strip that wraps onto several lines instead of overflowing.
class AppTabBar<T> extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<AppOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Wrap(
        children: [
          for (final o in options)
            _OptionCell(
              option: o,
              selected: o.value == selected,
              onTap: () => onChanged(o.value),
              decorationFor: (isSelected, color) => BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected
                        ? color
                        : t.background.withValues(alpha: 0),
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bordered single-choice group that wraps instead of overflowing.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<AppOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Wrap(
      spacing: VisionMetrics.space4,
      runSpacing: VisionMetrics.space4,
      children: [
        for (final o in options)
          _OptionCell(
            option: o,
            selected: o.value == selected,
            onTap: () => onChanged(o.value),
            decorationFor: (isSelected, color) => BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: VisionMetrics.opacityPressed)
                  : null,
              border: Border.all(color: isSelected ? color : t.borderMedium),
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            ),
          ),
      ],
    );
  }
}

class _OptionCell<T> extends StatelessWidget {
  const _OptionCell({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.decorationFor,
  });

  final AppOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final BoxDecoration Function(bool selected, Color accent) decorationFor;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = selected ? t.accent : t.textTertiary;
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: Container(
          constraints: BoxConstraints(minHeight: context.hitSize),
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space12,
          ),
          decoration: decorationFor(selected, t.accent),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: VisionMetrics.iconMedium, color: color),
                const SizedBox(width: VisionMetrics.space4),
              ],
              Flexible(
                child: Text(
                  option.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: t.fontSize(10),
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
