import '../../l10n/app_localizations.dart';
import 'ml_model_entry.dart';

extension MLModelEntryL10n on MLModelEntry {
  /// The model's one-line description in the UI language. Falls back to the
  /// registry's English text for ids without a translation.
  String localizedDescription(AppLocalizations l) => switch (id) {
        'isnet_anime' => l.mlModelDescIsnetAnime,
        'rmbg20_q4f16' => l.mlModelDescRmbgQuantized,
        'rmbg20_fp16' => l.mlModelDescRmbgBest,
        'span_2x_dc' => l.mlModelDescUpscaleFast,
        'compact_2x' => l.mlModelDescUpscaleMobile,
        'realplksr_2x_dc' => l.mlModelDescUpscaleBest,
        'sam21_tiny_encoder' => l.mlModelDescSamEncoder,
        'sam21_tiny_decoder' => l.mlModelDescSamDecoder,
        _ => description,
      };
}
