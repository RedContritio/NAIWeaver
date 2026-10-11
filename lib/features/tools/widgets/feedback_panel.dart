import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/gateway/backend_error_messages.dart';
import '../../../core/gateway/backend_exception.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/backend_feedback_api.dart';
import '../../../core/services/client_diagnostics.dart';
import '../../../core/services/client_diagnostics_platform.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/browser_native_selectable_text.dart';
import '../../../l10n/app_localizations.dart';

class FeedbackPanel extends StatefulWidget {
  const FeedbackPanel({
    super.key,
    this.api,
    this.diagnostics,
    this.gatewayAvailable,
    this.clientContextCollector,
  });

  static const descriptionKey = ValueKey<String>('feedback-description');
  static const submitKey = ValueKey<String>('feedback-submit');
  static const ticketKey = ValueKey<String>('feedback-ticket');
  static const copyTicketKey = ValueKey<String>('feedback-copy-ticket');

  /// Counted in Unicode code points, as the gateway counts them.
  static const maxDescriptionLength = 2000;

  final FeedbackApi? api;
  final ClientDiagnostics? diagnostics;
  final bool? gatewayAvailable;
  final Future<Map<String, dynamic>> Function()? clientContextCollector;

  @override
  State<FeedbackPanel> createState() => _FeedbackPanelState();
}

class _FeedbackPanelState extends State<FeedbackPanel> {
  final _descriptionController = TextEditingController();
  late final FeedbackApi _api;
  late final ClientDiagnostics _diagnostics;
  bool _submitting = false;
  String? _ticketId;
  Object? _error;

