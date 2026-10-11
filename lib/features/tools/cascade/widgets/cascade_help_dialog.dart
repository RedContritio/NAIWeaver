import 'package:flutter/material.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/theme/vision_metrics.dart';

void showCascadeHelpDialog(BuildContext context) {
  final t = context.tRead;
  final l = context.l;
  final mobile = isTouchSized(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.cascadeHelpTitle,
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
                _sectionHeader(t, l.cascadeHelpOverviewHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _paragraph(t, l.cascadeHelpOverviewBody, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpSetupHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _stepRow(t, '1', l.cascadeHelpStepCreate, l.cascadeHelpStepCreateDesc, mobile),
                _stepRow(t, '2', l.cascadeHelpStepEdit, l.cascadeHelpStepEditDesc, mobile),
                _stepRow(t, '3', l.cascadeHelpStepCast, l.cascadeHelpStepCastDesc, mobile),
                _stepRow(t, '4', l.cascadeHelpStepGenerate, l.cascadeHelpStepGenerateDesc, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpBasePromptHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _bulletRow(t, l.cascadeHelpScene, l.cascadeHelpSceneDesc, mobile),
                _bulletRow(t, l.cascadeHelpEnvironment, l.cascadeHelpEnvironmentDesc, mobile),
                const SizedBox(height: VisionMetrics.space4),
                _paragraph(t, l.cascadeHelpBasePromptNote, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpSlotsHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _bulletRow(t, l.cascadeHelpSlotPositive, l.cascadeHelpSlotPositiveDesc, mobile),
                _bulletRow(t, l.cascadeHelpSlotNegative, l.cascadeHelpSlotNegativeDesc, mobile),
                _bulletRow(t, l.cascadeHelpSlotGrid, l.cascadeHelpSlotGridDesc, mobile),
                _bulletRow(t, l.cascadeHelpSlotActions, l.cascadeHelpSlotActionsDesc, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpActionsHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _paragraph(t, l.cascadeHelpActionsIntro, mobile),
                const SizedBox(height: VisionMetrics.space4),
                _bulletRow(t, l.cascadeHelpSourceTarget, l.cascadeHelpSourceTargetDesc, mobile),
                _bulletRow(t, l.cascadeHelpMutual, l.cascadeHelpMutualDesc, mobile),
                const SizedBox(height: VisionMetrics.space4),
                _paragraph(t, l.cascadeHelpActionsNote, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpCastingHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _bulletRow(t, l.cascadeHelpCastAppearance, l.cascadeHelpCastAppearanceDesc, mobile),
                _bulletRow(t, l.cascadeHelpCastGlobalScene, l.cascadeHelpCastGlobalSceneDesc, mobile),
                _bulletRow(t, l.cascadeHelpCastInjection, l.cascadeHelpCastInjectionDesc, mobile),
                _bulletRow(t, l.cascadeHelpCastThumbs, l.cascadeHelpCastThumbsDesc, mobile),
                _bulletRow(t, l.cascadeHelpCastCaption, l.cascadeHelpCastCaptionDesc, mobile),
                _bulletRow(t, l.cascadeHelpCastExport, l.cascadeHelpCastExportDesc, mobile),
                _bulletRow(t, l.cascadeHelpCastGenerate, l.cascadeHelpCastGenerateDesc, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpPerBeatHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _paragraph(t, l.cascadeHelpPerBeatBody, mobile),

                _divider(t),

                _sectionHeader(t, l.cascadeHelpTipsHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _tipRow(t, l.cascadeHelpTip1, mobile),
                _tipRow(t, l.cascadeHelpTip2, mobile),
                _tipRow(t, l.cascadeHelpTip3, mobile),
                _tipRow(t, l.cascadeHelpTip4, mobile),
                _tipRow(t, l.cascadeHelpTip5, mobile),
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

Widget _stepRow(
  VisionTokens t,
  String number,
  String title,
  String description,
  bool mobile,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: VisionMetrics.opacityPressed),
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
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
        const SizedBox(width: VisionMetrics.space8),
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

Widget _bulletRow(
  VisionTokens t,
  String label,
  String description,
  bool mobile,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
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
          style: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(mobile ? 12 : 11),
          ),
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
      const SizedBox(height: VisionMetrics.space16),
      Divider(
        color: t.textDisabled.withValues(alpha: VisionMetrics.opacityDisabled),
        height: 1,
      ),
      const SizedBox(height: VisionMetrics.space16),
    ],
  );
}
