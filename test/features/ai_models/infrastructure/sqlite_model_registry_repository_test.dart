import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:path/path.dart' as p;

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

  test('registry mutations invalidate in-flight index writes', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    var invalidations = 0;
    final repository = SqliteModelRegistryRepository(
      database: database,
      beforeMutation: () => invalidations += 1,
    );
    const entry = ModelRegistryEntry(
      id: 'model-fence',
      type: 'embedding',
      provider: 'local',
      name: 'Fence model',
      version: '1',
      sizeBytes: 10,
      quantization: null,
      minRamMb: null,
      recommendedTier: null,
      localPath: '/models/fence.onnx',
      checksum: null,
      enabled: true,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.valid,
    );

    await repository.save(entry);
    await repository.deleteById(entry.id);

    expect(invalidations, 2);
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
    await database.run((executor) async {
      await executor
          .insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
            'id': 'embedding-set-1',
            'source_type': 'secret',
            'source_id': 'secret-1',
            'vault_id': 'default',
            'model_id': entry.id,
            'model_revision_hash': 'a' * 64,
            'source_updated_at': 1,
            'source_fingerprint': Uint8List(32),
            'fingerprint_key_id': 'test-key',
            'fingerprint_version': 1,
            'index_config_version': 1,
            'index_config_epoch': 1,
            'index_config_hash': 'b' * 64,
            'chunk_schema_version': 1,
            'vector_format_version': 1,
            'vector_dimension': 1,
            'chunk_count': 1,
            'created_at': 1,
          });
      await executor.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
        'id': 'embedding-chunk-1',
        'index_set_id': 'embedding-set-1',
        'source_field': 'secret.title',
        'field_chunk_index': 0,
        'chunk_fingerprint': Uint8List(32),
        'vector_blob': Uint8List(4),
        'token_count': 1,
        'created_at': 1,
      });
    });

    await repository.save(entry.copyWith(name: 'Updated'));

    final indexSets = await database.run(
      (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
    );
    expect(indexSets, hasLength(1));
    final embeddings = await database.run(
      (executor) => executor.query(DatabaseSchema.embeddingChunks),
    );
    expect(embeddings, hasLength(1));
  });

  test(
    'trusted structured installation persists only its active revision provenance',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_registry_trusted_',
      );
      addTearDown(() => support.delete(recursive: true));
      final repository = SqliteModelRegistryRepository(database: database);
      final entry = await _trustedEntry(support, generation: 2);

      await repository.save(entry);

      final saved = await repository.getById(entry.id);
      expect(saved, isNotNull);
      expect(saved!.isInstalled, isTrue);
      expect(saved.releaseId, 'release-2');
      expect(saved.catalogVersion, 7);
      expect(saved.catalogDigest, _catalogDigest);
      expect(saved.generation, 2);
      expect(saved.revisionRoot, 'revisions/2');
      expect(saved.artifacts.map((artifact) => artifact.artifactId), <String>[
        'model',
        'tokenizer',
      ]);
      expect(
        saved.artifacts,
        everyElement(
          predicate<ModelArtifactPath>((artifact) {
            return artifact.isVerified && artifact.releaseId == 'release-2';
          }),
        ),
      );
      final parent = (await database.run(
        (db) => db.query(
          DatabaseSchema.modelRegistry,
          where: 'id = ?',
          whereArgs: <Object>[entry.id],
        ),
      )).single;
      expect(parent['active_release_id'], 'release-2');
      expect(parent['catalog_version'], 7);
      expect(parent['catalog_digest'], _catalogDigest);
      expect(parent['install_generation'], 2);
      expect(parent['revision_root'], 'revisions/2');
      final artifacts = await database.run(
        (db) => db.query(
          DatabaseSchema.modelRegistryArtifacts,
          where: 'model_id = ? AND release_id = ?',
          whereArgs: <Object>[entry.id, 'release-2'],
          orderBy: 'artifact_id ASC',
        ),
      );
      expect(artifacts, hasLength(2));
      expect(
        artifacts.map((artifact) => artifact['verified_sha256']),
        everyElement(_digestA),
      );
    },
  );

  test('legacy registry save remains disabled cleanup-only metadata', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final support = await Directory.systemTemp.createTemp(
      'note_secret_search_registry_legacy_',
    );
    addTearDown(() => support.delete(recursive: true));
    final path = p.join(support.path, 'models', 'legacy', 'model.gguf');
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(<int>[1]);
    final repository = SqliteModelRegistryRepository(database: database);

    await repository.save(
      ModelRegistryEntry(
        id: 'legacy',
        type: 'llm',
        provider: 'legacy',
        name: 'Legacy',
        version: null,
        sizeBytes: 1,
        quantization: null,
        minRamMb: null,
        recommendedTier: null,
        localPath: path,
        checksum: _digestA,
        enabled: true,
        installedAt: DateTime.fromMillisecondsSinceEpoch(1),
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.valid,
      ),
    );

    final saved = await repository.getById('legacy');
    expect(saved, isNotNull);
    expect(saved!.enabled, isFalse);
    expect(saved.integrityStatus, ModelIntegrityStatus.unknown);
    expect(saved.isInstalled, isFalse);
    expect(
      await database.run(
        (db) => db.query(
          DatabaseSchema.modelRegistryArtifacts,
          where: 'model_id = ?',
          whereArgs: const <Object>['legacy'],
        ),
      ),
      isEmpty,
    );
  });

  test(
    'invalid artifact set cannot replace a trusted active revision',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_registry_atomic_',
      );
      addTearDown(() => support.delete(recursive: true));
      final repository = SqliteModelRegistryRepository(database: database);
      final installed = await _trustedEntry(support, generation: 1);
      await repository.save(installed);
      final candidate = await _trustedEntry(support, generation: 2);
      final invalid = candidate.copyWith(
        artifacts: <ModelArtifactPath>[
          ModelArtifactPath(
            artifactId: candidate.artifacts.first.artifactId,
            releaseId: candidate.releaseId!,
            role: 'model',
            sourceId: 'mirror-a',
            localPath: candidate.localPath!,
            relativePath: 'runtime/model.gguf',
            required: true,
            expectedChecksum: _digestA,
            expectedSizeBytes: 3,
            state: 'installed',
          ),
        ],
      );

      await expectLater(repository.save(invalid), throwsArgumentError);

      final saved = await repository.getById(installed.id);
      expect(saved?.generation, 1);
      expect(saved?.releaseId, 'release-1');
      expect(saved?.artifacts, hasLength(2));
    },
  );

  test(
    'late registry generation cannot overwrite the current revision',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_registry_generation_',
      );
      addTearDown(() => support.delete(recursive: true));
      final repository = SqliteModelRegistryRepository(database: database);
      final current = await _trustedEntry(support, generation: 3);
      await repository.save(current);
      final stale = await _trustedEntry(support, generation: 2);

      await repository.save(stale);

      final saved = await repository.getById(current.id);
      expect(saved?.generation, 3);
      expect(saved?.releaseId, 'release-3');
      expect(saved?.revisionRoot, 'revisions/3');
    },
  );
}

