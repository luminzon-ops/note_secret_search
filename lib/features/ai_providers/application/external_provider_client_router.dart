import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

class ExternalProviderClientRouter
    implements ExternalProviderClient, CancellableExternalProviderClient {
  ExternalProviderClientRouter({
    required ExternalProviderClient openAiCompatible,
    required ExternalProviderClient ollama,
  }) : _openAiCompatible = openAiCompatible,
       _ollama = ollama;

  final ExternalProviderClient _openAiCompatible;
  final ExternalProviderClient _ollama;
  final Map<String, ExternalProviderClient> _requestClients =
      <String, ExternalProviderClient>{};

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    return _for(config).generateChatCompletion(
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
    final client = _for(config);
    _requestClients[requestId] = client;
    try {
      if (client is CancellableExternalProviderClient) {
        return (client as CancellableExternalProviderClient)
            .generateCancellableChatCompletion(
              requestId: requestId,
              config: config,
              prompt: prompt,
              usedPrivateContext: usedPrivateContext,
            );
      }
      return client.generateChatCompletion(
        config: config,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
      );
    } finally {
      if (identical(_requestClients[requestId], client)) {
        _requestClients.remove(requestId);
      }
    }
  }

  @override
  void cancelRequest(String requestId) {
    final client = _requestClients[requestId];
    if (client is CancellableExternalProviderClient) {
      (client as CancellableExternalProviderClient).cancelRequest(requestId);
    }
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) {
    return _for(config).testConnection(config);
  }

  ExternalProviderClient _for(ExternalProviderConfig config) {
    return switch (config.providerType) {
      ExternalProviderType.openAiCompatible => _openAiCompatible,
      ExternalProviderType.ollama => _ollama,
    };
  }
}
