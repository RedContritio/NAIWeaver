import '../gateway/backend_exception.dart';
import 'backend_client.dart';

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
  BackendFeedbackApi({BackendClient? client})
    : _client = client ?? BackendClient.shared;

  final BackendClient _client;

  @override
  Future<FeedbackSubmission> submit({
    required String description,
    required Map<String, dynamic> clientContext,
    required List<Map<String, dynamic>> diagnostics,
  }) async {
    final response = await _client.post<dynamic>(
      '/api/feedback',
      data: {
        'description': description.trim(),
        'client_context': clientContext,
        'diagnostics': diagnostics,
      },
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const BackendException(
        statusCode: null,
        code: BackendErrorCode.invalidResponse,
      );
    }
    return FeedbackSubmission(
      id: data['id'] as String? ?? '',
      createdAt: data['created_at'] as String? ?? '',
    );
  }
}
