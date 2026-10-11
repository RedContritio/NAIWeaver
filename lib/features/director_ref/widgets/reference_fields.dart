import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/editable_slider_value.dart';
import '../../../core/widgets/enabled_toggle.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/vision_slider.dart';
import '../../../l10n/app_localizations.dart';
import '../models/director_reference.dart';

// Field widgets shared by the shelf editor sheets and the Tools → References
// cards, for both precise references and vibes.

String localizedRefType(AppLocalizations l, DirectorReferenceType type) {
  switch (type) {
    case DirectorReferenceType.character:
      return l.refTypeCharacter;
    case DirectorReferenceType.style:
      return l.refTypeStyle;
    case DirectorReferenceType.characterAndStyle:
      return l.refTypeCharAndStyle;
  }
}

Color refTypeColor(VisionTokens t, DirectorReferenceType type) {
  switch (type) {
    case DirectorReferenceType.character:
      return t.accentRefCharacter;
    case DirectorReferenceType.style:
      return t.accentRefStyle;
    case DirectorReferenceType.characterAndStyle:
      return t.accentRefCharStyle;
  }
}

/// Character / style / both picker for a precise reference.
class DirectorRefTypeSelector extends StatelessWidget {
  const DirectorRefTypeSelector({
    super.key,
    required this.type,
    required this.onChanged,
  });

  final DirectorReferenceType type;
  final ValueChanged<DirectorReferenceType> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        for (final option in DirectorReferenceType.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _TypeChip(
                label: localizedRefType(context.l, option),
                color: refTypeColor(t, option),
                selected: option == type,
                onTap: () => onChanged(option),
              ),
            ),
          ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: kManagerTouchTarget),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : t.borderSubtle,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? color : t.textMinimal,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: t.fontSize(8),
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: selected ? color : t.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Labelled 0..1 slider with a tappable value for typed entry.
class ReferenceSliderField extends StatelessWidget {
  const ReferenceSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: t.fontSize(9),
                  letterSpacing: 2,
                  color: t.textDisabled,
                ),
              ),
            ),
            EditableSliderValue(
              value: value,
              softMin: 0.0,
              softMax: 1.0,
              decimals: 2,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: t.fontSize(10),
                color: t.textTertiary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        VisionSlider(
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
          activeColor: accent.withValues(alpha: 0.5),
          inactiveColor: t.textMinimal,
          thumbColor: accent,
          thumbRadius: 6,
        ),
      ],
    );
  }
}

/// A current reference or vibe in Tools → References: thumbnail, enable
/// toggle, library/remove actions and its editing fields. A disabled or
/// paused entry is dimmed (it stays editable) so it reads the same as in the
/// shelf; a paused one also says why it is not sent.
class ReferenceItemCard extends StatelessWidget {
  const ReferenceItemCard({
    super.key,
    required this.image,
    required this.accent,
    required this.enabled,
    required this.onToggleEnabled,
    required this.saveTooltip,
    required this.onSave,
    required this.onRemove,
    required this.children,
    this.pausedReason,
  });

  /// Opacity of a disabled entry's image and fields.
  static const disabledOpacity = 0.45;

  final Uint8List image;
  final Color accent;
  final bool enabled;
  final VoidCallback onToggleEnabled;
  final String saveTooltip;
  final VoidCallback onSave;
  final VoidCallback onRemove;

  /// Type selector / label and the slider fields.
  final List<Widget> children;

  /// Why an enabled entry is not sent (the account lacks paid access); null
  /// when it is.
  final String? pausedReason;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final thumbSize = isMobile(context) ? 64.0 : 80.0;
    final paused = pausedReason;
    final opacity = enabled && paused == null ? 1.0 : disabledOpacity;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: enabled && paused == null
              ? accent.withValues(alpha: 0.3)
              : t.textMinimal,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: opacity,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accent, width: 1),
                    image: DecorationImage(
                      image: MemoryImage(image),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    EnabledToggle(
                      enabled: enabled,
                      accent: accent,
                      onTap: onToggleEnabled,
                    ),
                    ManagerIconButton(
                      icon: Icons.bookmark_border,
                      tooltip: saveTooltip,
                      onPressed: onSave,
                    ),
                    ManagerIconButton(
                      icon: Icons.close,
                      tooltip: context.l.refRemove,
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (paused != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.pause_circle_outline,
                  size: 14,
                  color: t.accentDanger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    paused,
                    style: TextStyle(
                      color: t.accentDanger,
                      fontSize: t.fontSize(9),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Opacity(
            opacity: opacity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
