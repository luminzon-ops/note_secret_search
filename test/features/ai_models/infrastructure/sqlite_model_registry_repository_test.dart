import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'encodes and decodes registry artifact paths for sqlite persistence',
    () {
      const artifacts = <ModelArtifactPath>[
        ModelArtifactPath(
          role: 'model',
          sourceId: 'model-source',
          localPath: '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf',
          checksum: 'sha256:model',
          sizeBytes: 10,
        ),
        ModelArtifactPath(
          role: 'mmproj',
          sourceId: 'mmproj-source',
          localPath: '/models/minicpm/mmproj-model-f16.gguf',
          checksum: 'sha256:mmproj',
          sizeBytes: 20,
        ),
      ];

      final encoded = encodeModelArtifactPathsForSqlite(artifacts);
      final decoded = decodeModelArtifactPathsFromSqlite(encoded);

      expect(decoded, hasLength(2));
      expect(decoded.first.role, 'model');
      expect(
        decoded.first.localPath,
        '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf',
      );
      expect(decoded.last.role, 'mmproj');
      expect(decoded.last.localPath, '/models/minicpm/mmproj-model-f16.gguf');
    },
  );

  test('decodes missing sqlite artifact json as empty list', () {
    expect(decodeModelArtifactPathsFromSqlite(null), isEmpty);
    expect(decodeModelArtifactPathsFromSqlite(''), isEmpty);
  });

  test('updating a model registry row preserves its embeddings', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final repository = SqliteModelRegistryRepository(database: database);
    const entry = ModelRegistryEntry(
      id: 'model-1',
      type: 'embedding',
      provider: 'local',
      name: 'Original',
      version: '1',
      sizeBytes: 10,
      quantization: null,
      minRamMb: null,
      recommendedTier: null,
      localPath: '/models/model.onnx',
      checksum: null,
      enabled: true,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.valid,
    );
    await database.run(
      (executor) =>
          executor.insert(DatabaseSchema.secretItems, <String, Object?>{
            'id': 'secret-1',
            'vault_id': 'default',
            'title': 'Source',
            'favorite': 0,
            'created_at': 1,
            'updated_at': 1,
          }),
    );
    await repository.save(entry);
    await database.run(
      (executor) =>
          executor.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
            'id': 'embedding-1',
            'source_id': 'secret-1',
            'source_type': 'secret',
            'chunk_index': 0,
            'plaintext_hash': 'hash',
            'model_id': entry.id,
            'created_at': 1,
            'updated_at': 1,
          }),
    );

    await repository.save(entry.copyWith(name: 'Updated'));

    final embeddings = await database.run(
      (executor) => executor.query(DatabaseSchema.embeddingChunks),
    );
    expect(embeddings, hasLength(1));
  });
}
