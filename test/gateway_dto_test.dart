import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_rules.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';

import 'support/fake_gateway_adapter.dart';

Map<String, dynamic> _row({
  int batchSize = 1,
  bool hasImage = true,
  Map<String, dynamic> extra = const {},
}) => {
  'id': 'item-1',
  'user_id': 7,
  'username': 'tester',
  'batch_id': 'batch-1',
  'batch_index': 0,
  'batch_size': batchSize,
  'status': 'success',
  'error_code': null,
  'mode': 'free',
  'points_charged': 14,
  'prompt': 'p',
  'negative_prompt': '',
  'width': 832,
  'height': 1216,
  'steps': 28,
  'scale': 5,
  'sampler': 'k_euler',
  'seed': 42,
  'request_json': '{}',
  'has_image': hasImage,
  'created_at': '2026-08-25T12:00:00Z',
  'completed_at': null,
  ...extra,
};

void main() {
  group('history items', () {
    test('a batch of one is a single image even though it has a batch id', () {
      final single = ServerHistoryItem.fromJson(_row());
      final batch = ServerHistoryItem.fromJson(_row(batchSize: 4));

      expect(single.batchId, 'batch-1');
      expect(single.isBatch, isFalse);
      expect(batch.isBatch, isTrue);
    });

    test('the image flag comes from has_image, not a stored path', () {
      expect(ServerHistoryItem.fromJson(_row()).hasImage, isTrue);
      expect(
        ServerHistoryItem.fromJson(_row(hasImage: false)).hasImage,
        isFalse,
      );
    });

    test('failure code and charge are kept', () {
      final item = ServerHistoryItem.fromJson(
        _row(
          extra: {
            'status': 'failed',
            'error_code': 'upstream_error',
            'points_charged': 0,
          },
        ),
      );

      expect(item.errorCode, 'upstream_error');
      expect(item.pointsCharged, 0);
      expect(ServerHistoryItem.fromJson(_row()).pointsCharged, 14);
    });
  });

  test('rules are read from the me payload', () {
    final rules = ImageRules.tryParse(meJson(batchLimit: 4)['rules'])!;

    expect(rules.batchLimit, 4);
    expect(rules.maxSteps, 50);
    expect(rules.freeSizes.first, (width: 832, height: 1216));
    expect(rules.toolCaps.augment, 80);
    expect(rules.pricing.freeVibeCount, 4);
    expect(ImageRules.tryParse(null), isNull);
  });
}
