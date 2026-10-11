import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_exception.dart';
import 'package:naiweaver/core/gateway/backend_rules.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';

import 'support/fake_gateway_adapter.dart';

/// A paid submit whose response is lost must be resent with the same
/// `client_request_id` and body (the gateway replays idempotently), and a
/// still-lost response must find the task the gateway already holds.
void main() {
  final rules = ImageRules.tryParse(rulesJson())!;
  const seeds = [11, 22];

  Map<String, dynamic> acceptedJson() => {
    'task_id': 'task-1',
    'items': [
      {'id': 'a', 'batch_index': 1, 'status': 'queued'},
      {'id': 'b', 'batch_index': 2, 'status': 'queued'},
    ],
  };

  Map<String, dynamic> currentTaskJson({List<int> taskSeeds = seeds}) => {
    'task': {
      'id': 'task-1',
      'status': 'queued',
      'items': [
        for (var i = 0; i < taskSeeds.length; i++)
          {
            'id': 'item-$i',
            'batch_index': i + 1,
            'status': 'queued',
            'seed': taskSeeds[i],
          },
      ],
    },
  };

  NovelAIService service(FakeGatewayAdapter adapter) => NovelAIService(
    '',
    client: clientOver(adapter),
    gateway: true,
    submitRetryDelays: const [Duration.zero, Duration.zero],
  );

  Future<GatewayGenerationSubmission> submit(NovelAIService s) {
    final request = s.buildImageGenerationRequest(
      prompt: '1girl',
      negativePrompt: '',
      width: 832,
      height: 1216,
      seed: seeds.first,
    );
    return s.submitGatewayBatch(
      request: request,
      seeds: seeds,
      clientRequestId: 'request-id-1',
      rules: rules,
    );
  }

  test('a lost response is resent with the same id and body', () async {
    var posts = 0;
    final adapter = FakeGatewayAdapter((options) {
      if (options.method == 'POST') {
        if (posts++ == 0) throw connectionFailure(options);
        return jsonResponse(acceptedJson(), status: 202);
      }
      fail('unexpected ${options.method} ${options.uri.path}');
    });

    final submission = await submit(service(adapter));

    expect(submission.taskId, 'task-1');
    final bodies = adapter.requests.map((r) => r.data).toList();
    expect(bodies, hasLength(2));
    expect(bodies[1], bodies[0]);
    expect((bodies[1] as Map)['client_request_id'], 'request-id-1');
  });

  test('a response that never arrives resumes the task on the server', () async {
    final adapter = FakeGatewayAdapter((options) {
      if (options.method == 'POST') throw connectionFailure(options);
      return jsonResponse(currentTaskJson());
    });

    final submission = await submit(service(adapter));

    expect(adapter.count('POST', '/api/generation-tasks'), 3);
    expect(submission.taskId, 'task-1');
    expect(submission.items.map((i) => i.id), ['item-0', 'item-1']);
  });

  test('no matching task surfaces the network error', () async {
    final adapter = FakeGatewayAdapter((options) {
      if (options.method == 'POST') throw connectionFailure(options);
      return jsonResponse(currentTaskJson(taskSeeds: [1, 2]));
    });

    await expectLater(
      submit(service(adapter)),
      throwsA(
        isA<BackendException>().having((e) => e.isNetworkError, 'net', true),
      ),
    );
  });

  test('an answer from the gateway is never resent', () async {
    final adapter = FakeGatewayAdapter(
      (options) => jsonResponse(gatewayError('upstream_error'), status: 502),
    );

    await expectLater(
      submit(service(adapter)),
      throwsA(isA<BackendException>()),
    );
    expect(adapter.count('POST', '/api/generation-tasks'), 1);
  });
}
