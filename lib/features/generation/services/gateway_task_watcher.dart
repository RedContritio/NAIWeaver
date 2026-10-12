import 'dart:async';
import 'dart:typed_data';

import '../../../core/gateway/backend_exception.dart';
import '../../../core/services/backend_history_api.dart';
import '../models/generated_image_item.dart';

/// The progress shown for a gateway item status. `success` stays "generating"
/// until the image has been fetched, so an item never steps back to "queued".
GenerationTaskProgress progressForGatewayStatus(String status) {
  return switch (status) {
    'running' || 'success' => GenerationTaskProgress.generating,
    'failed' => GenerationTaskProgress.failed,
    'rejected' => GenerationTaskProgress.rejected,
    'cancelled' => GenerationTaskProgress.cancelled,
    _ => GenerationTaskProgress.queued,
  };
}

bool isFinalGatewayStatus(String status) =>
    status == 'success' ||
    status == 'failed' ||
    status == 'rejected' ||
    status == 'cancelled';

/// Stops a [GatewayTaskWatcher.watch] from the outside (new run, account
/// switch, dispose). Cancelling is idempotent.
class GatewayWatchToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// The server did not finish the items within the watcher's total time.
class GatewayWatchTimeout implements Exception {
  const GatewayWatchTimeout();

  @override
  String toString() => 'GatewayWatchTimeout';
}

/// Follows the items of one gateway submission until each is final: the one
/// place that polls, fetches images and decides what is fatal.
///
/// The gateway keeps running the work whatever the client does, so stopping
/// (cancel, timeout, error) never loses the server's result; the caller can
/// watch the same items again later.
class GatewayTaskWatcher {
  GatewayTaskWatcher({
    required BackendHistoryApi api,
    this.pollInterval = const Duration(seconds: 1),
    this.timeout = const Duration(minutes: 30),
    this.maxBackoff = const Duration(seconds: 15),
  }) : _api = api;

  final BackendHistoryApi _api;
  final Duration pollInterval;

  /// Total time one [watch] may take.
  final Duration timeout;
  final Duration maxBackoff;

  static const _maxPollFailures = 8;
  static const _maxImageFailures = 8;
  static const _missingImageFailures = 3;

  /// Follows [itemIds] of submission [taskId].
  ///
  /// [onItem] sees every poll of a followed item; [onImage] delivers a
  /// successful item's bytes (fetched concurrently); [onImageFailed] reports an
  /// image that cannot be fetched at all. Returns when every item is final or
  /// [token] was cancelled; throws [GatewayWatchTimeout] when time runs out and
  /// the [BackendException] of a failure that polling again cannot fix (the
  /// session ended, no access, the task is gone, the gateway stays down).
  Future<void> watch({
    required String taskId,
    required Set<String> itemIds,
    required GatewayWatchToken token,
    required void Function(ServerHistoryItem item) onItem,
    required void Function(ServerHistoryItem item, Uint8List bytes) onImage,
    required void Function(ServerHistoryItem item, Object error) onImageFailed,
  }) async {
    final pending = {...itemIds};
    final imageFailures = <String, int>{};
    final deadline = DateTime.now().add(timeout);
    var pollFailures = 0;
    var backoff = pollInterval;

    while (pending.isNotEmpty && !token.isCancelled) {
      if (DateTime.now().isAfter(deadline)) throw const GatewayWatchTimeout();
      final ServerGenerationTask task;
      try {
        task = await _api.fetchGenerationTask(taskId);
        pollFailures = 0;
        backoff = pollInterval;
      } on BackendException catch (error) {
        if (error.isNotAuthenticated ||
            error.statusCode == 403 ||
            error.statusCode == 404 ||
            ++pollFailures >= _maxPollFailures) {
          rethrow;
        }
        await _sleep(backoff, token);
        backoff = Duration(
          milliseconds: (backoff.inMilliseconds * 2).clamp(
            pollInterval.inMilliseconds,
            maxBackoff.inMilliseconds,
          ),
        );
        continue;
      }
      if (token.isCancelled) return;

      final followed = task.items
          .where((item) => pending.contains(item.id))
          .toList();
      final downloads = <Future<void>>[];
      for (final item in followed) {
        onItem(item);
        if (item.status == 'success') {
          downloads.add(
            _download(
              item,
              token,
              imageFailures,
              onImage: (bytes) {
                pending.remove(item.id);
                onImage(item, bytes);
              },
              onFailed: (error) {
                pending.remove(item.id);
                onImageFailed(item, error);
              },
            ),
          );
        } else if (isFinalGatewayStatus(item.status)) {
          pending.remove(item.id);
        }
      }
      await Future.wait(downloads);
      if (pending.isEmpty) return;
      await _sleep(pollInterval, token);
    }
  }

  /// Fetches one image. A failure that may pass leaves the item pending for
  /// the next poll.
  Future<void> _download(
    ServerHistoryItem item,
    GatewayWatchToken token,
    Map<String, int> failures, {
    required void Function(Uint8List bytes) onImage,
    required void Function(Object error) onFailed,
  }) async {
    try {
      final bytes = await _api.fetchImageBytes(item.id);
      if (!token.isCancelled) onImage(bytes);
    } on BackendException catch (error) {
      if (error.isNotAuthenticated) rethrow;
      final count = failures[item.id] = (failures[item.id] ?? 0) + 1;
      final status = error.statusCode;
      final permanent =
          status == 403 ||
          (status == 404 && count >= _missingImageFailures) ||
          count >= _maxImageFailures;
      if (permanent && !token.isCancelled) onFailed(error);
    }
  }

  Future<void> _sleep(Duration duration, GatewayWatchToken token) =>
      Future.any([Future<void>.delayed(duration), token.whenCancelled]);
}
