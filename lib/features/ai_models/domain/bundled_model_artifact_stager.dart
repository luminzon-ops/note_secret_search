class BundledModelArtifactStageResult {
  const BundledModelArtifactStageResult({
    required this.path,
    required this.sizeBytes,
  });

  final String path;
  final int sizeBytes;
}

abstract interface class BundledModelArtifactStager {
  Future<BundledModelArtifactStageResult> stage({
    required String assetPath,
    required String targetPath,
    required int expectedSizeBytes,
  });
}
