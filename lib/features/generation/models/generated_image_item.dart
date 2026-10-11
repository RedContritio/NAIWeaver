import 'dart:typed_data';

enum GenerationTaskProgress { queued, generating, failed, rejected, cancelled }

/// One slot of the result set: pending, finished or failed. It is the only
/// place that knows an image's bytes, metadata, seed and whether it was saved.
class GeneratedImageItem {
  final String id;

  /// The run that created the item. Results of an older run never write to it.
  final int runId;
  final Uint8List? bytes;

  /// The metadata the image is saved with, frozen when the request was
  /// submitted: later edits of the form never change it.
  final Map<String, dynamic>? metadata;
  final int batchIndex;
  final int batchCount;
  final int? seed;
  final bool isLoading;
  final GenerationTaskProgress progress;
  final bool duplicateImageDetected;
  final bool saved;
  final String? savedBasename;
  final String? errorMessage;

  /// The client stopped following the item while the server may still finish
  /// it; following it again can still deliver the image.
  final bool retryable;

  const GeneratedImageItem({
    required this.id,
    required this.batchIndex,
    required this.batchCount,
    this.runId = 0,
    this.bytes,
    this.metadata,
    this.seed,
    this.isLoading = false,
    this.progress = GenerationTaskProgress.queued,
    this.duplicateImageDetected = false,
    this.saved = false,
    this.savedBasename,
    this.errorMessage,
    this.retryable = false,
  });

  bool get isComplete => bytes != null;
  bool get isFailed =>
      progress == GenerationTaskProgress.failed ||
      progress == GenerationTaskProgress.rejected ||
      progress == GenerationTaskProgress.cancelled;
  bool get isTerminal => isComplete || isFailed;

  GeneratedImageItem copyWith({
    Uint8List? bytes,
    Map<String, dynamic>? metadata,
    int? seed,
    bool? isLoading,
    GenerationTaskProgress? progress,
    bool? duplicateImageDetected,
    bool? saved,
    String? savedBasename,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? retryable,
  }) {
    return GeneratedImageItem(
      id: id,
      runId: runId,
      batchIndex: batchIndex,
      batchCount: batchCount,
      bytes: bytes ?? this.bytes,
      metadata: metadata ?? this.metadata,
      seed: seed ?? this.seed,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      duplicateImageDetected:
          duplicateImageDetected ?? this.duplicateImageDetected,
      saved: saved ?? this.saved,
      savedBasename: savedBasename ?? this.savedBasename,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      retryable: retryable ?? this.retryable,
    );
  }
}
