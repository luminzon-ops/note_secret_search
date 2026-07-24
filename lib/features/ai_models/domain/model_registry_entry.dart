import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';

enum ModelIntegrityStatus { unknown, valid, corrupted }

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
    this.integrityStatus = ModelIntegrityStatus.unknown,
    this.artifacts = const <ModelArtifactPath>[],
    this.releaseId,
    this.catalogVersion,
    this.catalogDigest,
    this.generation,
    this.revisionRoot,
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
  final ModelIntegrityStatus integrityStatus;
  final List<ModelArtifactPath> artifacts;
  final String? releaseId;
  final int? catalogVersion;
  final String? catalogDigest;
  final int? generation;
  final String? revisionRoot;

  bool get isInstalled {
    final hasPrimaryPath = localPath?.isNotEmpty ?? false;
    final trustedRevision =
        releaseId != null &&
        releaseId!.isNotEmpty &&
        (catalogVersion ?? 0) > 0 &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(catalogDigest ?? '') &&
        (generation ?? 0) > 0 &&
        _isRevisionRoot(revisionRoot);
    final requiredArtifacts = artifacts.where((artifact) => artifact.required);
    final hasRequiredArtifacts = artifacts.isEmpty
        ? false
        : requiredArtifacts.isNotEmpty &&
              requiredArtifacts.every(
                (artifact) =>
                    artifact.localPath.isNotEmpty && artifact.isVerified,
              ) &&
              (type != 'multimodal_llm' ||
                  (artifactPathForRole('model') != null &&
                      artifactPathForRole('mmproj') != null));
    return enabled &&
        filePresent &&
        integrityStatus == ModelIntegrityStatus.valid &&
        hasPrimaryPath &&
        trustedRevision &&
        hasRequiredArtifacts;
  }

  String? artifactPathForRole(String role) {
    for (final artifact in artifacts) {
      if (artifact.role == role && artifact.localPath.isNotEmpty) {
        return artifact.localPath;
      }
    }
    return null;
  }

  ModelArtifactPath? artifactById(String artifactId) {
    for (final artifact in artifacts) {
      if (artifact.artifactId == artifactId) {
        return artifact;
      }
    }
    return null;
  }

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
    ModelIntegrityStatus? integrityStatus,
    List<ModelArtifactPath>? artifacts,
    String? releaseId,
    bool clearReleaseId = false,
    int? catalogVersion,
    bool clearCatalogVersion = false,
    String? catalogDigest,
    bool clearCatalogDigest = false,
    int? generation,
    bool clearGeneration = false,
    String? revisionRoot,
    bool clearRevisionRoot = false,
  }) {
    return ModelRegistryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      provider: provider ?? this.provider,
      name: name ?? this.name,
      version: clearVersion ? null : (version ?? this.version),
      sizeBytes: clearSizeBytes ? null : (sizeBytes ?? this.sizeBytes),
      quantization: clearQuantization
          ? null
          : (quantization ?? this.quantization),
      minRamMb: clearMinRamMb ? null : (minRamMb ?? this.minRamMb),
      recommendedTier: clearRecommendedTier
          ? null
          : (recommendedTier ?? this.recommendedTier),
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      checksum: clearChecksum ? null : (checksum ?? this.checksum),
      enabled: enabled ?? this.enabled,
      installedAt: clearInstalledAt ? null : (installedAt ?? this.installedAt),
      filePresent: filePresent ?? this.filePresent,
      integrityStatus: integrityStatus ?? this.integrityStatus,
      artifacts: artifacts ?? this.artifacts,
      releaseId: clearReleaseId ? null : (releaseId ?? this.releaseId),
      catalogVersion: clearCatalogVersion
          ? null
          : (catalogVersion ?? this.catalogVersion),
      catalogDigest: clearCatalogDigest
          ? null
          : (catalogDigest ?? this.catalogDigest),
      generation: clearGeneration ? null : (generation ?? this.generation),
      revisionRoot: clearRevisionRoot
          ? null
          : (revisionRoot ?? this.revisionRoot),
    );
  }
}

bool _isRevisionRoot(String? value) {
  if (value == null ||
      value.isEmpty ||
      !value.startsWith('revisions/') ||
      value.endsWith('/') ||
      value.contains(r'\') ||
      value.contains(':') ||
      value.contains('//')) {
    return false;
  }
  return value
      .split('/')
      .every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}
