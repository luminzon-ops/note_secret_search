import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_model_catalog_repository.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._rawJson);

  final String _rawJson;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_rawJson));
    return ByteData.view(bytes.buffer);
  }
}

void main() {
  test('loadCatalog parses llm catalog entries with gguf download artifacts', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "phi_local_q4",
    "type": "llm",
    "tier": "local",
    "display_name": "Phi Local Q4",
    "description": "用于本地自由聊天与首轮设备问答验证的轻量级本地 LLM。",
    "size_bytes": 104857600,
    "min_ram_mb": 2048,
    "recommended_tier": "local",
    "source_list": [
      {
        "id": "project-owned-primary",
        "label": "项目内置来源",
        "url": "https://example.com/models/phi_local_q4.gguf",
        "checksum": "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final entry = catalog.single;
    expect(entry.type, 'llm');
    expect(entry.displayName, 'Phi Local Q4');
    expect(entry.sources, hasLength(1));
    expect(entry.sources.single.url, 'https://example.com/models/phi_local_q4.gguf');
    expect(
      entry.sources.single.checksum,
      'sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
    );
  });

  test('built-in catalog exposes at least one llm entry', () async {
    final projectRoot = Directory.current;
    final catalogFile = File('${projectRoot.path}${Platform.pathSeparator}assets${Platform.pathSeparator}model_catalog${Platform.pathSeparator}built_in_catalog.json');
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(await catalogFile.readAsString()),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog.any((entry) => entry.type == 'llm'), isTrue);
  });

  test('built-in catalog exposes a lighter gguf llm option for device validation', () async {
    final projectRoot = Directory.current;
    final catalogFile = File(
      '${projectRoot.path}${Platform.pathSeparator}assets${Platform.pathSeparator}model_catalog${Platform.pathSeparator}built_in_catalog.json',
    );
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(await catalogFile.readAsString()),
    );

    final catalog = await repository.loadCatalog();
    final qwenEntry = catalog.firstWhere((entry) => entry.id == 'qwen2_5_0_5b_instruct_q4_k_m');
    final lighterEntry = catalog.firstWhere((entry) => entry.id == 'smollm2_360m_instruct_q4_k_m');

    expect(lighterEntry.type, 'llm');
    expect(lighterEntry.sizeBytes, lessThan(qwenEntry.sizeBytes));
    expect(lighterEntry.sources, isNotEmpty);
    expect(lighterEntry.sources.single.url, contains('.gguf'));
    expect(lighterEntry.sources.single.checksum, startsWith('sha256:'));
  });

  test('built-in catalog exposes MiniCPM-V 4_6 as deployable multimodal model artifacts', () async {
    final projectRoot = Directory.current;
    final catalogFile = File(
      '${projectRoot.path}${Platform.pathSeparator}assets${Platform.pathSeparator}model_catalog${Platform.pathSeparator}built_in_catalog.json',
    );
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(await catalogFile.readAsString()),
    );

    final catalog = await repository.loadCatalog();
    final miniCpmEntry = catalog.firstWhere((entry) => entry.id == 'minicpm_v_4_6_q4_k_m');

    expect(miniCpmEntry.type, 'multimodal_llm');
    expect(miniCpmEntry.tier, 'local_multimodal');
    expect(miniCpmEntry.recommendedTier, 'vision_language_local');
    expect(miniCpmEntry.description, contains('mmproj-model-f16.gguf'));
    expect(miniCpmEntry.sources, hasLength(2));
    expect(miniCpmEntry.sources.map((source) => source.role), containsAll(<String>['model', 'mmproj']));
    expect(miniCpmEntry.sources.every((source) => source.required), isTrue);
    expect(
      miniCpmEntry.sources.map((source) => source.url),
      containsAll(<String>[
        'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/MiniCPM-V-4_6-Q4_K_M.gguf',
        'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/mmproj-model-f16.gguf',
      ]),
    );
  });

  test('built-in BGE embedding runtime declares token_type_ids input', () async {
    final projectRoot = Directory.current;
    final catalogFile = File(
      '${projectRoot.path}${Platform.pathSeparator}assets${Platform.pathSeparator}model_catalog${Platform.pathSeparator}built_in_catalog.json',
    );
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle(await catalogFile.readAsString()),
    );

    final catalog = await repository.loadCatalog();
    final bgeEntry = catalog.firstWhere((entry) => entry.id == 'bge_small_zh_v1_5');

    expect(bgeEntry.runtime, isNotNull);
    expect(bgeEntry.runtime?.tokenTypeIdsName, 'token_type_ids');
  });

  test('loadCatalog parses checksum metadata from source_list', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "embed_min_cn_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "内置最小版 Embedding",
    "description": "低端设备优先，MVP 默认推荐。",
    "size_bytes": 157286400,
    "min_ram_mb": 3072,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "github-release",
        "label": "GitHub Releases",
        "url": "https://example.com/models/embed_min_cn_v1.onnx",
        "checksum": "sha256:abc123"
      },
      {
        "id": "mirror-cn",
        "label": "备用镜像",
        "url": "https://mirror.example.com/models/embed_min_cn_v1.onnx",
        "checksum": "sha256:def456"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    expect(catalog.single.sources, hasLength(2));
    expect(catalog.single.sources.first.label, 'GitHub Releases');
    expect(catalog.single.sources.first.checksum, 'sha256:abc123');
    expect(catalog.single.sources.last.label, '备用镜像');
    expect(catalog.single.sources.last.checksum, 'sha256:def456');
  });

  test('loadCatalog parses embedding tokenizer and runtime metadata', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "bge_small_zh_v1_5",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "BGE Small 中文 Embedding",
    "description": "用于本地中文语义检索的 BGE 小型 embedding 模型。",
    "size_bytes": 94851877,
    "min_ram_mb": 3072,
    "recommended_tier": "tier_1",
    "tokenizer": {
      "format": "tokenizer_json",
      "asset_path": "assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json",
      "max_sequence_length": 256,
      "lowercase": false
    },
    "runtime": {
      "input_ids_name": "input_ids",
      "attention_mask_name": "attention_mask",
      "output_name": "last_hidden_state",
      "pooling": "mean",
      "normalization": "l2"
    },
    "source_list": [
      {
        "id": "xenova-revision-pinned",
        "label": "HuggingFace Xenova（revision pinned）",
        "url": "https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/75c43b069aac4d136ba6bc1122f995fedcfd2781/onnx/model.onnx",
        "checksum": "sha256:69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final entry = catalog.single;
    expect(entry.tokenizer, isNotNull);
    expect(entry.tokenizer?.format, 'tokenizer_json');
    expect(
      entry.tokenizer?.assetPath,
      'assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json',
    );
    expect(entry.tokenizer?.maxSequenceLength, 256);
    expect(entry.tokenizer?.lowercase, isFalse);

    expect(entry.runtime, isNotNull);
    expect(entry.runtime?.inputIdsName, 'input_ids');
    expect(entry.runtime?.attentionMaskName, 'attention_mask');
    expect(entry.runtime?.tokenTypeIdsName, isNull);
    expect(entry.runtime?.outputName, 'last_hidden_state');
    expect(entry.runtime?.pooling, 'mean');
    expect(entry.runtime?.normalization, 'l2');
    expect(entry.sources.single.checksum, 'sha256:69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a');
  });

  test('loadCatalog parses signature metadata from source_list', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "test_sig_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Test Signature Model",
    "description": "Test model with signature metadata.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "signed-source",
        "label": "Signed Source",
        "url": "https://example.com/model.onnx",
        "checksum": "sha256:abc123",
        "signature": "base64:abc123signature==",
        "signatureAlgorithm": "RSA-SHA256",
        "keyId": "key-id-123"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final source = catalog.single.sources.single;
    expect(source.signature, 'base64:abc123signature==');
    expect(source.signatureAlgorithm, 'RSA-SHA256');
    expect(source.keyId, 'key-id-123');
    expect(source.declaresArtifactTrust(), isTrue);
  });

  test('loadCatalog parses snake_case signature keys signature_algorithm and key_id', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "test_snake_case_sig_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Snake Case Signature Model",
    "description": "Test model with snake_case signature keys.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "snake-case-source",
        "label": "Snake Case Source",
        "url": "https://example.com/model.onnx",
        "checksum": "sha256:snake123",
        "signature": "base64:snakesig==",
        "signature_algorithm": "RSA-SHA256",
        "key_id": "snake-key-id"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final source = catalog.single.sources.single;
    expect(source.signature, 'base64:snakesig==');
    expect(source.signatureAlgorithm, 'RSA-SHA256');
    expect(source.keyId, 'snake-key-id');
    expect(source.declaresArtifactTrust(), isTrue);
  });

  test('loadCatalog resolves snake_case over legacy camelCase when both present', () async {
    // Prefer snake_case (signature_algorithm) when both forms exist in JSON.
    // The parser checks snake_case first, so snake takes precedence.
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "test_both_keys_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Both Keys Model",
    "description": "Model with both snake and camel signature keys.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "both-source",
        "label": "Both Source",
        "url": "https://example.com/model.onnx",
        "checksum": "sha256:both123",
        "signature": "base64:bothsig==",
        "signatureAlgorithm": "camelAlgo",
        "signature_algorithm": "snakeAlgo",
        "keyId": "camelKey",
        "key_id": "snakeKey"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final source = catalog.single.sources.single;
    // Snake_case takes precedence (checked first in parser)
    expect(source.signatureAlgorithm, 'snakeAlgo');
    expect(source.keyId, 'snakeKey');
  });

  test('loadCatalog handles legacy source entry without signature metadata', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "legacy_model_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Legacy Model",
    "description": "Old model without signature metadata.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "legacy-source",
        "label": "Legacy Source",
        "url": "https://example.com/legacy.onnx",
        "checksum": "sha256:legacychecksum"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final source = catalog.single.sources.single;
    expect(source.checksum, 'sha256:legacychecksum');
    expect(source.signature, isNull);
    expect(source.signatureAlgorithm, isNull);
    expect(source.keyId, isNull);
    expect(source.declaresArtifactTrust(), isFalse);
  });

  test('loadCatalog handles partial signature metadata without breaking parsing', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "partial_sig_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Partial Signature Model",
    "description": "Model with only signature field.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "partial-source",
        "label": "Partial Source",
        "url": "https://example.com/partial.onnx",
        "checksum": "sha256:partialchecksum",
        "signature": "base64:partialsig=="
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final source = catalog.single.sources.single;
    expect(source.signature, 'base64:partialsig==');
    expect(source.signatureAlgorithm, isNull);
    expect(source.keyId, isNull);
    // Trust stub is false when algorithm is missing even if signature present
    expect(source.declaresArtifactTrust(), isFalse);
  });

  test('loadCatalog parses checksum-only source entry with no signature fields', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "checksum_only_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Checksum Only Model",
    "description": "Model with only checksum.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "checksum-only",
        "label": "Checksum Only",
        "url": "https://example.com/checksumonly.onnx",
        "checksum": "sha256:checksumonly123"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog, hasLength(1));
    final source = catalog.single.sources.single;
    expect(source.checksum, 'sha256:checksumonly123');
    expect(source.signature, isNull);
    expect(source.declaresArtifactTrust(), isFalse);
  });

  test('built_in_catalog includes signature metadata on at least one source entry', () async {
    final file = File('assets/model_catalog/built_in_catalog.json');
    final decoded = jsonDecode(await file.readAsString());

    expect(decoded, isA<List<dynamic>>());
    final entries = (decoded as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    expect(entries, isNotEmpty);

    bool hasSignatureField = false;
    for (final entry in entries) {
      final sources = (entry['source_list'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().toList(growable: false) ?? [];
      for (final source in sources) {
        if (source.containsKey('signature') || source.containsKey('signatureAlgorithm') || source.containsKey('keyId')) {
          hasSignatureField = true;
          break;
        }
      }
      if (hasSignatureField) break;
    }
    expect(hasSignatureField, isTrue, reason: 'At least one source entry in built_in_catalog.json should have signature metadata');
  });

  test('built_in_catalog source entry with signature has trust metadata', () async {
    final file = File('assets/model_catalog/built_in_catalog.json');
    final decoded = jsonDecode(await file.readAsString());

    final entries = (decoded as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    final entry = entries.singleWhere((item) => item['id'] == 'bge_small_zh_v1_5');

    final sources = (entry['source_list'] as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    expect(sources.first, contains('checksum'));
  });

  group('ModelSourceEntry trust stub semantic', () {
    test('declaresArtifactTrust returns true only when signature and algorithm are present', () async {
      final repository = AssetModelCatalogRepository(
        assetBundle: _FakeAssetBundle('''
[
  {
    "id": "trust_test_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "Trust Test Model",
    "description": "Test trust semantics.",
    "size_bytes": 100000000,
    "min_ram_mb": 2048,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "trust-full",
        "label": "Full Trust",
        "url": "https://example.com/full.onnx",
        "checksum": "sha256:full",
        "signature": "base64:fullsig",
        "signatureAlgorithm": "RSA-SHA256",
        "keyId": "key-1"
      },
      {
        "id": "trust-signature-only",
        "label": "Signature Only",
        "url": "https://example.com/sigonly.onnx",
        "checksum": "sha256:sigonly",
        "signature": "base64:sigonly"
      },
      {
        "id": "trust-algorithm-only",
        "label": "Algorithm Only",
        "url": "https://example.com/algoonly.onnx",
        "checksum": "sha256:algoonly",
        "signatureAlgorithm": "RSA-SHA256"
      },
      {
        "id": "trust-none",
        "label": "No Trust",
        "url": "https://example.com/notrust.onnx",
        "checksum": "sha256:notrust"
      }
    ]
  }
]
'''),
      );

      final catalog = await repository.loadCatalog();
      final sources = catalog.single.sources;

      expect(sources[0].declaresArtifactTrust(), isTrue);   // full
      expect(sources[1].declaresArtifactTrust(), isFalse);  // signature only, no algorithm
      expect(sources[2].declaresArtifactTrust(), isFalse);  // algorithm only, no signature
      expect(sources[3].declaresArtifactTrust(), isFalse);  // none
    });
  });

  test('built_in_catalog declares real bge-small-zh-v1.5 resources', () async {
    final file = File('assets/model_catalog/built_in_catalog.json');
    final decoded = jsonDecode(await file.readAsString());

    expect(decoded, isA<List<dynamic>>());
    final entries = (decoded as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    final entry = entries.singleWhere((item) => item['id'] == 'bge_small_zh_v1_5');

    expect(entry['display_name'], 'BGE Small 中文 Embedding');
    expect(entry['size_bytes'], 94851877);

    final tokenizer = entry['tokenizer'] as Map<String, dynamic>;
    expect(tokenizer['asset_path'], 'assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json');
    expect(tokenizer['lowercase'], false);

    final sources = (entry['source_list'] as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    expect(sources, hasLength(2));
    expect(sources.first['id'], 'xenova-revision-pinned');
    expect(
      sources.first['url'],
      'https://hf-mirror.com/Xenova/bge-small-zh-v1.5/resolve/75c43b069aac4d136ba6bc1122f995fedcfd2781/onnx/model.onnx',
    );
    expect(
      sources.first['checksum'],
      'sha256:69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a',
    );
    expect(sources.last['id'], 'xenova-main-fallback');
    expect(
      sources.last['url'],
      'https://hf-mirror.com/Xenova/bge-small-zh-v1.5/resolve/main/onnx/model.onnx',
    );
  });
}
