import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/responsive.dart';

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

  @override
  Widget build(BuildContext context) {
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
        fillColor: compact
            ? t.background.withValues(alpha: 0.8)
            : t.borderSubtle,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: compact
              ? BorderSide(color: t.borderSubtle)
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: compact
              ? BorderSide(color: t.borderSubtle)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.accent),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 10,
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
          onPressed: () => onRandomizeChanged(!randomize),
          icon: Icon(
            randomize ? Icons.shuffle : Icons.tag,
            size: 14,
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
            size: 12,
            color: randomize ? t.accent : t.textDisabled,
          ),
          const SizedBox(width: 6),
          Expanded(child: SizedBox(height: 28, child: field)),
        ],
      );
    }

    return Column(
      key: fullKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l.panelSeed.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: t.fontSize(isMobile(context) ? 11 : 9),
            letterSpacing: 1.5,
            color: t.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        field,
      ],
    );
  }
}
