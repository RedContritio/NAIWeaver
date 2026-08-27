import 'package:dio/dio.dart';

import '../gateway/backend_gateway.dart';

class FeedbackSubmission {
  const FeedbackSubmission({required this.id, required this.createdAt});

  final String id;
  final String createdAt;
}

abstract class FeedbackApi {
  Future<FeedbackSubmission> submit({
    required String description,
    required Map<String, dynamic> clientContext,
    required List<Map<String, dynamic>> diagnostics,
  });
}

class BackendFeedbackApi implements FeedbackApi {
  BackendFeedbackApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  final Dio _dio;

  @override
  Future<FeedbackSubmission> submit({
    required String description,
    required Map<String, dynamic> clientContext,
    required List<Map<String, dynamic>> diagnostics,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        backendUrl('/api/feedback'),
        data: {
          'description': description.trim(),
          'client_context': clientContext,
          'diagnostics': diagnostics,
        },
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FeedbackApiException('Invalid server response');
      }
      return FeedbackSubmission(
        id: data['id'] as String? ?? '',
        createdAt: data['created_at'] as String? ?? '',
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      final detail = data is Map ? data['detail'] : null;
      throw FeedbackApiException(
        detail?.toString() ?? error.message ?? 'Request failed',
      );
    }
  }
}

class FeedbackApiException implements Exception {
  const FeedbackApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
