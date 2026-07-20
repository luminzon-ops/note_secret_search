import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/search_index_model_revision.dart';

void main() {
  test('model revision excludes local paths and display-only metadata', () {
    final first = resolveSearchIndexModelRevision(
      model: _model(localPath: '/first/model.onnx', name: 'First'),
      catalog: _catalog(),
      tokenizerAssetSha256: 'c' * 64,
    );
    final second = resolveSearchIndexModelRevision(
      model: _model(localPath: '/second/model.onnx', name: 'Renamed'),
      catalog: _catalog(),
      tokenizerAssetSha256: 'c' * 64,
    );

    expect(first, second);
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('tokenizer digest and runtime contract invalidate model revision', () {
    final baseline = resolveSearchIndexModelRevision(
      model: _model(),
      catalog: _catalog(),
      tokenizerAssetSha256: 'c' * 64,
    );
    final tokenizerChanged = resolveSearchIndexModelRevision(
      model: _model(),
      catalog: _catalog(),
      tokenizerAssetSha256: 'd' * 64,
    );
    final runtimeChanged = resolveSearchIndexModelRevision(
      model: _model(),
      catalog: _catalog(pooling: 'cls'),
      tokenizerAssetSha256: 'c' * 64,
    );

    expect(tokenizerChanged, isNot(baseline));
    expect(runtimeChanged, isNot(baseline));
  });
}

ModelRegistryEntry _model({
  String localPath = '/models/model.onnx',
  String name = 'Embedding',
}) {
  return ModelRegistryEntry(
    id: 'model-1',
    type: 'embedding',
    provider: 'builtin',
    name: name,
    version: '1',
    sizeBytes: 10,
    quantization: 'q8',
    minRamMb: 128,
    recommendedTier: 'mvp',
    localPath: localPath,
    checksum: 'a' * 64,
    enabled: true,
    installedAt: DateTime.fromMillisecondsSinceEpoch(1),
    filePresent: true,
    integrityStatus: ModelIntegrityStatus.valid,
    artifacts: <ModelArtifactPath>[
      ModelArtifactPath(
        role: 'model',
        sourceId: 'source-model',
        localPath: localPath,
        checksum: 'a' * 64,
      ),
      ModelArtifactPath(
        role: 'tokenizer',
        sourceId: 'source-tokenizer',
        localPath: '$localPath.tokenizer',
        checksum: 'b' * 64,
      ),
    ],
  );
}

ModelCatalogEntry _catalog({String pooling = 'mean'}) {
  return ModelCatalogEntry(
    id: 'model-1',
    type: 'embedding',
    tier: 'mvp',
    displayName: 'Catalog name',
    description: 'Description',
    sizeBytes: 10,
    minRamMb: 128,
    recommendedTier: 'mvp',
    tokenizer: const EmbeddingTokenizerSpec(
      format: 'wordpiece',
      assetPath: 'assets/tokenizer.json',
      maxSequenceLength: 256,
      lowercase: true,
    ),
    runtime: EmbeddingRuntimeSpec(
      inputIdsName: 'input_ids',
      attentionMaskName: 'attention_mask',
      tokenTypeIdsName: 'token_type_ids',
      outputName: 'last_hidden_state',
      pooling: pooling,
      normalization: 'l2',
    ),
    sources: const <ModelSourceEntry>[],
  );
}
