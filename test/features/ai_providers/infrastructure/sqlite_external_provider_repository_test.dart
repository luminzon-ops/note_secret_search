import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/sqlite_external_provider_repository.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;
  late SqliteExternalProviderRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    security = SecurityTestFixture();
    repository = SqliteExternalProviderRepository(
      database: database,
      cryptoService: security.crypto,
    );
  });

  tearDown(() async {
    security.dispose();
    await database.close();
  });

  test('stores provider JSON as NSSF and restores the API key', () async {
    const config = ExternalProviderConfig(
      id: 'provider-1',
      providerType: ExternalProviderType.openAiCompatible,
      displayName: 'Private provider',
      baseUrl: 'https://provider.example/v1',
      apiKey: 'secret-api-key',
      modelName: 'private-model',
      embeddingModelName: 'private-embedding',
      enabled: true,
      allowSensitiveFields: false,
    );

    await repository.save(config);

    final rows = await database.run(
      (db) => db.query(
        DatabaseSchema.providerConfigs,
        where: 'id = ?',
        whereArgs: [config.id],
      ),
    );
    final encrypted = rows.single['encrypted_config']! as List<int>;
    expect(() => FieldEnvelopeCodec.decode(encrypted), returnsNormally);
    expect(
      utf8.decode(encrypted, allowMalformed: true),
      isNot(contains(config.apiKey)),
    );

    final restored = await repository.loadById(config.id);
    expect(restored, isNotNull);
    expect(restored?.apiKey, config.apiKey);
    expect(restored?.baseUrl, config.baseUrl);
    expect(restored?.modelName, config.modelName);
  });

  test('rejects legacy plaintext provider JSON', () async {
    const config = ExternalProviderConfig(
      id: 'legacy-provider',
      providerType: ExternalProviderType.ollama,
      displayName: 'Legacy provider',
      baseUrl: 'http://localhost:11434',
      apiKey: '',
      modelName: 'legacy-model',
      embeddingModelName: null,
      enabled: true,
      allowSensitiveFields: false,
    );
    await database.run(
      (db) => db.insert(DatabaseSchema.providerConfigs, {
        'id': config.id,
        'provider_type': config.providerType.name,
        'name': config.displayName,
        'encrypted_config': utf8.encode(jsonEncode(config.toJson())),
        'enabled': 1,
        'created_at': 1000,
        'updated_at': 2000,
      }),
    );

    await expectLater(
      repository.loadById(config.id),
      throwsA(
        isA<FieldCryptoException>().having(
          (error) => error.failure,
          'failure',
          FieldCryptoFailure.invalidEnvelope,
        ),
      ),
    );
  });

  test('enabling a provider disables every other provider type', () async {
    const openAi = ExternalProviderConfig(
      id: 'openai-provider',
      providerType: ExternalProviderType.openAiCompatible,
      displayName: 'OpenAI compatible',
      baseUrl: 'https://provider.example/v1',
      apiKey: 'openai-key',
      modelName: 'openai-model',
      embeddingModelName: null,
      enabled: true,
      allowSensitiveFields: false,
    );
    const ollama = ExternalProviderConfig(
      id: 'ollama-provider',
      providerType: ExternalProviderType.ollama,
      displayName: 'Ollama',
      baseUrl: 'http://localhost:11434',
      apiKey: '',
      modelName: 'ollama-model',
      embeddingModelName: null,
      enabled: true,
      allowSensitiveFields: false,
    );

    await repository.save(openAi);
    await repository.save(ollama);

    final configs = await repository.loadAll();
    expect(
      configs.where((config) => config.enabled).map((config) => config.id),
      <String>['ollama-provider'],
    );
    expect((await repository.loadEnabled())?.id, 'ollama-provider');
  });
}
