class ModelRegistryEntry {
  const ModelRegistryEntry({
    required this.id,
    required this.type,
    required this.provider,
    required this.name,
    required this.version,
    required this.sizeBytes,
    required this.quantization,
    required this.minRamMb,
    required this.recommendedTier,
    required this.localPath,
    required this.checksum,
    required this.enabled,
    required this.installedAt,
    required this.filePresent,
  });

  final String id;
  final String type;
  final String provider;
  final String name;
  final String? version;
  final int? sizeBytes;
  final String? quantization;
  final int? minRamMb;
  final String? recommendedTier;
  final String? localPath;
  final String? checksum;
  final bool enabled;
  final DateTime? installedAt;
  final bool filePresent;

  bool get isInstalled => enabled && filePresent && (localPath?.isNotEmpty ?? false);

  ModelRegistryEntry copyWith({
    String? id,
    String? type,
    String? provider,
    String? name,
    String? version,
    bool clearVersion = false,
    int? sizeBytes,
    bool clearSizeBytes = false,
    String? quantization,
    bool clearQuantization = false,
    int? minRamMb,
    bool clearMinRamMb = false,
    String? recommendedTier,
    bool clearRecommendedTier = false,
    String? localPath,
    bool clearLocalPath = false,
    String? checksum,
    bool clearChecksum = false,
    bool? enabled,
    DateTime? installedAt,
    bool clearInstalledAt = false,
    bool? filePresent,
  }) {
    return ModelRegistryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      provider: provider ?? this.provider,
      name: name ?? this.name,
      version: clearVersion ? null : (version ?? this.version),
      sizeBytes: clearSizeBytes ? null : (sizeBytes ?? this.sizeBytes),
      quantization: clearQuantization ? null : (quantization ?? this.quantization),
      minRamMb: clearMinRamMb ? null : (minRamMb ?? this.minRamMb),
      recommendedTier: clearRecommendedTier ? null : (recommendedTier ?? this.recommendedTier),
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      checksum: clearChecksum ? null : (checksum ?? this.checksum),
      enabled: enabled ?? this.enabled,
      installedAt: clearInstalledAt ? null : (installedAt ?? this.installedAt),
      filePresent: filePresent ?? this.filePresent,
    );
  }
}
