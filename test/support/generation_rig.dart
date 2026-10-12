import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:naiweaver/core/gateway/backend_permissions.dart';
import 'package:naiweaver/core/gateway/backend_rules.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/generation/services/gateway_task_watcher.dart';

import '../test_harness.dart';
import 'fake_gateway_adapter.dart';

class StubTags extends TagService {
  StubTags(this.gate) : super(filePath: 'isolated-tags');

  /// Holds the initial load until it completes: a slow startup.
  final Future<void>? gate;

  @override
  Future<void> loadTags() async {
    await gate;
  }
}

/// The real notifier with the network-bound extras (balance) switched off and
/// every file under [dir].
class RigGeneration extends GenerationNotifier {
  RigGeneration({
    required super.preferences,
    required String dir,
    super.serviceFactory,
    super.historyApi,
    super.watcher,
    Future<void>? initializationGate,
  }) : super(
         tagService: StubTags(initializationGate),
         wildcardService: WildcardService(wildcardDir: '$dir/wildcards'),
         outputDir: '$dir/out',
         presetsFilePath: '$dir/presets.json',
         stylesFilePath: '$dir/styles.json',
       );

  @override
  Future<void> fetchAnlas() async {}
}

/// The gateway as the generation sees it: it accepts submissions, keeps the
/// status of each item (tests change them) and serves images.
class FakeGateway {
  FakeGateway(this.image) {
    adapter = _GatedAdapter(this, _handle);
  }

  /// The PNG every successful item serves.
  final Uint8List image;
  late final FakeGatewayAdapter adapter;

  /// Held while it is set: image downloads wait for it.
  Completer<void>? imageGate;

  final Map<String, String> status = {};
  final Map<String, String> errorCode = {};
  final Map<String, List<String>> tasks = {};
  final List<Map<String, dynamic>> submissions = [];
  int cancelCalls = 0;

  /// Image downloads started, including those held by [imageGate].
  int imageRequests = 0;

  /// Items succeed as soon as they are looked at.
  bool autoComplete = false;

  List<String> get itemIds => [for (final ids in tasks.values) ...ids];

  /// The status of every item of the latest submission.
  void setAll(String value) {
    for (final id in tasks.values.last) {
      status[id] = value;
    }
  }

  Map<String, dynamic> _item(String taskId, int index, String id) => {
    'id': id,
    'user_id': 7,
    'username': 'tester',
    'batch_id': taskId,
    'batch_index': index,
    'batch_size': tasks[taskId]!.length,
    'status': status[id],
    'error_code': errorCode[id],
    'seed': (submissions.last['seeds'] as List)[index],
    'has_image': status[id] == 'success',
    'request_json': submissions.last['request'],
  };

  Map<String, dynamic> _task(String taskId) => {
    'id': taskId,
    'status': 'running',
    'items': [
      for (final (index, id) in tasks[taskId]!.indexed)
        _item(taskId, index, id),
    ],
  };

  ResponseBody _handle(RequestOptions options) {
    final path = options.uri.path;
    if (options.method == 'POST' && path == '/api/generation-tasks') {
      final body = options.data as Map<String, dynamic>;
      submissions.add(body);
      final taskId = 'task-${submissions.length}';
      final seeds = body['seeds'] as List;
      final ids = [for (var i = 0; i < seeds.length; i++) '$taskId-item-$i'];
      tasks[taskId] = ids;
      for (final id in ids) {
        status[id] = 'queued';
      }
      return jsonResponse({
        'task_id': taskId,
        'status': 'queued',
        'items': [
          for (final (index, id) in ids.indexed)
            {'id': id, 'batch_index': index, 'status': 'queued'},
        ],
      }, status: 202);
    }
    final cancel = RegExp(r'^/api/generation-tasks/([^/]+)/cancel$');
    final cancelMatch = cancel.firstMatch(path);
    if (options.method == 'POST' && cancelMatch != null) {
      cancelCalls++;
      final taskId = cancelMatch.group(1)!;
      for (final id in tasks[taskId]!) {
        if (status[id] == 'queued') status[id] = 'cancelled';
      }
      return jsonResponse(_task(taskId));
    }
    final task = RegExp(r'^/api/generation-tasks/([^/]+)$').firstMatch(path);
    if (task != null && tasks.containsKey(task.group(1))) {
      if (autoComplete) {
        for (final id in tasks[task.group(1)]!) {
          if (status[id] == 'queued') status[id] = 'success';
        }
      }
      return jsonResponse(_task(task.group(1)!));
    }
    if (RegExp(r'^/api/history/[^/]+/image$').hasMatch(path)) {
      return bytesResponse(image);
    }
    return jsonResponse(gatewayError('not_found'), status: 404);
  }
}

class _GatedAdapter extends FakeGatewayAdapter {
  _GatedAdapter(this.gateway, super.handler);

  final FakeGateway gateway;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/image')) {
      gateway.imageRequests++;
      await gateway.imageGate?.future;
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class GatewayRig {
  GatewayRig._(this.generation, this.gateway, this.dir);

  final RigGeneration generation;
  final FakeGateway gateway;
  final Directory dir;

  /// Files the notifier wrote to its output folder.
  List<File> get savedFiles {
    final out = Directory('${dir.path}/out');
    return out.existsSync() ? out.listSync().whereType<File>().toList() : [];
  }

  static Future<GatewayRig> create(
    Directory dir,
    Uint8List image, {
    Duration pollInterval = const Duration(milliseconds: 5),
    Duration timeout = const Duration(seconds: 30),
    Map<String, Object> preferences = const {},
  }) async {
    final gateway = FakeGateway(image);
    final client = clientOver(gateway.adapter);
    final api = BackendHistoryApi(client: client);
    final generation = RigGeneration(
      preferences: await testPreferences(initial: preferences),
      dir: dir.path,
      serviceFactory: (key) =>
          NovelAIService(key, client: client, gateway: true),
      historyApi: api,
      watcher: GatewayTaskWatcher(
        api: api,
        pollInterval: pollInterval,
        timeout: timeout,
      ),
    );
    await generation.initialized;
    generation.updateGatewayAccess(
      ImageRules.tryParse(rulesJson()),
      const GenerationAccess(canFree: true, paid: PaidImageAccess.allowed),
    );
    return GatewayRig._(generation, gateway, dir);
  }
}

/// Waits until [condition] holds (the notifier works on real timers).
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition was not reached in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
