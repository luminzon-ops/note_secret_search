import 'package:dio/dio.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

class OpenAiCompatibleProviderClient implements ExternalProviderClient {
  OpenAiCompatibleProviderClient({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${config.baseUrl}/chat/completions',
      data: <String, Object?>{
        'model': config.modelName,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
      },
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          if (usedPrivateContext) 'X-Private-Context': 'true',
        },
      ),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('External provider returned an empty response.');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('External provider returned no completion choices.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw StateError('External provider choice payload is invalid.');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw StateError('External provider message payload is invalid.');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    throw StateError('External provider returned empty completion content.');
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {
    await _dio.get<void>(
      '${config.baseUrl}/models',
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${config.apiKey}',
        },
      ),
    );
  }
}
