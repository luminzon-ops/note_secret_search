import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_endpoint_policy.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';

typedef ExternalProviderClientResolver =
    ExternalProviderClient Function(ExternalProviderType providerType);
typedef ExternalProviderConsentCheck =
    Future<bool> Function(
      ExternalProviderConfig config,
      ExternalProviderConsentScope scope,
    );
typedef ExternalProviderAccessCheck = Future<bool> Function();

enum ExternalChatGatewayErrorCode {
  invalidArgument,
  externalAccessDisabled,
  providerNotEnabled,
  invalidConfiguration,
  authorizationRequired,
  privateContextNotAllowed,
  providerChanged,
  busy,
  cancelled,
  requestFailed,
}

class ExternalChatGatewayException implements Exception {
  const ExternalChatGatewayException(this.code, this.message);

  final ExternalChatGatewayErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class ExternalChatAuthorization {
  const ExternalChatAuthorization({
    required this.configId,
    required this.providerType,
    required this.model,
    required this.fingerprint,
    required this.includesPrivateContext,
  });

  final String configId;
  final ExternalProviderType providerType;
  final String model;
  final String fingerprint;
  final bool includesPrivateContext;
}

class ExternalChatResult {
  const ExternalChatResult({required this.text, required this.usage});

  final String text;
  final ChatBackendUsage usage;
}

class ExternalChatGateway {
  ExternalChatGateway({
    required ExternalProviderRepository repository,
    required ExternalProviderClientResolver clientFor,
    ExternalProviderEndpointPolicy endpointPolicy =
        defaultExternalProviderEndpointPolicy,
    required ExternalProviderConsentCheck hasConsent,
    required ExternalProviderAccessCheck isExternalAccessAllowed,
  }) : _repository = repository,
       _clientFor = clientFor,
       _endpointPolicy = endpointPolicy,
       _hasConsent = hasConsent,
       _isExternalAccessAllowed = isExternalAccessAllowed;

  final ExternalProviderRepository _repository;
  final ExternalProviderClientResolver _clientFor;
  final ExternalProviderEndpointPolicy _endpointPolicy;
  final ExternalProviderConsentCheck _hasConsent;
  final ExternalProviderAccessCheck _isExternalAccessAllowed;
  final Map<String, _ActiveExternalRequest> _activeRequests =
      <String, _ActiveExternalRequest>{};
  final Map<String, int> _configurationInvalidatedAt = <String, int>{};
  final Map<String, int> _fingerprintInvalidatedAt = <String, int>{};
  var _invalidationSerial = 0;
  var _allInvalidatedAt = 0;

