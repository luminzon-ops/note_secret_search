part of 'model_catalog_entry.dart';

class ModelArtifactSpec {
  const ModelArtifactSpec({
    required this.id,
    required this.releaseId,
    required this.role,
    required this.required,
    required this.relativePath,
    required this.sizeBytes,
    required this.checksum,
    required this.origin,
    required this.sources,
    this.supportedAbis = const <String>[],
    this.runtimeConstraints = const <String, Object?>{},
  });

  factory ModelArtifactSpec.fromJson(
    Map<String, Object?> json, {
    required bool strict,
  }) {
    if (strict) {
      _expectKeys(json, const <String>{
        'artifact_id',
        'release_id',
        'role',
        'required',
        'relative_path',
        'size_bytes',
        'sha256',
        'origin',
        'supported_abis',
        'runtime_constraints',
        'sources',
      });
    }
    final origin = _string(json['origin'], required: strict) ?? 'download';
    if (strict &&
        !const <String>{'download', 'bundled_asset'}.contains(origin)) {
      throw const ModelCatalogFormatException('artifact_origin_invalid');
    }
    final artifactId = _string(json['artifact_id'], required: strict) ?? '';
    final releaseId = _string(json['release_id'], required: strict) ?? '';
    final checksum = _string(json['sha256'], required: strict) ?? '';
    final requiredValue = _bool(json['required'], required: strict);
    final rawSources = json['sources'];
    final sources = rawSources is List
        ? rawSources
              .map((item) {
                if (item is! Map<String, Object?>) {
                  throw const ModelCatalogFormatException(
                    'artifact_source_invalid',
                  );
                }
                return ModelSourceEntry.fromManifestJson(
                  item,
                  checksum: checksum,
                  artifactId: artifactId,
                  required: requiredValue,
                );
              })
              .toList(growable: false)
        : (strict
              ? throw const ModelCatalogFormatException(
                  'artifact_sources_invalid',
                )
              : const <ModelSourceEntry>[]);
    final rawAbis = json['supported_abis'];
    final supportedAbis = rawAbis is List
        ? rawAbis
              .map((item) {
                if (item is! String || item.isEmpty) {
                  throw const ModelCatalogFormatException(
                    'artifact_abi_invalid',
                  );
                }
                return item;
              })
              .toList(growable: false)
        : (strict
              ? throw const ModelCatalogFormatException('artifact_abi_invalid')
              : const <String>[]);
    final runtimeConstraints = _objectMap(
      json['runtime_constraints'],
      required: strict,
    );
    return ModelArtifactSpec(
      id: artifactId,
      releaseId: releaseId,
      role: _string(json['role'], required: strict) ?? 'model',
      required: requiredValue,
      relativePath: _string(json['relative_path'], required: strict) ?? '',
      sizeBytes: _integer(json['size_bytes'], required: strict),
      checksum: checksum,
      origin: origin == 'bundled_asset'
          ? ModelArtifactOrigin.bundledAsset
          : ModelArtifactOrigin.download,
      sources: sources,
      supportedAbis: supportedAbis,
      runtimeConstraints: runtimeConstraints,
    );
  }

  final String id;
  final String releaseId;
  final String role;
  final bool required;
  final String relativePath;
  final int sizeBytes;
  final String checksum;
  final ModelArtifactOrigin origin;
  final List<ModelSourceEntry> sources;
  final List<String> supportedAbis;
  final Map<String, Object?> runtimeConstraints;

  bool get isBundledAsset => origin == ModelArtifactOrigin.bundledAsset;
}

enum ModelArtifactOrigin { download, bundledAsset }

class EmbeddingTokenizerSpec {
  const EmbeddingTokenizerSpec({
    required this.format,
    required this.assetPath,
    required this.maxSequenceLength,
    required this.lowercase,
  });

  factory EmbeddingTokenizerSpec.fromJson(
    Map<String, Object?> json, {
    required bool strict,
  }) {
    if (strict) {
      _expectKeys(json, const <String>{
        'format',
        'asset_path',
        'max_sequence_length',
        'lowercase',
      });
    }
    return EmbeddingTokenizerSpec(
      format: _string(json['format'], required: strict) ?? '',
      assetPath: _string(json['asset_path'], required: strict) ?? '',
      maxSequenceLength: _integer(
        json['max_sequence_length'],
        required: strict,
      ),
      lowercase: json['lowercase'] as bool? ?? false,
    );
  }

  final String format;
  final String assetPath;
  final int maxSequenceLength;
  final bool lowercase;
}

class EmbeddingRuntimeSpec {
  const EmbeddingRuntimeSpec({
    required this.inputIdsName,
    required this.attentionMaskName,
    this.tokenTypeIdsName,
    required this.outputName,
    required this.pooling,
    required this.normalization,
  });

  factory EmbeddingRuntimeSpec.fromJson(
    Map<String, Object?> json, {
    required bool strict,
  }) {
    if (strict) {
      _expectKeys(json, const <String>{
        'input_ids_name',
        'attention_mask_name',
        'token_type_ids_name',
        'output_name',
        'pooling',
        'normalization',
      });
    }
    return EmbeddingRuntimeSpec(
      inputIdsName: _string(json['input_ids_name'], required: strict) ?? '',
      attentionMaskName:
          _string(json['attention_mask_name'], required: strict) ?? '',
      tokenTypeIdsName: json['token_type_ids_name'] as String?,
      outputName: _string(json['output_name'], required: strict) ?? '',
      pooling: _string(json['pooling'], required: strict) ?? '',
      normalization: _string(json['normalization'], required: strict) ?? '',
    );
  }

  final String inputIdsName;
  final String attentionMaskName;
  final String? tokenTypeIdsName;
  final String outputName;
  final String pooling;
  final String normalization;
}
