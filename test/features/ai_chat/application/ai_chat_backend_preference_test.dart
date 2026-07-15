import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _externalConfig = ExternalProviderConfig(
  id: 'provider-1',
  providerType: ExternalProviderType.openAiCompatible,
  displayName: 'External Test',
  baseUrl: 'https://example.com/v1',
  apiKey: 'secret-key',
  modelName: 'gpt-4.1-mini',
  embeddingModelName: null,
  enabled: true,
  allowSensitiveFields: true,
);

const _embeddingModel = ModelRegistryEntry(
  id: 'embedding-test',
  type: 'embedding',
  provider: 'test',
  name: 'Embedding Test',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'test',
  localPath: '/models/embedding.onnx',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _manualItem = ChatContextItem(
  id: 'secret-1',
  type: ChatContextItemType.secret,
  title: 'Secret',
  preview: 'private',
  summary: 'private manual summary',
);

void main() {
  test('explicit external backend rejects an unacknowledged config', () async {
    final externalClient = _RecordingExternalClient();
    final container = await _buildContainer(
      externalClient: externalClient,
      config: _externalConfig,
    );
    addTearDown(container.dispose);

    await expectLater(
      () => container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.freeChat,
              userInput: 'hello',
              backendPreference: ChatBackendPreference.external,
            ),
          ),
      throwsA(
        predicate(
          (error) =>
              error is StateError && error.toString().contains('外部模型配置尚未确认'),
        ),
      ),
    );

    expect(externalClient.generateCallCount, 0);
  });

  test(
    'explicit external backend uses the acknowledged current config',
    () async {
      final externalClient = _RecordingExternalClient();
      final container = await _buildContainer(
        externalClient: externalClient,
        config: _externalConfig,
      );
      addTearDown(container.dispose);
      await container
          .read(externalPrivacyConfirmationControllerProvider)
          .markAcknowledged(_externalConfig, includesPrivateContext: false);

      final response = await container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.freeChat,
              userInput: 'hello',
              backendPreference: ChatBackendPreference.external,
            ),
          );

      expect(response.text, 'external answer');
      expect(externalClient.generateCallCount, 1);
      expect(externalClient.lastPrompt, 'hello');
      expect(externalClient.lastUsedPrivateContext, isFalse);
    },
  );

  test(
    'standard external consent does not authorize private context',
    () async {
      final externalClient = _RecordingExternalClient();
      final container = await _buildContainer(
        externalClient: externalClient,
        config: _externalConfig,
      );
      addTearDown(container.dispose);
      await container
          .read(externalPrivacyConfirmationControllerProvider)
          .markAcknowledged(_externalConfig, includesPrivateContext: false);

      await expectLater(
        () => container
            .read(aiChatOrchestratorProvider)
            .send(
              const AiChatRequest(
                mode: ChatMode.freeChat,
                userInput: 'private question',
                backendPreference: ChatBackendPreference.external,
                allowPrivateContext: true,
              ),
            ),
        throwsA(
          predicate(
            (error) =>
                error is StateError && error.toString().contains('外部模型配置尚未确认'),
          ),
        ),
      );

      expect(externalClient.generateCallCount, 0);
    },
  );

  test('acknowledgement does not survive an external config change', () async {
    final externalClient = _RecordingExternalClient();
    final changedConfig = _externalConfig.copyWith(modelName: 'gpt-4.1');
    final container = await _buildContainer(
      externalClient: externalClient,
      config: changedConfig,
    );
    addTearDown(container.dispose);
    await container
        .read(externalPrivacyConfirmationControllerProvider)
        .markAcknowledged(_externalConfig, includesPrivateContext: false);

    await expectLater(
      () => container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.freeChat,
              userInput: 'hello',
              backendPreference: ChatBackendPreference.external,
            ),
          ),
      throwsStateError,
    );

    expect(externalClient.generateCallCount, 0);
  });

  test('explicit external backend rejects unavailable provider', () async {
    final externalClient = _RecordingExternalClient();
    final container = await _buildContainer(
      externalClient: externalClient,
      config: null,
    );
    addTearDown(container.dispose);

    await expectLater(
      () => container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.freeChat,
              userInput: 'hello',
              backendPreference: ChatBackendPreference.external,
            ),
          ),
      throwsA(
        predicate(
          (error) =>
              error is StateError && error.toString().contains('尚未启用外部模型提供方'),
        ),
      ),
    );

    expect(externalClient.generateCallCount, 0);
  });

  test('private QA external backend requires sensitive-field policy', () async {
    final externalClient = _RecordingExternalClient();
    final blockedConfig = _externalConfig.copyWith(allowSensitiveFields: false);
    final retriever = _RecordingContextRetriever(const [_manualItem]);
    final container = await _buildContainer(
      externalClient: externalClient,
      config: blockedConfig,
      retriever: retriever,
    );
    addTearDown(container.dispose);
    await container
        .read(externalPrivacyConfirmationControllerProvider)
        .markAcknowledged(blockedConfig, includesPrivateContext: true);

    await expectLater(
      () => container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.privateQa,
              userInput: 'private question',
              backendPreference: ChatBackendPreference.external,
            ),
          ),
      throwsStateError,
    );

    expect(externalClient.generateCallCount, 0);
  });

  test(
    'free chat ignores stale manual items when private context is off',
    () async {
      final externalClient = _RecordingExternalClient();
      final retriever = _RecordingContextRetriever(const [_manualItem]);
      final container = await _buildContainer(
        externalClient: externalClient,
        config: _externalConfig,
        retriever: retriever,
      );
      addTearDown(container.dispose);
      await container
          .read(externalPrivacyConfirmationControllerProvider)
          .markAcknowledged(_externalConfig, includesPrivateContext: false);

      final response = await container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.freeChat,
              userInput: 'public question',
              backendPreference: ChatBackendPreference.external,
              manualItems: [_manualItem],
            ),
          );

      expect(retriever.callCount, 0);
      expect(externalClient.lastPrompt, 'public question');
      expect(externalClient.lastUsedPrivateContext, isFalse);
      expect(response.contextItems, isEmpty);
      expect(response.sourceType, ChatContextSource.none);
    },
  );
}

