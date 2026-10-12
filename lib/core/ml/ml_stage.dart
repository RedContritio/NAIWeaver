import '../../l10n/app_localizations.dart';

/// Progress stage reported by the ML services. Services have no BuildContext,
/// so they report a stage and the UI maps it to localized text.
enum MLStage {
  starting,
  preprocessing,
  analyzing,
  loadingModel,
  loadingEncoder,
  encodingImage,
  runningInference,
  generatingMatte,
  generatingMask,
  applyingMask,
  splittingTiles,
  upscalingTiles,
  recombiningAlpha,
  stitching,
  complete;

  String label(AppLocalizations l) => switch (this) {
        MLStage.starting => l.mlStageStarting,
        MLStage.preprocessing => l.mlStagePreprocessing,
        MLStage.analyzing => l.mlStageAnalyzing,
        MLStage.loadingModel => l.mlStageLoadingModel,
        MLStage.loadingEncoder => l.mlStageLoadingEncoder,
        MLStage.encodingImage => l.mlStageEncodingImage,
        MLStage.runningInference => l.mlStageRunningInference,
        MLStage.generatingMatte => l.mlStageGeneratingMatte,
        MLStage.generatingMask => l.mlStageGeneratingMask,
        MLStage.applyingMask => l.mlStageApplyingMask,
        MLStage.splittingTiles => l.mlStageSplittingTiles,
        MLStage.upscalingTiles => l.mlStageUpscalingTiles,
        MLStage.recombiningAlpha => l.mlStageRecombiningAlpha,
        MLStage.stitching => l.mlStageStitching,
        MLStage.complete => l.mlStageComplete,
      };
}
