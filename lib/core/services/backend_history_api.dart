import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../gateway/backend_gateway.dart';
import 'backend_auth_api.dart';

class BackendHistoryApi {
  BackendHistoryApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  final Dio _dio;

  Future<ServerHistoryPage> fetchHistoryPage({
    int limit = 20,
    int offset = 0,
    int? userId,
    bool allUsers = false,
    bool currentBatch = false,
  }) async {
    final response = await _dio.get<dynamic>(
      backendUrl('/api/history'),
      queryParameters: {
        'limit': limit,
        'offset': offset,
        if (userId != null) 'user_id': userId,
        if (allUsers) 'all_users': true,
        if (currentBatch) 'current_batch': true,
      },
    );
    final data = response.data;
    final items = data is Map<String, dynamic>
        ? data['items'] as List<dynamic>? ?? const []
        : const [];
    return ServerHistoryPage(
      items: items
          .whereType<Map<String, dynamic>>()
          .map(ServerHistoryItem.fromJson)
          .toList(),
      total: data is Map<String, dynamic>
          ? (data['total'] as num?)?.toInt() ?? 0
          : 0,
      limit: data is Map<String, dynamic>
          ? (data['limit'] as num?)?.toInt() ?? limit
          : limit,
      offset: data is Map<String, dynamic>
          ? (data['offset'] as num?)?.toInt() ?? offset
          : offset,
    );
  }

  Future<List<ServerHistoryItem>> fetchHistory({
    int limit = 20,
    int offset = 0,
    int? userId,
    bool allUsers = false,
    bool currentBatch = false,
  }) async {
    return (await fetchHistoryPage(
      limit: limit,
      offset: offset,
      userId: userId,
      allUsers: allUsers,
      currentBatch: currentBatch,
    )).items;
  }

  Future<List<AuthUser>> fetchUsers() async {
    final response = await _dio.get<dynamic>(backendUrl('/api/admin/users'));
    final data = response.data;
    final items = data is Map<String, dynamic>
        ? data['items'] as List<dynamic>? ?? const []
        : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(AuthUser.fromJson)
        .toList();
  }

  Future<void> deleteHistoryItem(String id) async {
    await _dio.delete<dynamic>(backendUrl('/api/history/$id'));
  }

  Future<void> deleteHistoryBatch(String batchId) async {
    await _dio.delete<dynamic>(backendUrl('/api/history/batches/$batchId'));
  }

  Future<Uint8List> fetchImageBytes(String id) async {
    final response = await _dio.get<List<int>>(
      backendUrl('/api/history/$id/image'),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<ServerGenerationTask?> fetchCurrentTask() async {
    final response = await _dio.get<dynamic>(
      backendUrl('/api/current-generation-task'),
    );
    final data = response.data;
    final task = data is Map<String, dynamic> ? data['task'] : null;
    return task is Map<String, dynamic>
        ? ServerGenerationTask.fromJson(task)
        : null;
  }

  Future<ServerGenerationTask> fetchGenerationTask(String id) async {
    final response = await _dio.get<dynamic>(
      backendUrl('/api/generation-tasks/$id'),
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid generation task response');
    }
    return ServerGenerationTask.fromJson(data);
  }
}

class ServerGenerationTask {
  const ServerGenerationTask({
    required this.id,
    required this.status,
    required this.items,
  });

  final String id;
  final String status;
  final List<ServerHistoryItem> items;

  factory ServerGenerationTask.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return ServerGenerationTask(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(ServerHistoryItem.fromJson)
          .toList(),
    );
  }
}

class ServerHistoryPage {
  final List<ServerHistoryItem> items;
  final int total;
  final int limit;
  final int offset;

  const ServerHistoryPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  int get pageIndex => limit <= 0 ? 0 : offset ~/ limit;
  int get totalPages => total <= 0 ? 1 : ((total + limit - 1) ~/ limit);
  bool get hasPrevious => offset > 0;
  bool get hasNext => offset + limit < total;
}

class ServerHistoryItem {
  final String id;
  final int userId;
  final String username;
  final String mode;
  final String status;
  final String prompt;
  final String negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double scale;
  final String sampler;
  final int seed;
  final bool hasImage;
  final String createdAt;
  final String? completedAt;
  final String? batchId;
  final int? batchIndex;
  final String? errorMessage;
  final Map<String, dynamic>? request;

  const ServerHistoryItem({
    required this.id,
    required this.userId,
    required this.username,
    required this.mode,
    required this.status,
    required this.prompt,
    required this.negativePrompt,
    required this.width,
    required this.height,
    required this.steps,
    required this.scale,
    required this.sampler,
    required this.seed,
    required this.hasImage,
    required this.createdAt,
    required this.completedAt,
    this.batchId,
    this.batchIndex,
    this.errorMessage,
    this.request,
  });

  factory ServerHistoryItem.fromJson(Map<String, dynamic> json) {
    final requestJson = json['request_json'];
    Map<String, dynamic>? request;
    if (requestJson is String && requestJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(requestJson);
        if (decoded is Map<String, dynamic>) request = decoded;
      } catch (_) {}
    } else if (requestJson is Map<String, dynamic>) {
      request = requestJson;
    }
    return ServerHistoryItem(
      id: json['id'] as String? ?? '',
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      status: json['status'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: json['negative_prompt'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      steps: (json['steps'] as num?)?.toInt() ?? 0,
      scale: (json['scale'] as num?)?.toDouble() ?? 0,
      sampler: json['sampler'] as String? ?? '',
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      hasImage: json['image_path'] != null,
      createdAt: json['created_at'] as String? ?? '',
      completedAt: json['completed_at'] as String?,
      batchId: json['batch_id'] as String?,
      batchIndex: (json['batch_index'] as num?)?.toInt(),
      errorMessage: json['error_message'] as String?,
      request: request,
    );
  }

  Map<String, dynamic> get generationMetadata {
    final parameters = request?['parameters'];
    final parsedParameters = parameters is Map<String, dynamic>
        ? parameters
        : const <String, dynamic>{};
    return {
      'prompt': request?['input'] as String? ?? prompt,
      'original_prompt': request?['input'] as String? ?? prompt,
      'uc': parsedParameters['uc'] as String? ?? negativePrompt,
      'undesired_content': parsedParameters['uc'] as String? ?? negativePrompt,
      ...parsedParameters,
      if (request?['model'] != null) 'model': request!['model'],
      if (request?['action'] != null) 'action': request!['action'],
    };
  }

  String get imageUrl => backendUrl('/api/history/$id/image');

  String get thumbnailUrl => backendUrl('/api/history/$id/thumbnail');

  String get downloadFileName => 'NAIWeaver_${seed}_$id.png';
}