  Future<ExternalChatAuthorization> authorize({
    required bool includesPrivateContext,
  }) async {
    if (!await _isExternalAccessAllowed()) {
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.externalAccessDisabled,
        '尚未允许外部 AI 访问。',
      );
    }
    final config = await _repository.loadEnabled();
    if (config == null || !config.enabled) {
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.providerNotEnabled,
        '尚未启用外部模型提供方。',
      );
    }
    _validateConfiguration(config);
    if (includesPrivateContext && !config.allowSensitiveFields) {
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.privateContextNotAllowed,
        '当前外部模型未允许访问私密内容。',
      );
    }

    final scope = includesPrivateContext
        ? ExternalProviderConsentScope.privateContext
        : ExternalProviderConsentScope.standard;
    final acknowledged = await _hasConsent(config, scope);
    if (!acknowledged) {
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.authorizationRequired,
        '外部模型配置尚未确认。',
      );
    }

    return ExternalChatAuthorization(
      configId: config.id,
      providerType: config.providerType,
      model: config.modelName.trim(),
      fingerprint: externalProviderConsentFingerprint(config, scope: scope),
      includesPrivateContext: includesPrivateContext,
    );
  }

  Future<ExternalChatResult> send({
    required String requestId,
    required String prompt,
    required bool includesPrivateContext,
    bool? usedPrivateContext,
    required String expectedFingerprint,
  }) async {
    if (requestId.trim().isEmpty ||
        prompt.trim().isEmpty ||
        expectedFingerprint.trim().isEmpty) {
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.invalidArgument,
        '外部模型请求参数无效。',
      );
    }
    if (_activeRequests.containsKey(requestId)) {
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.busy,
        '该外部模型请求正在处理中。',
      );
    }

    final active = _ActiveExternalRequest(
      requestId: requestId,
      fingerprint: expectedFingerprint,
      invalidationSerial: _invalidationSerial,
    );
    _activeRequests[requestId] = active;

    try {
      _throwIfCancelled(active);
      final authorization = await authorize(
        includesPrivateContext: includesPrivateContext,
      );
      active.configId = authorization.configId;
      _throwIfCancelled(active);
      if (authorization.fingerprint != expectedFingerprint) {
        throw const ExternalChatGatewayException(
          ExternalChatGatewayErrorCode.providerChanged,
          '外部模型配置已变化，请重新确认后发送。',
        );
      }

      final config = await _repository.loadById(authorization.configId);
      _throwIfCancelled(active);
      if (config == null ||
          !config.enabled ||
          externalProviderConsentFingerprint(
                config,
                scope: includesPrivateContext
                    ? ExternalProviderConsentScope.privateContext
                    : ExternalProviderConsentScope.standard,
              ) !=
              authorization.fingerprint) {
        throw const ExternalChatGatewayException(
          ExternalChatGatewayErrorCode.providerChanged,
          '外部模型配置已变化，请重新确认后发送。',
        );
      }
      if (!await _isExternalAccessAllowed()) {
        throw const ExternalChatGatewayException(
          ExternalChatGatewayErrorCode.externalAccessDisabled,
          '尚未允许外部 AI 访问。',
        );
      }
      _throwIfCancelled(active);

      active.client = _clientFor(config.providerType);
      _throwIfCancelled(active);

      final text = await _generate(
        active: active,
        config: config,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext ?? includesPrivateContext,
      );
      _throwIfCancelled(active);
      final current = await authorize(
        includesPrivateContext: includesPrivateContext,
      );
      _throwIfCancelled(active);
      if (current.fingerprint != active.fingerprint) {
        throw const ExternalChatGatewayException(
          ExternalChatGatewayErrorCode.providerChanged,
          '外部模型配置已变化，已丢弃过期响应。',
        );
      }

      return ExternalChatResult(
        text: text,
        usage: ChatBackendUsage(
          actualBackend: current.providerType.name,
          actualModel: current.model,
          providerFingerprint: current.fingerprint,
        ),
      );
    } on ExternalChatGatewayException {
      rethrow;
    } on Object {
      _throwIfCancelled(active);
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.requestFailed,
        '外部模型请求失败。',
      );
    } finally {
      if (identical(_activeRequests[requestId], active)) {
        _activeRequests.remove(requestId);
      }
    }
  }

  void cancel(String requestId) {
    final active = _activeRequests[requestId];
    if (active != null) {
      _cancel(active);
    }
  }

  void invalidateConfiguration(String configId) {
    _configurationInvalidatedAt[configId] = ++_invalidationSerial;
    for (final active in _activeRequests.values.toList(growable: false)) {
      if (active.configId == configId) {
        _cancel(active);
      }
    }
  }

  void invalidateFingerprint(String fingerprint) {
    _fingerprintInvalidatedAt[fingerprint] = ++_invalidationSerial;
    for (final active in _activeRequests.values.toList(growable: false)) {
      if (active.fingerprint == fingerprint) {
        _cancel(active);
      }
    }
  }

  void cancelAll() {
    _allInvalidatedAt = ++_invalidationSerial;
    for (final active in _activeRequests.values.toList(growable: false)) {
      _cancel(active);
    }
  }

  Future<String> _generate({
    required _ActiveExternalRequest active,
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    final client = active.client!;
    if (client is CancellableExternalProviderClient) {
      final cancellable = client as CancellableExternalProviderClient;
      return cancellable.generateCancellableChatCompletion(
        requestId: active.requestId,
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
  }

  void _cancel(_ActiveExternalRequest active) {
    if (active.cancelled) {
      return;
    }
    active.cancelled = true;
    final client = active.client;
    if (client is CancellableExternalProviderClient) {
      (client as CancellableExternalProviderClient).cancelRequest(
        active.requestId,
      );
    }
  }

  void _throwIfCancelled(_ActiveExternalRequest active) {
    if (active.cancelled ||
        !identical(_activeRequests[active.requestId], active) ||
        _wasInvalidated(active)) {
      _cancel(active);
      throw const ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.cancelled,
        '外部模型请求已取消。',
      );
    }
  }

  bool _wasInvalidated(_ActiveExternalRequest active) {
    if (_allInvalidatedAt > active.invalidationSerial ||
        (_fingerprintInvalidatedAt[active.fingerprint] ?? 0) >
            active.invalidationSerial) {
      return true;
    }
    final configId = active.configId;
    return configId != null &&
        (_configurationInvalidatedAt[configId] ?? 0) >
            active.invalidationSerial;
  }

  void _validateConfiguration(ExternalProviderConfig config) {
    final endpoint = config.baseUrl.trim();
    final endpointError = _endpointPolicy.validate(config);
    if (config.id.trim().isEmpty ||
        config.modelName.trim().isEmpty ||
        endpoint.isEmpty ||
        endpointError != null) {
      throw ExternalChatGatewayException(
        ExternalChatGatewayErrorCode.invalidConfiguration,
        endpointError ?? '外部模型配置无效。',
      );
    }
  }
}

class _ActiveExternalRequest {
  _ActiveExternalRequest({
    required this.requestId,
    required this.fingerprint,
    required this.invalidationSerial,
  });

  final String requestId;
  String? configId;
  final String fingerprint;
  final int invalidationSerial;
  ExternalProviderClient? client;
  bool cancelled = false;
}