const _digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _catalogDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<ModelRegistryEntry> _trustedEntry(
  Directory support, {
  required int generation,
}) async {
  final revision = Directory(
    p.join(support.path, 'models', 'model-trusted', 'revisions', '$generation'),
  );
  await revision.create(recursive: true);
  final model = File(p.join(revision.path, 'runtime', 'model.gguf'));
  final tokenizer = File(p.join(revision.path, 'runtime', 'tokenizer.json'));
  await model.create(recursive: true);
  await tokenizer.create(recursive: true);
  await model.writeAsBytes(<int>[1, 2, 3]);
  await tokenizer.writeAsBytes(<int>[4, 5]);
  final release = 'release-$generation';
  return ModelRegistryEntry(
    id: 'model-trusted',
    type: 'llm',
    provider: 'builtin_catalog',
    name: 'Trusted',
    version: release,
    sizeBytes: 5,
    quantization: null,
    minRamMb: 2048,
    recommendedTier: 'local',
    localPath: model.path,
    checksum: _digestA,
    enabled: true,
    installedAt: DateTime.fromMillisecondsSinceEpoch(generation),
    filePresent: true,
    integrityStatus: ModelIntegrityStatus.valid,
    releaseId: release,
    catalogVersion: 7,
    catalogDigest: _catalogDigest,
    generation: generation,
    revisionRoot: 'revisions/$generation',
    artifacts: <ModelArtifactPath>[
      ModelArtifactPath(
        artifactId: 'model',
        releaseId: release,
        role: 'model',
        sourceId: 'mirror-a',
        localPath: model.path,
        relativePath: 'runtime/model.gguf',
        required: true,
        expectedChecksum: _digestA,
        expectedSizeBytes: 3,
        verifiedChecksum: _digestA,
        verifiedSizeBytes: 3,
        state: 'installed',
        verifiedAt: generation,
      ),
      ModelArtifactPath(
        artifactId: 'tokenizer',
        releaseId: release,
        role: 'tokenizer',
        sourceId: 'asset',
        localPath: tokenizer.path,
        relativePath: 'runtime/tokenizer.json',
        required: true,
        expectedChecksum: _digestA,
        expectedSizeBytes: 2,
        verifiedChecksum: _digestA,
        verifiedSizeBytes: 2,
        state: 'installed',
        verifiedAt: generation,
      ),
    ],
  );
}
