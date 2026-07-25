import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

class ModelRegistryIntegrityVerifier {
  const ModelRegistryIntegrityVerifier({required this.downloadService});

  final ModelDownloadService downloadService;

  Future<ModelRegistryEntry> verify(
    ModelRegistryEntry entry, {
    bool enableWhenValid = false,
  }) async {
    if (entry.artifacts.isEmpty) {
      return _verifyLegacy(entry, enableWhenValid: enableWhenValid);
    }

    final verifiedArtifacts = <ModelArtifactPath>[];
    var allRequiredPresent = true;
    var allPresentArtifactsValid = true;
    final verifiedAt = DateTime.now().millisecondsSinceEpoch;
    for (final artifact in entry.artifacts) {
      final present =
          artifact.localPath.trim().isNotEmpty &&
          await downloadService.fileExists(artifact.localPath);
      if (!present) {
        if (artifact.required) {
          allRequiredPresent = false;
        }
        verifiedArtifacts.add(
          artifact.copyWith(
            state: 'unknown',
            clearVerifiedChecksum: true,
            clearVerifiedSizeBytes: true,
            clearVerifiedAt: true,
          ),
        );
        continue;
      }

      final valid = await _verifyArtifact(artifact);
      if (!valid) {
        allPresentArtifactsValid = false;
        verifiedArtifacts.add(
          artifact.copyWith(
            state: 'corrupted',
            clearVerifiedChecksum: true,
            clearVerifiedSizeBytes: true,
            clearVerifiedAt: true,
          ),
        );
        continue;
      }
      verifiedArtifacts.add(
        artifact.copyWith(
          state: 'installed',
          verifiedChecksum: artifact.effectiveExpectedChecksum,
          verifiedSizeBytes: artifact.effectiveExpectedSizeBytes,
          verifiedAt: artifact.verifiedAt ?? verifiedAt,
        ),
      );
    }

    final integrityStatus = !allRequiredPresent
        ? ModelIntegrityStatus.unknown
        : allPresentArtifactsValid
        ? ModelIntegrityStatus.valid
        : ModelIntegrityStatus.corrupted;
    final trusted = integrityStatus == ModelIntegrityStatus.valid;
    return entry.copyWith(
      artifacts: verifiedArtifacts,
      filePresent: allRequiredPresent,
      enabled: trusted && (enableWhenValid || entry.enabled),
      integrityStatus: integrityStatus,
    );
  }

  Future<bool> _verifyArtifact(ModelArtifactPath artifact) async {
    final expectedChecksum = artifact.effectiveExpectedChecksum;
    final expectedSize = artifact.effectiveExpectedSizeBytes;
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(expectedChecksum) ||
        expectedSize <= 0) {
      return false;
    }
    try {
      if (await downloadService.fileLength(artifact.localPath) !=
          expectedSize) {
        return false;
      }
      await downloadService.verifyChecksum(
        filePath: artifact.localPath,
        expectedChecksum: expectedChecksum,
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<ModelRegistryEntry> _verifyLegacy(
    ModelRegistryEntry entry, {
    required bool enableWhenValid,
  }) async {
    final present = await downloadService.fileExists(entry.localPath);
    if (!present) {
      return entry.copyWith(
        filePresent: false,
        enabled: false,
        integrityStatus: ModelIntegrityStatus.unknown,
      );
    }
    final path = entry.localPath;
    final checksum = entry.checksum?.trim() ?? '';
    if (path == null ||
        path.trim().isEmpty ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(checksum)) {
      return entry.copyWith(
        filePresent: true,
        enabled: false,
        integrityStatus: ModelIntegrityStatus.unknown,
      );
    }
    try {
      await downloadService.verifyChecksum(
        filePath: path,
        expectedChecksum: checksum,
      );
      return entry.copyWith(
        filePresent: true,
        enabled: enableWhenValid || entry.enabled,
        integrityStatus: ModelIntegrityStatus.valid,
      );
    } on Object {
      return entry.copyWith(
        filePresent: true,
        enabled: false,
        integrityStatus: ModelIntegrityStatus.corrupted,
      );
    }
  }
}

bool modelRegistryIntegrityChanged(
  ModelRegistryEntry before,
  ModelRegistryEntry after,
) {
  if (before.enabled != after.enabled ||
      before.filePresent != after.filePresent ||
      before.integrityStatus != after.integrityStatus ||
      before.artifacts.length != after.artifacts.length) {
    return true;
  }
  for (var index = 0; index < before.artifacts.length; index++) {
    if (!_sameArtifactIntegrity(
      before.artifacts[index],
      after.artifacts[index],
    )) {
      return true;
    }
  }
  return false;
}

bool _sameArtifactIntegrity(ModelArtifactPath before, ModelArtifactPath after) {
  return before.artifactId == after.artifactId &&
      before.releaseId == after.releaseId &&
      before.role == after.role &&
      before.required == after.required &&
      before.relativePath == after.relativePath &&
      before.localPath == after.localPath &&
      before.sourceId == after.sourceId &&
      before.expectedChecksum == after.expectedChecksum &&
      before.expectedSizeBytes == after.expectedSizeBytes &&
      before.verifiedChecksum == after.verifiedChecksum &&
      before.verifiedSizeBytes == after.verifiedSizeBytes &&
      before.state == after.state &&
      before.verifiedAt == after.verifiedAt;
}
