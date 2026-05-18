import 'package:dio/dio.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

class OllamaProviderClient implements ExternalProviderClient {
  OllamaProviderClient({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${config.baseUrl}/api/chat',
      data: <String, Object?>{
        'model': config.modelName,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
        'stream': false,
        if (usedPrivateContext)
          'options': <String, Object?>{
            'num_ctx': 4096,
          },
      },
      options: Options(
        headers: <String, String>{'Content-Type': 'application/json'},
      ),
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
  Future<void> testConnection(ExternalProviderConfig config) async {
    await _dio.get<void>('${config.baseUrl}/api/tags');
  }
}
