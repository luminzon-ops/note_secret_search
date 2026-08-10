part of 'model_catalog_entry.dart';

class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.id,
    required this.type,
    required this.tier,
    required this.displayName,
    required this.description,
    required this.sizeBytes,
    required this.minRamMb,
    required this.recommendedTier,
    this.tokenizer,
    this.runtime,
    required this.sources,
    this.releaseId = 'legacy',
    this.catalogVersion = 0,
    this.catalogDigest = '',
    this.artifacts = const <ModelArtifactSpec>[],
  });

  factory ModelCatalogEntry.fromJson(Map<String, dynamic> json) {
    return _fromJson(json, strict: false);
  }

  factory ModelCatalogEntry.fromManifestJson(
    Map<String, Object?> json, {
    required int catalogVersion,
    required String catalogDigest,
  }) {
    final entry = _fromJson(
      json,
      strict: true,
      catalogVersion: catalogVersion,
      catalogDigest: catalogDigest,
    );
    return entry;
  }

  static ModelCatalogEntry _fromJson(
    Map<String, Object?> json, {
    required bool strict,
    int catalogVersion = 0,
    String catalogDigest = '',
  }) {
    if (strict) {
      _expectKeys(json, const <String>{
        'id',
        'type',
        'tier',
        'display_name',
        'description',
        'size_bytes',
        'min_ram_mb',
        'recommended_tier',
        'release_id',
        'tokenizer',
        'runtime',
        'artifacts',
      });
    }
    final id = _string(json['id'], required: strict);
    final type = _string(json['type'], required: strict);
    final tier = _string(json['tier'], required: strict);
    final displayName = _string(json['display_name'], required: strict);
    final description = _string(json['description'], required: strict);
    final sizeBytes = _integer(json['size_bytes'], required: strict);
    final minRamMb = _integer(json['min_ram_mb'], required: strict);
    final recommendedTier = _string(json['recommended_tier'], required: strict);
    if (strict &&
        !const <String>{'embedding', 'llm', 'multimodal_llm'}.contains(type)) {
      throw const ModelCatalogFormatException('model_type_invalid');
    }
    final rawArtifacts = json['artifacts'];
    final artifacts = rawArtifacts is List
        ? rawArtifacts
              .map((item) {
                if (item is! Map<String, Object?>) {
                  throw const ModelCatalogFormatException(
                    'artifact_entry_invalid',
                  );
                }
                return ModelArtifactSpec.fromJson(item, strict: strict);
              })
              .toList(growable: false)
        : const <ModelArtifactSpec>[];
    _validateArtifacts(artifacts, strict: strict);

    final legacySources = _readLegacySources(json['source_list']);
    final primaryArtifact = artifacts
        .where((artifact) => artifact.role == 'model')
        .firstOrNull;
    final sources = artifacts.isNotEmpty
        ? (primaryArtifact?.sources ?? const <ModelSourceEntry>[])
        : legacySources;
    final tokenizer = _readTokenizer(json['tokenizer'], strict: strict);
    if (strict && tokenizer != null) {
      final tokenizerArtifact = artifacts
          .where(
            (artifact) =>
                artifact.origin == ModelArtifactOrigin.bundledAsset &&
                artifact.relativePath == tokenizer.assetPath,
          )
          .firstOrNull;
      if (tokenizerArtifact == null) {
        throw const ModelCatalogFormatException('tokenizer_artifact_missing');
      }
    }
    return ModelCatalogEntry(
      id: id!,
      type: type!,
      tier: tier!,
      displayName: displayName!,
      description: description!,
      sizeBytes: sizeBytes,
      minRamMb: minRamMb,
      recommendedTier: recommendedTier!,
      tokenizer: tokenizer,
      runtime: _readRuntime(json['runtime'], strict: strict),
      sources: sources,
      releaseId: _string(json['release_id'], required: strict) ?? 'legacy',
      catalogVersion: catalogVersion,
      catalogDigest: catalogDigest,
      artifacts: artifacts,
    );
  }

  static List<ModelSourceEntry> _readLegacySources(Object? raw) {
    if (raw is! List) {
      return const <ModelSourceEntry>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => ModelSourceEntry.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  static EmbeddingTokenizerSpec? _readTokenizer(
    Object? raw, {
    required bool strict,
  }) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map<String, Object?>) {
      throw const ModelCatalogFormatException('tokenizer_invalid');
    }
    return EmbeddingTokenizerSpec.fromJson(raw, strict: strict);
  }

  static EmbeddingRuntimeSpec? _readRuntime(
    Object? raw, {
    required bool strict,
  }) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map<String, Object?>) {
      throw const ModelCatalogFormatException('runtime_invalid');
    }
    return EmbeddingRuntimeSpec.fromJson(raw, strict: strict);
  }

  final String id;
  final String type;
  final String tier;
  final String displayName;
  final String description;
  final int sizeBytes;
  final int minRamMb;
  final String recommendedTier;
  final EmbeddingTokenizerSpec? tokenizer;
  final EmbeddingRuntimeSpec? runtime;

  /// Compatibility view for existing UI/controller callers.
  final List<ModelSourceEntry> sources;

  final String releaseId;
  final int catalogVersion;
  final String catalogDigest;
  final List<ModelArtifactSpec> artifacts;

  ModelArtifactSpec? get primaryArtifact =>
      artifacts.where((artifact) => artifact.role == 'model').firstOrNull;

  ModelArtifactSpec? artifactById(String artifactId) =>
      artifacts.where((artifact) => artifact.id == artifactId).firstOrNull;
}
