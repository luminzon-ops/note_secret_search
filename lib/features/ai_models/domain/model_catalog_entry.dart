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
      sources: sourceList,
    );
  }

  final String id;
  final String type;
  final String tier;
  final String displayName;
  final String description;
  final int sizeBytes;
  final int minRamMb;
  final String recommendedTier;
  final List<ModelSourceEntry> sources;
}

class ModelSourceEntry {
  const ModelSourceEntry({
    required this.id,
    required this.label,
    required this.url,
  });

  factory ModelSourceEntry.fromJson(Map<String, dynamic> json) {
    return ModelSourceEntry(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  final String id;
  final String label;
  final String url;
}
