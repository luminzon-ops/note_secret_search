class ModelCatalogFormatException implements Exception {
  const ModelCatalogFormatException(this.code);

  final String code;

  @override
  String toString() => code;
}

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

  static void _validateArtifacts(
    List<ModelArtifactSpec> artifacts, {
    required bool strict,
  }) {
    if (!strict) {
      return;
    }
    if (artifacts.isEmpty) {
      throw const ModelCatalogFormatException('artifact_list_empty');
    }
    final ids = <String>{};
    final roles = <String>{};
    final paths = <String>{};
    for (final artifact in artifacts) {
      if (!ids.add(artifact.id) ||
          !roles.add(artifact.role) ||
          !paths.add(artifact.relativePath.toLowerCase())) {
        throw const ModelCatalogFormatException('artifact_identity_duplicate');
      }
      if (artifact.id.isEmpty ||
          artifact.releaseId.isEmpty ||
          !const <String>{
            'model',
            'tokenizer',
            'mmproj',
            'sidecar',
          }.contains(artifact.role) ||
          artifact.sizeBytes <= 0 ||
          !_isSha256(artifact.checksum) ||
          !_isSafeRelativePath(artifact.relativePath) ||
          (artifact.required == false && artifact.role == 'model')) {
        throw const ModelCatalogFormatException('artifact_contract_invalid');
      }
      if (artifact.origin == ModelArtifactOrigin.download &&
          artifact.sources.isEmpty) {
        throw const ModelCatalogFormatException('artifact_sources_missing');
      }
      if (artifact.origin == ModelArtifactOrigin.bundledAsset &&
          artifact.sources.isNotEmpty) {
        throw const ModelCatalogFormatException(
          'bundled_artifact_source_invalid',
        );
      }
      final sourceIds = <String>{};
      for (final source in artifact.sources) {
        if (!sourceIds.add(source.id) ||
            source.id.isEmpty ||
            !_isHttpsUrl(source.url) ||
            source.artifactId != artifact.id ||
            source.checksum != artifact.checksum) {
          throw const ModelCatalogFormatException('artifact_source_invalid');
        }
      }
    }
    if (!roles.contains('model')) {
      throw const ModelCatalogFormatException('primary_artifact_missing');
    }
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

class ModelSourceEntry {
  const ModelSourceEntry({
    required this.id,
    required this.label,
    required this.url,
    this.checksum = '',
    this.role = 'model',
    this.required = true,
    this.signature,
    this.signatureAlgorithm,
    this.keyId,
    this.priority = 0,
    this.artifactId = '',
  });

  factory ModelSourceEntry.fromJson(Map<String, dynamic> json) {
    return ModelSourceEntry(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
      role: json['role'] as String? ?? 'model',
      required: json['required'] as bool? ?? true,
      signature: json['signature'] as String?,
      signatureAlgorithm:
          (json['signature_algorithm'] ?? json['signatureAlgorithm'])
              as String?,
      keyId: (json['key_id'] ?? json['keyId']) as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      artifactId: json['artifact_id'] as String? ?? '',
    );
  }

  factory ModelSourceEntry.fromManifestJson(
    Map<String, Object?> json, {
    required String checksum,
    required String artifactId,
    required bool required,
  }) {
    _expectKeys(json, const <String>{'source_id', 'label', 'url', 'priority'});
    return ModelSourceEntry(
      id: _string(json['source_id'], required: true) ?? '',
      label: _string(json['label'], required: true) ?? '',
      url: _string(json['url'], required: true) ?? '',
      checksum: checksum,
      required: required,
      priority: _integer(json['priority'], required: true),
      artifactId: artifactId,
    );
  }

  bool declaresArtifactTrust() {
    return signature != null && signatureAlgorithm != null;
  }

  final String id;
  final String label;
  final String url;

  /// Deprecated compatibility projection. Trust is owned by the signed artifact.
  final String checksum;
  final String role;
  final bool required;
  final String? signature;
  final String? signatureAlgorithm;
  final String? keyId;
  final int priority;
  final String artifactId;
}

void _expectKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length || !value.keys.every(expected.contains)) {
    throw const ModelCatalogFormatException('catalog_schema_invalid');
  }
}

String? _string(Object? value, {required bool required}) {
  if (value == null && !required) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw const ModelCatalogFormatException('catalog_string_invalid');
  }
  return value;
}

int _integer(Object? value, {required bool required}) {
  if (value == null && !required) {
    return 0;
  }
  if (value is! int || value < 0) {
    throw const ModelCatalogFormatException('catalog_integer_invalid');
  }
  return value;
}

bool _bool(Object? value, {required bool required}) {
  if (value == null && !required) {
    return false;
  }
  if (value is! bool) {
    throw const ModelCatalogFormatException('catalog_boolean_invalid');
  }
  return value;
}

Map<String, Object?> _objectMap(Object? value, {required bool required}) {
  if (value == null && !required) {
    return const <String, Object?>{};
  }
  if (value is! Map) {
    throw const ModelCatalogFormatException('catalog_object_invalid');
  }
  return Map<String, Object?>.fromEntries(
    value.entries.map((entry) {
      if (entry.key is! String) {
        throw const ModelCatalogFormatException('catalog_object_key_invalid');
      }
      return MapEntry(entry.key as String, entry.value);
    }),
  );
}

bool _isSafeRelativePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value) ||
      value.contains('\\') ||
      value.contains('//')) {
    return false;
  }
  final segments = value.split('/');
  return segments.every(
    (segment) =>
        segment.isNotEmpty &&
        segment != '.' &&
        segment != '..' &&
        !segment.contains(':'),
  );
}

bool _isHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty;
}

bool _isSha256(String value) =>
    RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);
