import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/external_chat_gateway.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent_store.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';

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
  test(
    'cancel during external authorization prevents the network request',
    () async {
      final accessCheckStarted = Completer<void>();
      final allowExternalAccess = Completer<bool>();
      final externalClient = _RecordingExternalClient();
      final gateway = ExternalChatGateway(
        repository: _MemoryExternalProviderRepository(
          configs: const <ExternalProviderConfig>[_externalConfig],
        ),
        clientFor: (_) => externalClient,
        hasConsent: (_, _) async => true,
        isExternalAccessAllowed: () {
          if (!accessCheckStarted.isCompleted) {
            accessCheckStarted.complete();
          }
          return allowExternalAccess.future;
        },
      );
      final container = ProviderContainer(
        overrides: [externalChatGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      final orchestrator = container.read(aiChatOrchestratorProvider);
      final pending = orchestrator.send(
        const AiChatRequest(
          mode: ChatMode.freeChat,
          userInput: 'do not send after cancellation',
          requestId: 'preflight-cancel',
          backendPreference: ChatBackendPreference.external,
        ),
      );
      await accessCheckStarted.future;

      await orchestrator.cancel('preflight-cancel');
      allowExternalAccess.complete(true);

      await expectLater(
        pending,
        throwsA(predicate((error) => error.toString().contains('生成已停止'))),
      );
      expect(externalClient.generateCallCount, 0);
    },
  );

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
              error is ExternalChatGatewayException &&
              error.code == ExternalChatGatewayErrorCode.authorizationRequired,
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
      expect(externalClient.lastPrompt, contains('用户问题：\nhello'));
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
                error is ExternalChatGatewayException &&
                error.code ==
                    ExternalChatGatewayErrorCode.authorizationRequired,
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
      throwsA(
        predicate(
          (error) =>
              error is ExternalChatGatewayException &&
              error.code == ExternalChatGatewayErrorCode.authorizationRequired,
        ),
      ),
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
              error is ExternalChatGatewayException &&
              error.code == ExternalChatGatewayErrorCode.providerNotEnabled,
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
      throwsA(
        predicate(
          (error) =>
              error is ExternalChatGatewayException &&
              error.code ==
                  ExternalChatGatewayErrorCode.privateContextNotAllowed,
        ),
      ),
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
      expect(externalClient.lastPrompt, contains('用户问题：\npublic question'));
      expect(externalClient.lastPrompt, isNot(contains(_manualItem.summary)));
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
  return ProviderContainer(
    overrides: [
      externalProviderConsentStoreProvider.overrideWithValue(
        _MemoryExternalProviderConsentStore(),
      ),
      localLlmReadinessProvider.overrideWith(
        (ref) async => const LocalLlmReadiness(
          ready: false,
          reason: 'local unavailable',
          activeModel: null,
          runtimeState: null,
        ),
      ),
      externalProviderRepositoryProvider.overrideWithValue(
        _MemoryExternalProviderRepository(
          configs: config == null
              ? const <ExternalProviderConfig>[]
              : <ExternalProviderConfig>[config],
        ),
      ),
      externalProviderClientRouterProvider.overrideWithValue(externalClient),
      searchConfigurationProvider.overrideWith(
        (ref) async => SearchConfiguration.defaults().copyWith(
          allowExternalProviderAccess: true,
        ),
      ),
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

class _MemoryExternalProviderConsentStore
    implements ExternalProviderConsentStore {
  final Map<String, bool> _values = <String, bool>{};

  @override
  Future<bool> read(String key) async => _values[key] ?? false;

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> write(String key, bool value) async {
    _values[key] = value;
  }
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

class _MemoryExternalProviderRepository implements ExternalProviderRepository {
  _MemoryExternalProviderRepository({
    List<ExternalProviderConfig> configs = const <ExternalProviderConfig>[],
  }) : _configs = List<ExternalProviderConfig>.from(configs);

  final List<ExternalProviderConfig> _configs;

  @override
  Future<List<ExternalProviderConfig>> loadAll() async {
    return List<ExternalProviderConfig>.from(_configs);
  }

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    return _configs.where((config) => config.id == id).firstOrNull;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    return _configs.where((config) => config.enabled).firstOrNull;
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    _configs.removeWhere((item) => item.id == config.id);
    _configs.add(config);
  }
}
