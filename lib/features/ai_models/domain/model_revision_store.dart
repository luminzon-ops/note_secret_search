class ModelRevisionStoreException implements Exception {
  const ModelRevisionStoreException(this.code);

  final String code;

  @override
  String toString() => code;
}

class StagedModelArtifact {
  const StagedModelArtifact({
    required this.artifactId,
    required this.relativePath,
    required this.stagingPath,
    required this.expectedSizeBytes,
    required this.expectedChecksum,
  });

  final String artifactId;
  final String relativePath;
  final String stagingPath;
  final int expectedSizeBytes;
  final String expectedChecksum;
}

class InstalledModelRevision {
  const InstalledModelRevision({
    required this.revisionRoot,
    required this.pathsByArtifactId,
  });

  final String revisionRoot;
  final Map<String, String> pathsByArtifactId;
}

abstract interface class ModelRevisionStore {
  Future<StagedModelArtifact> stageExistingArtifact({
    required String modelId,
    required String operationId,
    required String artifactId,
    required String relativePath,
    required String sourcePath,
    required int expectedSizeBytes,
    required String expectedChecksum,
  });

  Future<InstalledModelRevision> installVerifiedRevision({
    required String modelId,
    required String operationId,
    required int generation,
    required List<StagedModelArtifact> artifacts,
  });

  Future<void> recoverInterruptedInstalls({required String modelId});

  Future<void> discardInstalledRevision({
    required String modelId,
    required String revisionRoot,
  });
}
