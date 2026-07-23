import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_providers/application/external_chat_gateway.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';

const _config = ExternalProviderConfig(
  id: 'provider-1',
  providerType: ExternalProviderType.openAiCompatible,
  displayName: 'Provider',
  baseUrl: 'https://example.test/v1',
  apiKey: 'credential-a',
  modelName: 'chat-model',
  embeddingModelName: null,
  enabled: true,
  allowSensitiveFields: true,
);

void main() {
  test(
    'gateway reloads enabled config and returns actual provider usage',
    () async {
      final repository = _MemoryRepository(_config);
      final consent = _ConsentLedger()
        ..ack(_config, ExternalProviderConsentScope.standard);
      final client = _ControllableClient()..completeImmediately('answer');
      final gateway = _gateway(repository, consent, client);

      final authorization = await gateway.authorize(
        includesPrivateContext: false,
      );
      final result = await gateway.send(
        requestId: 'request-1',
        prompt: 'hello',
        includesPrivateContext: false,
        expectedFingerprint: authorization.fingerprint,
      );

      expect(client.prompts, <String>['hello']);
      expect(result.text, 'answer');
      expect(result.usage.actualBackend, 'openAiCompatible');
      expect(result.usage.actualModel, 'chat-model');
      expect(result.usage.providerFingerprint, authorization.fingerprint);
    },
  );

  test(
    'gateway rejects disabled providers before touching the network',
    () async {
      final disabled = _config.copyWith(enabled: false);
      final repository = _MemoryRepository(disabled);
      final consent = _ConsentLedger()
        ..ack(disabled, ExternalProviderConsentScope.standard);
      final client = _ControllableClient()..completeImmediately('unexpected');
      final gateway = _gateway(repository, consent, client);

      await expectLater(
        gateway.authorize(includesPrivateContext: false),
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.providerNotEnabled,
          ),
        ),
      );
      expect(client.prompts, isEmpty);
    },
  );

  test('gateway requires the global external access opt-in', () async {
    final repository = _MemoryRepository(_config);
    final consent = _ConsentLedger()
      ..ack(_config, ExternalProviderConsentScope.standard);
    final client = _ControllableClient()..completeImmediately('unexpected');
    final gateway = _gateway(
      repository,
      consent,
      client,
      externalAccessAllowed: false,
    );

    await expectLater(
      gateway.authorize(includesPrivateContext: false),
      throwsA(
        isA<ExternalChatGatewayException>().having(
          (error) => error.code,
          'code',
          ExternalChatGatewayErrorCode.externalAccessDisabled,
        ),
      ),
    );
    expect(client.prompts, isEmpty);
  });

  test(
    'private sends require private scope and sensitive-field policy',
    () async {
      final blocked = _config.copyWith(allowSensitiveFields: false);
      final blockedConsent = _ConsentLedger()
        ..ack(blocked, ExternalProviderConsentScope.privateContext);
      final blockedGateway = _gateway(
        _MemoryRepository(blocked),
        blockedConsent,
        _ControllableClient(),
      );

      await expectLater(
        blockedGateway.authorize(includesPrivateContext: true),
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.privateContextNotAllowed,
          ),
        ),
      );

      final standardOnly = _ConsentLedger()
        ..ack(_config, ExternalProviderConsentScope.standard);
      final standardOnlyGateway = _gateway(
        _MemoryRepository(_config),
        standardOnly,
        _ControllableClient(),
      );
      await expectLater(
        standardOnlyGateway.authorize(includesPrivateContext: true),
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.authorizationRequired,
          ),
        ),
      );
    },
  );

  test(
    'identity changes reject stale authorization before network send',
    () async {
      final repository = _MemoryRepository(_config);
      final consent = _ConsentLedger()
        ..ack(_config, ExternalProviderConsentScope.standard);
      final client = _ControllableClient()..completeImmediately('unexpected');
      final gateway = _gateway(repository, consent, client);
      final authorization = await gateway.authorize(
        includesPrivateContext: false,
      );

      final rotated = _config.copyWith(apiKey: 'credential-b');
      repository.current = rotated;
      consent.ack(rotated, ExternalProviderConsentScope.standard);

      await expectLater(
        gateway.send(
          requestId: 'request-stale',
          prompt: 'hello',
          includesPrivateContext: false,
          expectedFingerprint: authorization.fingerprint,
        ),
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.providerChanged,
          ),
        ),
      );
      expect(client.prompts, isEmpty);
    },
  );

  test(
    'configuration invalidation during authorization prevents network send',
    () async {
      final repository = _MemoryRepository(_config);
      final consent = _ConsentLedger()
        ..ack(_config, ExternalProviderConsentScope.standard);
      final client = _ControllableClient()..completeImmediately('unexpected');
      final gateway = _gateway(repository, consent, client);
      final authorization = await gateway.authorize(
        includesPrivateContext: false,
      );
      repository.pauseNextEnabledLoad();

      final pending = gateway.send(
        requestId: 'request-preflight-invalidation',
        prompt: 'must never cross the network boundary',
        includesPrivateContext: false,
        expectedFingerprint: authorization.fingerprint,
      );
      await repository.enabledLoadStarted;

      gateway.invalidateConfiguration(_config.id);
      repository.resumeEnabledLoad();

      await expectLater(
        pending,
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.cancelled,
          ),
        ),
      );
      expect(client.prompts, isEmpty);
    },
  );

  test(
    'global opt-in disabled during authorization prevents network send',
    () async {
      final repository = _MemoryRepository(_config);
      final consent = _ConsentLedger()
        ..ack(_config, ExternalProviderConsentScope.standard);
      final client = _ControllableClient()..completeImmediately('unexpected');
      var externalAccessAllowed = true;
      final gateway = _gateway(
        repository,
        consent,
        client,
        accessCheck: () async => externalAccessAllowed,
      );
      final authorization = await gateway.authorize(
        includesPrivateContext: false,
      );
      repository.pauseNextEnabledLoad();

      final pending = gateway.send(
        requestId: 'request-opt-out-preflight',
        prompt: 'must not send after opt-out',
        includesPrivateContext: false,
        expectedFingerprint: authorization.fingerprint,
      );
      await repository.enabledLoadStarted;

      externalAccessAllowed = false;
      repository.resumeEnabledLoad();

      await expectLater(
        pending,
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.externalAccessDisabled,
          ),
        ),
      );
      expect(client.prompts, isEmpty);
    },
  );

  test(
    'configuration invalidation cancels and discards late responses',
    () async {
      final repository = _MemoryRepository(_config);
      final consent = _ConsentLedger()
        ..ack(_config, ExternalProviderConsentScope.standard);
      final client = _ControllableClient();
      final gateway = _gateway(repository, consent, client);
      final authorization = await gateway.authorize(
        includesPrivateContext: false,
      );

      final pending = gateway.send(
        requestId: 'request-late',
        prompt: 'sensitive prompt sentinel',
        includesPrivateContext: false,
        expectedFingerprint: authorization.fingerprint,
      );
      await client.started.future;

      gateway.invalidateConfiguration(_config.id);
      expect(client.cancelledRequestIds, <String>['request-late']);
      client.complete('late response sentinel');

      await expectLater(
        pending,
        throwsA(
          isA<ExternalChatGatewayException>().having(
            (error) => error.code,
            'code',
            ExternalChatGatewayErrorCode.cancelled,
          ),
        ),
      );
    },
  );
}

