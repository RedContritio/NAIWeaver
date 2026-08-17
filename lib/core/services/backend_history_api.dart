import 'package:dio/dio.dart';

import '../gateway/backend_gateway.dart';
import 'backend_auth_api.dart';

class BackendHistoryApi {
  BackendHistoryApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  final Dio _dio;

  Future<List<ServerHistoryItem>> fetchHistory({
    int limit = 50,
    int? userId,
  }) async {
    final response = await _dio.get<dynamic>(
      backendUrl('/api/history'),
      queryParameters: {'limit': limit, if (userId != null) 'user_id': userId},
    );
    final data = response.data;
    final items = data is Map<String, dynamic>
        ? data['items'] as List<dynamic>? ?? const []
        : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(ServerHistoryItem.fromJson)
        .toList();
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
  });

  factory ServerHistoryItem.fromJson(Map<String, dynamic> json) {
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
    );
  }

  String get imageUrl => backendUrl('/api/history/$id/image');

  String get thumbnailUrl => backendUrl('/api/history/$id/thumbnail');

  String get downloadFileName => 'NAIWeaver_${seed}_$id.png';
}
