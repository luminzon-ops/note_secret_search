import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_endpoint_policy.dart';

void main() {
  const httpsConfig = ExternalProviderConfig(
    id: 'provider-1',
    providerType: ExternalProviderType.openAiCompatible,
    displayName: 'Provider',
    baseUrl: 'https://example.com/v1/',
    apiKey: 'key',
    modelName: 'model',
    embeddingModelName: null,
    enabled: true,
    allowSensitiveFields: false,
  );

  test('release accepts HTTPS endpoints only', () {
    const policy = ExternalProviderEndpointPolicy.release();
    expect(policy.validate(httpsConfig), isNull);
    expect(
      policy.validate(httpsConfig.copyWith(baseUrl: 'http://example.com/v1')),
      'Release builds require HTTPS external provider endpoints.',
    );
    expect(
      policy.validate(httpsConfig.copyWith(baseUrl: 'http://localhost:11434')),
      'Release builds require HTTPS external provider endpoints.',
    );
  });

  test('debug allows only loopback HTTP endpoints', () {
    const policy = ExternalProviderEndpointPolicy.debug();
    expect(policy.validate(httpsConfig), isNull);
    expect(
      policy.validate(httpsConfig.copyWith(baseUrl: 'http://127.0.0.1:11434')),
      isNull,
    );
    expect(
      policy.validate(
        httpsConfig.copyWith(baseUrl: 'http://192.168.1.10:11434'),
      ),
      'Debug HTTP endpoints must use loopback hosts.',
    );
  });

  test('policy rejects missing host and unsupported schemes', () {
    const policy = ExternalProviderEndpointPolicy.release();
    expect(
      policy.validate(httpsConfig.copyWith(baseUrl: 'example.com/v1')),
      'External provider endpoint must include a scheme and host.',
    );
    expect(
      policy.validate(httpsConfig.copyWith(baseUrl: 'ftp://example.com/v1')),
      'External provider endpoint must use HTTPS.',
    );
  });
}
