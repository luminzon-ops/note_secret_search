import 'package:dio/dio.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

class OllamaProviderClient
    implements ExternalProviderClient, CancellableExternalProviderClient {
  OllamaProviderClient({required Dio dio}) : _dio = dio;

  final Dio _dio;
  final Map<String, CancelToken> _activeRequests = <String, CancelToken>{};

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    return _generate(
      config: config,
      prompt: prompt,
      usedPrivateContext: usedPrivateContext,
    );
  }

  @override
  Future<String> generateCancellableChatCompletion({
    required String requestId,
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    final cancelToken = CancelToken();
    _activeRequests[requestId] = cancelToken;
    try {
      return await _generate(
        config: config,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
        cancelToken: cancelToken,
      );
    } finally {
      if (identical(_activeRequests[requestId], cancelToken)) {
        _activeRequests.remove(requestId);
      }
    }
  }

  Future<String> _generate({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${config.baseUrl}/api/chat',
      data: <String, Object?>{
        'model': config.modelName,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
        'stream': false,
        if (usedPrivateContext) 'options': <String, Object?>{'num_ctx': 4096},
      },
      options: Options(
        headers: <String, String>{'Content-Type': 'application/json'},
      ),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Ollama returned an empty response.');
    }
    final message = data['message'];
    if (message is! Map<String, dynamic>) {
      throw StateError('Ollama message payload is invalid.');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    throw StateError('Ollama returned empty completion content.');
  }

  @override
  void cancelRequest(String requestId) {
    _activeRequests[requestId]?.cancel('request_cancelled');
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {
    await _dio.get<void>('${config.baseUrl}/api/tags');
  }
}
