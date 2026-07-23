import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _config = ExternalProviderConfig(
  id: 'privacy-provider',
  providerType: ExternalProviderType.openAiCompatible,
  displayName: 'Privacy fixture',
  baseUrl: 'https://example.test/v1',
  apiKey: 'API_KEY_SENTINEL',
  modelName: 'privacy-model',
  embeddingModelName: null,
  enabled: true,
  allowSensitiveFields: true,
);

void main() {
  test(
    'external orchestrator sends approved manual body but excludes password and api key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final client = _RecordingExternalClient();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => preferences),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults().copyWith(
              allowExternalProviderAccess: true,
              includePasswordField: true,
            ),
          ),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: false,
              reason: 'auto context disabled for fixture',
              activeEmbeddingModel: null,
            ),
          ),
          externalProviderRepositoryProvider.overrideWithValue(
            _MemoryProviderRepository(_config),
          ),
          externalProviderClientRouterProvider.overrideWithValue(client),
          chatContextProjectorProvider.overrideWithValue(
            RepositoryChatContextProjector(
              secretRepository: _SecretRepository(),
              noteRepository: _NoteRepository(),
              cryptoService: _FixtureCrypto(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(externalPrivacyConfirmationControllerProvider)
          .markAcknowledged(_config, includesPrivateContext: true);

      final response = await container
          .read(aiChatOrchestratorProvider)
          .send(
            const AiChatRequest(
              mode: ChatMode.freeChat,
              userInput: 'Summarize the approved fixture.',
              backendPreference: ChatBackendPreference.external,
              allowPrivateContext: true,
              manualItems: [
                ChatContextItem(
                  id: 'secret-1',
                  type: ChatContextItemType.secret,
                  title: 'Fixture secret',
                  preview: 'stale preview',
                  summary: 'stale summary',
                ),
                ChatContextItem(
                  id: 'note-1',
                  type: ChatContextItemType.note,
                  title: 'Fixture note',
                  preview: 'stale preview',
                  summary: 'stale summary',
                ),
              ],
            ),
          );

      expect(response.text, 'external answer');
      expect(client.lastPrompt, contains('MANUAL_BODY_SENTINEL'));
      expect(client.lastPrompt, contains('fixture-user'));
      expect(client.lastPrompt, isNot(contains('PASSWORD_SENTINEL')));
      expect(client.lastPrompt, isNot(contains('API_KEY_SENTINEL')));
      expect(response.usage.actualBackend, 'openAiCompatible');
      expect(response.usage.actualModel, 'privacy-model');
      expect(response.usage.providerFingerprint, isNotEmpty);
    },
  );

  test('controller persists and restores actual external provenance', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final client = _RecordingExternalClient();
    final sessions = _MemoryChatSessionRepository();
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        sharedPreferencesProvider.overrideWith((ref) async => preferences),
        searchConfigurationProvider.overrideWith(
          (ref) async => SearchConfiguration.defaults().copyWith(
            allowExternalProviderAccess: true,
          ),
        ),
        externalProviderRepositoryProvider.overrideWithValue(
          _MemoryProviderRepository(_config),
        ),
        externalProviderClientRouterProvider.overrideWithValue(client),
        chatSessionRepositoryProvider.overrideWithValue(sessions),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(externalPrivacyConfirmationControllerProvider)
        .markAcknowledged(_config, includesPrivateContext: false);

    final controller = container.read(freeChatControllerProvider.notifier);
    controller.setBackendPreference(ChatBackendPreference.external);
    await controller.send('Record actual external usage.');

    final session = sessions.sessions.single;
    final assistant = sessions.messages.singleWhere(
      (message) => message.role == ChatStoredMessageRole.assistant,
    );
    expect(session.lastModelId, 'privacy-model');
    expect(assistant.backendUsage?.actualBackend, 'openAiCompatible');
    expect(assistant.backendUsage?.actualModel, 'privacy-model');
    expect(assistant.backendUsage?.providerFingerprint, isNotEmpty);

    await controller.startNewSession();
    await controller.selectSession(session.id);

    expect(controller.state.backendPreference, ChatBackendPreference.local);
    expect(
      controller.state.messages.last.backendUsage?.actualBackend,
      'openAiCompatible',
    );
    expect(
      controller.state.messages.last.backendUsage?.actualModel,
      'privacy-model',
    );
    expect(
      controller.state.messages.last.backendUsage?.providerFingerprint,
      assistant.backendUsage?.providerFingerprint,
    );
  });
}

class _MemoryProviderRepository implements ExternalProviderRepository {
  _MemoryProviderRepository(this.current);

  final ExternalProviderConfig current;

  @override
  Future<List<ExternalProviderConfig>> loadAll() async => [current];

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    return id == current.id ? current : null;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    return current.enabled ? current : null;
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {}
}

class _MemoryChatSessionRepository implements ChatSessionRepository {
  final List<ChatSession> sessions = <ChatSession>[];
  final List<ChatStoredMessage> messages = <ChatStoredMessage>[];

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return sessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return messages
        .where((message) => message.sessionId == sessionId)
        .toList(growable: false);
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    return List<ChatSession>.from(sessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    messages.removeWhere((item) => item.id == message.id);
    messages.add(message);
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    sessions.removeWhere((item) => item.id == session.id);
    sessions.add(session);
  }
}

class _RecordingExternalClient implements ExternalProviderClient {
  String? lastPrompt;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    lastPrompt = prompt;
    return 'external answer';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _FixtureCrypto implements CryptoService {
  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
  }
}

class _SecretRepository implements SecretRepository {
  @override
  Future<SecretItem?> getById(String id) async {
    if (id != 'secret-1') {
      return null;
    }
    return SecretItem(
      id: id,
      vaultId: 'vault-1',
      title: 'Fixture secret',
      usernameCiphertext: _bytes('fixture-user'),
      passwordCiphertext: _bytes('PASSWORD_SENTINEL'),
      websiteUrlCiphertext: _bytes('https://fixture.test'),
      noteCiphertext: _bytes('secret note'),
      tags: const <String>['fixture'],
      categoryId: null,
      favorite: false,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
    );
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) async => const [];

  @override
  Future<void> save(SecretItem item) async {}

  @override
  Future<void> softDelete(String id) async {}
}

class _NoteRepository implements NoteRepository {
  @override
  Future<NoteItem?> getById(String id) async {
    if (id != 'note-1') {
      return null;
    }
    return NoteItem(
      id: id,
      vaultId: 'vault-1',
      title: 'Fixture note',
      contentCiphertext: _bytes('MANUAL_BODY_SENTINEL'),
      summaryCacheCiphertext: null,
      tags: const <String>['fixture'],
      categoryId: null,
      favorite: false,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
    );
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) async => const [];

  @override
  Future<void> save(NoteItem item) async {}

  @override
  Future<void> softDelete(String id) async {}
}

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);
