import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

abstract interface class ExternalProviderClient {
  Future<void> testConnection(ExternalProviderConfig config);

  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  });
}

/// Optional extension used by the gateway to bind cancellation to a request.
///
/// Legacy clients can still implement [ExternalProviderClient]; the gateway
/// treats them as non-cancellable and discards stale results at the boundary.
abstract interface class CancellableExternalProviderClient {
  Future<String> generateCancellableChatCompletion({
    required String requestId,
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  });

  void cancelRequest(String requestId);
}
