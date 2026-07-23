import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_catalog_trust.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._rawJson);

  final String _rawJson;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_rawJson));
    return ByteData.view(bytes.buffer);
  }
}

class _MemoryAcceptanceStore implements ModelCatalogAcceptanceStore {
  _MemoryAcceptanceStore([this.state]);

  ModelCatalogAcceptanceState? state;

  @override
  Future<ModelCatalogAcceptanceState?> read() async => state;

  @override
  Future<void> accept(ModelCatalogAcceptanceState next) async {
    state = next;
  }
}

void main() {
  test('built-in catalog is signed and exposes structured artifacts', () async {
    final raw = await File(
      'assets/model_catalog/built_in_catalog.json',
    ).readAsString();
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(raw),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(3));
    final bge = catalog.singleWhere((entry) => entry.id == 'bge_small_zh_v1_5');
    expect(bge.catalogVersion, 1);
    expect(bge.catalogDigest, hasLength(64));
    expect(bge.releaseId, 'bge-small-zh-v1.5-75c43b069aac');
    expect(bge.artifacts, hasLength(2));
    expect(bge.artifacts.where((artifact) => artifact.required), hasLength(2));
    final tokenizer = bge.artifacts.singleWhere(
      (artifact) => artifact.role == 'tokenizer',
    );
    expect(tokenizer.isBundledAsset, isTrue);
    expect(
      tokenizer.checksum,
      'sha256:fdfe8732afc3b2cf9b97f4efb142e56ba20eaf2962f15eb0eb2feefe692dfd87',
    );
    expect(
      bge.sources.every(
        (source) => source.checksum == bge.primaryArtifact?.checksum,
      ),
      isTrue,
    );
  });

  test(
    'repository verifies a signed fixture before hiding multimodal models',
    () async {
      final repository = AssetModelCatalogRepository(
        assetBundle: _FakeAssetBundle(_signedFixture),
      );

      final catalog = await repository.loadCatalog();

      expect(catalog.map((entry) => entry.id), <String>['embed-fixture']);
    },
  );

  test('repository rejects unsigned arrays and tampered signatures', () async {
    final unsigned = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('[]'),
    );
    expect(
      unsigned.loadCatalog,
      throwsA(
        isA<ModelCatalogTrustException>().having(
          (error) => error.code,
          'code',
          'catalog_root_invalid',
        ),
      ),
    );

    final tampered = _signedFixture.replaceFirst(
      '6qRF_dolqCZHz9vejbtqe-KolYh0jY1_',
      '7qRF_dolqCZHz9vejbtqe-KolYh0jY1_',
    );
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(tampered),
    );
    expect(repository.loadCatalog, throwsA(isA<ModelCatalogTrustException>()));
  });

  test(
    'acceptance state rejects version rollback and same-version digest change',
    () async {
      final verifier = ModelCatalogVerifier();
      final verified = verifier.verify(_signedFixture);
      final rollbackStore = _MemoryAcceptanceStore(
        ModelCatalogAcceptanceState(
          catalogVersion: verified.catalogVersion + 1,
          payloadDigest: verified.payloadDigest,
          keyId: verified.keyId,
        ),
      );
      final rollbackRepository = AssetModelCatalogRepository(
        assetBundle: _FakeAssetBundle(_signedFixture),
        acceptanceStore: rollbackStore,
      );
      expect(
        rollbackRepository.loadCatalog,
        throwsA(
          isA<ModelCatalogTrustException>().having(
            (error) => error.code,
            'code',
            'catalog_version_rollback',
          ),
        ),
      );

      final conflictStore = _MemoryAcceptanceStore(
        ModelCatalogAcceptanceState(
          catalogVersion: verified.catalogVersion,
          payloadDigest: '0' * 64,
          keyId: verified.keyId,
        ),
      );
      final conflictRepository = AssetModelCatalogRepository(
        assetBundle: _FakeAssetBundle(_signedFixture),
        acceptanceStore: conflictStore,
      );
      expect(
        conflictRepository.loadCatalog,
        throwsA(
          isA<ModelCatalogTrustException>().having(
            (error) => error.code,
            'code',
            'catalog_version_digest_conflict',
          ),
        ),
      );
    },
  );

  test('acceptance store records only a fully parsed catalog', () async {
    final store = _MemoryAcceptanceStore();
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(_signedFixture),
      acceptanceStore: store,
    );

    await repository.loadCatalog();

    expect(store.state, isNotNull);
    expect(store.state?.catalogVersion, 9);
    expect(store.state?.keyId, 'phase7-v1');
    expect(store.state?.payloadDigest, hasLength(64));
  });
}

const _signedFixture = r'''
{
  "schema_version": 1,
  "catalog_version": 9,
  "key_id": "phase7-v1",
  "signature_algorithm": "Ed25519",
  "payload": {
    "models": [
      {
        "id": "embed-fixture",
        "type": "embedding",
        "tier": "minimum",
        "display_name": "Fixture",
        "description": "Fixture",
        "size_bytes": 4,
        "min_ram_mb": 1,
        "recommended_tier": "tier_1",
        "release_id": "fixture-r1",
        "tokenizer": null,
        "runtime": null,
        "artifacts": [
          {
            "artifact_id": "fixture-model",
            "release_id": "fixture-r1",
            "role": "model",
            "required": true,
            "relative_path": "model.bin",
            "size_bytes": 4,
            "sha256": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "origin": "download",
            "supported_abis": [],
            "runtime_constraints": {},
            "sources": [
              {
                "source_id": "fixture-source",
                "label": "Fixture",
                "url": "https://example.com/model.bin",
                "priority": 0
              }
            ]
          }
        ]
      },
      {
        "id": "minicpm-fixture",
        "type": "multimodal_llm",
        "tier": "local_multimodal",
        "display_name": "Hidden",
        "description": "Hidden",
        "size_bytes": 4,
        "min_ram_mb": 1,
        "recommended_tier": "local",
        "release_id": "fixture-mm-r1",
        "tokenizer": null,
        "runtime": null,
        "artifacts": [
          {
            "artifact_id": "mm-model",
            "release_id": "fixture-mm-r1",
            "role": "model",
            "required": true,
            "relative_path": "mm.bin",
            "size_bytes": 4,
            "sha256": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "origin": "download",
            "supported_abis": ["arm64-v8a"],
            "runtime_constraints": {},
            "sources": [
              {
                "source_id": "mm-source",
                "label": "Fixture",
                "url": "https://example.com/mm.bin",
                "priority": 0
              }
            ]
          }
        ]
      }
    ]
  },
  "signature": "6qRF_dolqCZHz9vejbtqe-KolYh0jY1_kmJodHX3cIaBv4cLnTRSedu6yRQnjTCB7jhSnifR0szV4RbYOfeyAg=="
}
''';
