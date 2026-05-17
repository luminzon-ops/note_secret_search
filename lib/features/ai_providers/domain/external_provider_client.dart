import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

abstract interface class ExternalProviderClient {
  Future<void> testConnection(ExternalProviderConfig config);

  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  });
}