ExternalChatGateway _gateway(
  ExternalProviderRepository repository,
  _ConsentLedger consent,
  ExternalProviderClient client, {
  bool externalAccessAllowed = true,
  ExternalProviderAccessCheck? accessCheck,
}) {
  return ExternalChatGateway(
    repository: repository,
    clientFor: (_) => client,
    hasConsent: consent.hasConsent,
    isExternalAccessAllowed:
        accessCheck ?? () async => externalAccessAllowed,
  );
}

class _MemoryRepository implements ExternalProviderRepository {
  _MemoryRepository(this.current);

  ExternalProviderConfig? current;
  Completer<void>? _enabledLoadGate;
  Completer<void>? _enabledLoadStarted;

  Future<void> get enabledLoadStarted => _enabledLoadStarted!.future;

  void pauseNextEnabledLoad() {
    _enabledLoadGate = Completer<void>();
    _enabledLoadStarted = Completer<void>();
  }

  void resumeEnabledLoad() {
    final gate = _enabledLoadGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<List<ExternalProviderConfig>> loadAll() async {
    return current == null ? const [] : <ExternalProviderConfig>[current!];
  }

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    return current?.id == id ? current : null;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    final gate = _enabledLoadGate;
    if (gate != null) {
      final started = _enabledLoadStarted!;
      if (!started.isCompleted) {
        started.complete();
      }
      await gate.future;
      _enabledLoadGate = null;
      _enabledLoadStarted = null;
    }
    final config = current;
    return config != null && config.enabled ? config : null;
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    current = config;
  }
}

class _ConsentLedger {
  final Set<String> _entries = <String>{};

  void ack(ExternalProviderConfig config, ExternalProviderConsentScope scope) {
    _entries.add(externalProviderConsentFingerprint(config, scope: scope));
  }

  Future<bool> hasConsent(
    ExternalProviderConfig config,
    ExternalProviderConsentScope scope,
  ) async {
    return _entries.contains(
      externalProviderConsentFingerprint(config, scope: scope),
    );
  }
}

class _ControllableClient
    implements ExternalProviderClient, CancellableExternalProviderClient {
  final Completer<void> started = Completer<void>();
  final List<String> prompts = <String>[];
  final List<String> cancelledRequestIds = <String>[];
  final Completer<String> _result = Completer<String>();

  void completeImmediately(String text) {
    _result.complete(text);
  }

  void complete(String text) {
    if (!_result.isCompleted) {
      _result.complete(text);
    }
  }

  @override
  void cancelRequest(String requestId) {
    cancelledRequestIds.add(requestId);
  }

  @override
  Future<String> generateCancellableChatCompletion({
    required String requestId,
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    prompts.add(prompt);
    if (!started.isCompleted) {
      started.complete();
    }
    return _result.future;
  }

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    return generateCancellableChatCompletion(
      requestId: 'legacy',
      config: config,
      prompt: prompt,
      usedPrivateContext: usedPrivateContext,
    );
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}