Future<ProviderContainer> _buildContainer({
  required _RecordingExternalClient externalClient,
  required ExternalProviderConfig? config,
  _RecordingContextRetriever? retriever,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => preferences),
      localLlmReadinessProvider.overrideWith(
        (ref) async => const LocalLlmReadiness(
          ready: false,
          reason: 'local unavailable',
          activeModel: null,
          runtimeState: null,
        ),
      ),
      externalProviderStatusProvider.overrideWith(
        (ref) async => ExternalProviderStatus(
          available: config != null,
          reason: config == null ? '尚未启用外部模型提供方。' : 'external ready',
          config: config,
        ),
      ),
      externalProviderClientProvider.overrideWithValue(externalClient),
      semanticSearchReadinessProvider.overrideWith(
        (ref) async => const SemanticSearchReadiness(
          ready: true,
          reason: 'semantic ready',
          activeEmbeddingModel: _embeddingModel,
        ),
      ),
      aiChatContextRetrieverProvider.overrideWithValue(
        retriever ?? _RecordingContextRetriever(),
      ),
    ],
  );
}

class _RecordingExternalClient implements ExternalProviderClient {
  var generateCallCount = 0;
  String? lastPrompt;
  bool? lastUsedPrivateContext;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    generateCallCount++;
    lastPrompt = prompt;
    lastUsedPrivateContext = usedPrivateContext;
    return 'external answer';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _RecordingContextRetriever implements AiChatContextRetriever {
  _RecordingContextRetriever([this.items = const <ChatContextItem>[]]);

  final List<ChatContextItem> items;
  var callCount = 0;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    callCount++;
    return items;
  }
}
