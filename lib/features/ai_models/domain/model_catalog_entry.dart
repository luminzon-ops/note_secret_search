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
  });

  factory ModelCatalogEntry.fromJson(Map<String, dynamic> json) {
    final rawSources = json['source_list'];
    final sourceList = rawSources is List
        ? rawSources
            .whereType<Map<String, dynamic>>()
            .map(ModelSourceEntry.fromJson)
            .toList(growable: false)
        : const <ModelSourceEntry>[];

    return ModelCatalogEntry(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      tier: json['tier'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      minRamMb: (json['min_ram_mb'] as num?)?.toInt() ?? 0,
      recommendedTier: json['recommended_tier'] as String? ?? '',
      tokenizer: _readTokenizer(json['tokenizer']),
      runtime: _readRuntime(json['runtime']),
      sources: sourceList,
    );
  }

  static EmbeddingTokenizerSpec? _readTokenizer(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    return EmbeddingTokenizerSpec.fromJson(raw);
  }

  static EmbeddingRuntimeSpec? _readRuntime(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    return EmbeddingRuntimeSpec.fromJson(raw);
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
  final List<ModelSourceEntry> sources;
}

class EmbeddingTokenizerSpec {
  const EmbeddingTokenizerSpec({
    required this.format,
    required this.assetPath,
    required this.maxSequenceLength,
    required this.lowercase,
  });

  factory EmbeddingTokenizerSpec.fromJson(Map<String, dynamic> json) {
    return EmbeddingTokenizerSpec(
      format: json['format'] as String? ?? '',
      assetPath: json['asset_path'] as String? ?? '',
      maxSequenceLength: (json['max_sequence_length'] as num?)?.toInt() ?? 0,
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

  factory EmbeddingRuntimeSpec.fromJson(Map<String, dynamic> json) {
    return EmbeddingRuntimeSpec(
      inputIdsName: json['input_ids_name'] as String? ?? '',
      attentionMaskName: json['attention_mask_name'] as String? ?? '',
      tokenTypeIdsName: json['token_type_ids_name'] as String?,
      outputName: json['output_name'] as String? ?? '',
      pooling: json['pooling'] as String? ?? '',
      normalization: json['normalization'] as String? ?? '',
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
      // Prefer snake_case; fall back to legacy camelCase for backward compatibility.
      signatureAlgorithm: (json['signature_algorithm'] ?? json['signatureAlgorithm']) as String?,
      keyId: (json['key_id'] ?? json['keyId']) as String?,
    );
  }

  /// Returns true when both signature and algorithm are present,
  /// indicating the source declares a cryptographic artifact trust claim.
  bool declaresArtifactTrust() {
    return signature != null && signatureAlgorithm != null;
  }

  final String id;
  final String label;
  final String url;
  final String checksum;
  final String role;
  final bool required;
  final String? signature;
  final String? signatureAlgorithm;
  final String? keyId;
}
