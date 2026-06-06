import 'package:flutter/material.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/utils/responsive.dart';

void showCascadeHelpDialog(BuildContext context) {
  final t = context.tRead;
  final l = context.l;
  final mobile = isMobile(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          'CASCADE GUIDE',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: t.fontSize(mobile ? 16 : 14),
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9 > 560
              ? 560
              : MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(t, 'OVERVIEW', mobile),
                const SizedBox(height: 8),
                _paragraph(t, 'Cascade generates multi-beat scene sequences with consistent characters. '
                    'Each beat is one generation with its own environment, character poses, and settings. '
                    'Character appearances are set once in the casting sheet and applied to all beats.', mobile),

                _divider(t),

                _sectionHeader(t, 'SETUP FLOW', mobile),
                const SizedBox(height: 8),
                _stepRow(t, '1', 'Create', 'Set name, character count (0-5), and positioning mode', mobile),
                _stepRow(t, '2', 'Edit Beats', 'Set scene/action, environment, character prompts, actions, positions, styles, and settings per beat', mobile),
                _stepRow(t, '3', 'Cast', 'Save and return to the main screen playback view', mobile),
                _stepRow(t, '4', 'Generate', 'Enter character appearances, optional global injection, then generate each beat', mobile),

                _divider(t),

                _sectionHeader(t, 'BASE PROMPT', mobile),
                const SizedBox(height: 8),
                _bulletRow(t, 'Scene / Action', 'Base-prompt tags for what is happening and how it is framed (e.g., "2girls, hugging, wide shot, from above"). Subject-count, action, and camera tags go here.', mobile),
                _bulletRow(t, 'Environment', 'Base-prompt tags for where the scene takes place (e.g., "forest, night, indoors").', mobile),
                const SizedBox(height: 4),
                _paragraph(t, 'Both are tags (not prose) and feed the same base prompt — Scene / Action leads, Environment follows.', mobile),

                _divider(t),

                _sectionHeader(t, 'CHARACTER SLOTS', mobile),
                const SizedBox(height: 8),
                _bulletRow(t, 'Positive Prompt', 'Per-beat character tags (e.g., "happy, sitting")', mobile),
                _bulletRow(t, 'Negative Prompt', 'Per-beat undesired content for this character', mobile),
                _bulletRow(t, 'Position Grid', '5x5 grid for precise placement (if manual positioning is on)', mobile),
                _bulletRow(t, 'Action Tags', 'Define interactions between characters for this beat', mobile),

                _divider(t),

                _sectionHeader(t, 'ACTION INTERACTIONS', mobile),
                const SizedBox(height: 8),
                _paragraph(t, 'Tap the link icon between character slots to set an interaction for that beat.', mobile),
                const SizedBox(height: 4),
                _bulletRow(t, 'Source \u2192 Target', 'Directional action (e.g., A hugging B)', mobile),
                _bulletRow(t, 'Mutual \u2194', 'Both characters participate equally (e.g., holding hands)', mobile),
                const SizedBox(height: 4),
                _paragraph(t, 'Tags are embedded as source#action, target#action, or mutual#action in character prompts.', mobile),

                _divider(t),

                _sectionHeader(t, 'CASTING SHEET', mobile),
                const SizedBox(height: 8),
                _bulletRow(t, 'Character Appearance', 'Base look for each character (e.g., "1girl, blue hair") \u2014 shared across all beats', mobile),
                _bulletRow(t, 'Global Injection', 'Additional prompt text applied to every beat', mobile),
                _bulletRow(t, 'Beat Thumbnails', 'Tap to select; shows preview after generation', mobile),
                _bulletRow(t, 'Generate', 'Generates selected beat, auto-advances to next', mobile),

                _divider(t),

                _sectionHeader(t, 'PER-BEAT SETTINGS', mobile),
                const SizedBox(height: 8),
                _paragraph(t, 'Each beat can have its own resolution, sampler, steps, scale, and styles. '
                    'Styles are toggled per-beat from your style library.', mobile),

                _divider(t),

                _sectionHeader(t, 'TIPS', mobile),
                const SizedBox(height: 8),
                _tipRow(t, 'Use environment tags for scene changes between beats', mobile),
                _tipRow(t, 'Keep character appearances consistent in the casting sheet', mobile),
                _tipRow(t, 'Change action tags per-beat to show interactions evolving', mobile),
                _tipRow(t, 'Clone beats to quickly iterate on similar scenes', mobile),
                _tipRow(t, 'Each beat can use different styles for different moods', mobile),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l.commonClose.toUpperCase(),
              style: TextStyle(
                color: t.accent,
                fontSize: t.fontSize(12),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      );
    },
  );
}

Widget _sectionHeader(VisionTokens t, String label, bool mobile) {
  return Text(
    label,
    style: TextStyle(
      color: t.textSecondary,
      fontSize: t.fontSize(mobile ? 11 : 10),
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
    ),
  );
}

Widget _paragraph(VisionTokens t, String text, bool mobile) {
  return Text(
    text,
    style: TextStyle(
      color: t.textTertiary,
      fontSize: t.fontSize(mobile ? 12 : 11),
      height: 1.4,
    ),
  );
}

Widget _stepRow(VisionTokens t, String number, String title, String description, bool mobile) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: t.accent,
              fontSize: t.fontSize(mobile ? 10 : 9),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title  ',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(mobile ? 12 : 11),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: description,
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(mobile ? 12 : 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _bulletRow(VisionTokens t, String label, String description, bool mobile) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(mobile ? 12 : 11),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: description,
            style: TextStyle(
              color: t.textTertiary,
              fontSize: t.fontSize(mobile ? 12 : 11),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _tipRow(VisionTokens t, String text, bool mobile) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u2022 ',
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(mobile ? 12 : 11)),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: t.textTertiary,
              fontSize: t.fontSize(mobile ? 12 : 11),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _divider(VisionTokens t) {
  return Column(
    children: [
      const SizedBox(height: 16),
      Divider(color: t.textDisabled.withValues(alpha: 0.3), height: 1),
      const SizedBox(height: 16),
    ],
  );
}
