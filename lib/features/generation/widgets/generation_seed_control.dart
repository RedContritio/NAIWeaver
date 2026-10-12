import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/section_title.dart';
import '../services/seed_policy.dart';

enum GenerationSeedControlVariant { compact, full }

/// The single presentation and input-policy boundary for generation seeds.
///
/// Both variants deliberately keep the seed visible while random mode is on;
/// random mode only makes the value read-only. This avoids two controls for the
/// same state developing different validation or toggle behavior.
class GenerationSeedControl extends StatelessWidget {
  const GenerationSeedControl({
    super.key,
    required this.controller,
    required this.randomize,
    required this.onRandomizeChanged,
    this.variant = GenerationSeedControlVariant.full,
  });

  static const compactKey = ValueKey<String>('generation-seed-compact');
  static const fullKey = ValueKey<String>('generation-seed-full');

  final TextEditingController controller;
  final bool randomize;
  final ValueChanged<bool> onRandomizeChanged;
  final GenerationSeedControlVariant variant;

  /// Whether the seed box holds something other than a seed in
  /// `0..4294967295`. Random mode ignores the box, so it is never invalid.
  static bool isInvalidSeed(String text, {required bool randomize}) =>
      !randomize && parseSeedInput(text) == null;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => _buildControl(
        context,
        invalid: isInvalidSeed(value.text, randomize: randomize),
      ),
    );
  }

  Widget _buildControl(BuildContext context, {required bool invalid}) {
    final compact = variant == GenerationSeedControlVariant.compact;
    final t = context.t;
    final field = TextField(
      key: ValueKey<String>(
        compact
            ? 'generation-seed-field-compact'
            : 'generation-seed-field-full',
      ),
      controller: controller,
      readOnly: randomize,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
        fontSize: t.fontSize(compact ? 9 : 11),
        color: randomize ? t.textDisabled : t.textPrimary,
        letterSpacing: compact ? 1 : 0,
      ),
      decoration: InputDecoration(
        isDense: compact,
        hintText: context.l.panelSeed.toUpperCase(),
        hintStyle: TextStyle(fontSize: t.fontSize(9), color: t.textMinimal),
        errorText: invalid ? context.l.generationSeedInvalid : null,
        errorMaxLines: 2,
        errorStyle: TextStyle(fontSize: t.fontSize(9), color: t.accentDanger),
        fillColor: compact
            ? t.background.withValues(alpha: 0.8)
            : t.borderSubtle,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: VisionMetrics.borderRadius4,
          borderSide: compact
              ? BorderSide(color: t.borderSubtle)
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: VisionMetrics.borderRadius4,
          borderSide: compact
              ? BorderSide(color: t.borderSubtle)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: VisionMetrics.borderRadius4,
          borderSide: BorderSide(color: t.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: VisionMetrics.borderRadius4,
          borderSide: BorderSide(color: t.accentDanger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: VisionMetrics.borderRadius4,
          borderSide: BorderSide(color: t.accentDanger),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? VisionMetrics.space8 : VisionMetrics.space12,
          vertical: compact ? VisionMetrics.space4 : 10,
        ),
        suffixIconConstraints: BoxConstraints(
          minWidth: compact ? 28 : 48,
          minHeight: compact ? 24 : 48,
        ),
        suffixIcon: IconButton(
          key: ValueKey<String>(
            compact
                ? 'generation-seed-toggle-compact'
                : 'generation-seed-toggle-full',
          ),
          tooltip: context.l.panelSeed,
          onPressed: () => onRandomizeChanged(!randomize),
          icon: Icon(
            randomize ? Icons.shuffle : Icons.tag,
            size: VisionMetrics.iconSmall,
            color: randomize ? t.textSecondary : t.textDisabled,
          ),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
          padding: EdgeInsets.zero,
        ),
      ),
    );

    if (compact) {
      return Row(
        key: compactKey,
        children: [
          Icon(
            Icons.casino,
            size: VisionMetrics.iconSmall,
            color: randomize ? t.accent : t.textDisabled,
          ),
          const SizedBox(width: VisionMetrics.space8),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: field,
            ),
          ),
        ],
      );
    }

    return Column(
      key: fullKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.l.panelSeed.toUpperCase(), t: t),
        field,
      ],
    );
  }
}