  bool get _gatewayAvailable => widget.gatewayAvailable ?? useBackendGateway;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? BackendFeedbackApi();
    _diagnostics = widget.diagnostics ?? ClientDiagnostics.instance;
    _diagnostics.record('feedback_panel_opened');
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_gatewayAvailable) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _ticketId = null;
    });
    try {
      final media = MediaQuery.of(context);
      captureClientDiagnosticsPlatformSnapshot(_diagnostics);
      _diagnostics.record('feedback_submission_requested', {
        'diagnostic_event_count': _diagnostics.length,
        'diagnostic_dropped_event_count': _diagnostics.droppedCount,
        'viewport_width': media.size.width,
        'viewport_height': media.size.height,
        'view_insets_bottom': media.viewInsets.bottom,
      });
      final collectedContext = widget.clientContextCollector != null
          ? await widget.clientContextCollector!()
          : await _collectClientContext(media);
      final clientContext = {
        ...collectedContext,
        ..._diagnostics.sessionContext,
      };
      final submission = await _api.submit(
        description: _descriptionController.text,
        clientContext: clientContext,
        diagnostics: _diagnostics.snapshot(),
      );
      if (!mounted) return;
      _diagnostics.reset(reason: 'feedback_submitted');
      _diagnostics.record('feedback_submission_succeeded', {
        'report_id': submission.id,
      });
      setState(() {
        _ticketId = submission.id;
        _descriptionController.clear();
      });
    } catch (error) {
      _diagnostics.record('feedback_submission_failed', {
        'error_type': error.runtimeType.toString(),
      });
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<Map<String, dynamic>> _collectClientContext(
    MediaQueryData media,
  ) async {
    final package = await PackageInfo.fromPlatform();
    final platform = await collectClientPlatformInfo();
    return {
      'app_version': package.version,
      'build_number': package.buildNumber,
      'viewport_width': media.size.width,
      'viewport_height': media.size.height,
      'view_padding_top': media.viewPadding.top,
      'view_padding_right': media.viewPadding.right,
      'view_padding_bottom': media.viewPadding.bottom,
      'view_padding_left': media.viewPadding.left,
      'view_insets_top': media.viewInsets.top,
      'view_insets_right': media.viewInsets.right,
      'view_insets_bottom': media.viewInsets.bottom,
      'view_insets_left': media.viewInsets.left,
      'padding_top': media.padding.top,
      'padding_right': media.padding.right,
      'padding_bottom': media.padding.bottom,
      'padding_left': media.padding.left,
      'orientation': media.orientation.name,
      'device_pixel_ratio': media.devicePixelRatio,
      ...platform,
    };
  }

  String _errorText(AppLocalizations l, Object error) {
    if (error is BackendException) {
      if (error.statusCode == 422) return l.feedbackInvalid;
      return backendErrorMessage(l, error);
    }
    return l.gatewayErrUnknown;
  }

  void _copyTicket() {
    final ticketId = _ticketId;
    if (ticketId == null) return;
    Clipboard.setData(ClipboardData(text: ticketId)).ignore();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showAppSnackBar(context, context.l.feedbackTicketCopied);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    return ListView(
      padding: const EdgeInsets.all(VisionMetrics.space16),
      children: [
        Text(
          l.feedbackTitle.toUpperCase(),
          style: TextStyle(
            color: t.headerText,
            fontSize: t.titleSize(16),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: VisionMetrics.space12),
        Text(
          l.feedbackIntro,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: t.fontSize(11),
            height: 1.5,
          ),
        ),
        const SizedBox(height: VisionMetrics.space12),
        Row(
          children: [
            Icon(
              Icons.circle,
              size: VisionMetrics.space8,
              color: t.accentSuccess,
            ),
            const SizedBox(width: VisionMetrics.space8),
            Expanded(
              child: Text(
                l.feedbackDebugStatus(
                  _diagnostics.length,
                  (_diagnostics.sessionDuration.inSeconds / 60).ceil().clamp(
                    1,
                    100000,
                  ),
                  _diagnostics.droppedCount,
                ),
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(9),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: VisionMetrics.space16),
        AppPanel(
          variant: AppPanelVariant.inset,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: VisionMetrics.iconMedium,
                color: t.accent,
              ),
              const SizedBox(width: VisionMetrics.space8),
              Expanded(
                child: Text(
                  l.feedbackPrivacy,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(10),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: VisionMetrics.space16),
        TextField(
          key: FeedbackPanel.descriptionKey,
          controller: _descriptionController,
          minLines: 3,
          maxLines: 6,
          inputFormatters: [
            _CodePointLimitFormatter(FeedbackPanel.maxDescriptionLength),
          ],
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) => Text(
                '${_descriptionController.text.runes.length}'
                '/${FeedbackPanel.maxDescriptionLength}',
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(9),
                ),
              ),
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
          decoration: InputDecoration(
            labelText: l.feedbackDescriptionLabel,
            hintText: l.feedbackDescriptionHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: VisionMetrics.space12),
        FilledButton.icon(
          key: FeedbackPanel.submitKey,
          onPressed: _submitting || !_gatewayAvailable ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: VisionMetrics.iconMedium,
                  height: VisionMetrics.iconMedium,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bug_report_outlined),
          label: Text(
            _submitting ? l.feedbackSubmitting : l.feedbackSubmit,
            style: TextStyle(fontSize: t.buttonSize(11)),
          ),
        ),
        if (!_gatewayAvailable) ...[
          const SizedBox(height: VisionMetrics.space12),
          ErrorBanner(message: l.feedbackUnavailable),
        ],
        if (_ticketId != null) ...[
          const SizedBox(height: VisionMetrics.space16),
          Text(
            l.feedbackSubmitted,
            style: TextStyle(color: t.accentSuccess, fontSize: t.fontSize(11)),
          ),
          const SizedBox(height: VisionMetrics.space4),
          Row(
            children: [
              Text(
                '${l.feedbackTicketLabel}:',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: t.fontSize(11),
                ),
              ),
              const SizedBox(width: VisionMetrics.space8),
              Expanded(
                child: BrowserNativeSelectableText(
                  key: FeedbackPanel.ticketKey,
                  text: _ticketId!,
                  height: 38,
                  style: TextStyle(
                    color: t.accentSuccess,
                    fontSize: t.fontSize(11),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: FeedbackPanel.copyTicketKey,
                tooltip: l.feedbackCopyTicket,
                onPressed: _copyTicket,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: VisionMetrics.space16),
          ErrorBanner(
            message: '${l.feedbackSubmitFailed}: ${_errorText(l, _error!)}',
          ),
        ],
      ],
    );
  }
}

/// Caps the text at [maxLength] code points. The stock `maxLength` counts
/// grapheme clusters, so a run of emoji would pass the field but still exceed
/// the gateway's code-point limit.
class _CodePointLimitFormatter extends TextInputFormatter {
  const _CodePointLimitFormatter(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxLength) return newValue;
    final text = String.fromCharCodes(newValue.text.runes.take(maxLength));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: newValue.selection.end.clamp(0, text.length),
      ),
    );
  }
}
