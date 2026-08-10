part of 'io_model_revision_store.dart';

extension _IoModelRevisionStoreStaging on IoModelRevisionStore {
  Future<StagedModelArtifact> _stageExistingArtifact({
    required String modelId,
    required String operationId,
    required String artifactId,
    required String relativePath,
    required String sourcePath,
    required int expectedSizeBytes,
    required String expectedChecksum,
  }) async {
    _validateIdentifier(modelId, 'model_id_invalid');
    _validateIdentifier(operationId, 'operation_id_invalid');
    final requested = StagedModelArtifact(
      artifactId: artifactId,
      relativePath: relativePath,
      stagingPath: '',
      expectedSizeBytes: expectedSizeBytes,
      expectedChecksum: expectedChecksum,
    );
    _validateArtifacts(<StagedModelArtifact>[requested]);

    final support = await _applicationSupportDirectoryProvider();
    final supportRoot = _absolute(support.path);
    final modelsRoot = _absolute(p.join(supportRoot, 'models'));
    final modelRoot = _absolute(p.join(modelsRoot, modelId));
    final revisionsRoot = _absolute(p.join(modelRoot, 'revisions'));
    final stagingRoot = _absolute(p.join(modelRoot, '.staging', operationId));
    final source = _absolute(sourcePath);
    final target = _absolute(p.join(stagingRoot, '$artifactId.part'));
    final temporaryTarget = '$target.copying';
    if (!p.isWithin(modelsRoot, modelRoot) ||
        !p.isWithin(modelRoot, revisionsRoot) ||
        !p.isWithin(modelRoot, stagingRoot) ||
        !p.isWithin(revisionsRoot, source) ||
        !p.isWithin(stagingRoot, target) ||
        !p.isWithin(stagingRoot, temporaryTarget)) {
      throw const ModelRevisionStoreException('revision_path_outside_root');
    }

    final resolvedModelsRoot = await _resolvedDirectoryWithin(
      modelsRoot,
      supportRoot,
      missingCode: 'revision_models_root_missing',
    );
    final resolvedModelRoot = await _resolvedDirectoryWithin(
      modelRoot,
      resolvedModelsRoot,
      missingCode: 'revision_model_root_missing',
    );
    final resolvedRevisionsRoot = await _resolvedDirectoryWithin(
      revisionsRoot,
      resolvedModelRoot,
      missingCode: 'revision_root_missing',
    );
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const ModelRevisionStoreException(
        'revision_existing_artifact_missing',
      );
    }
    final resolvedSource = await File(source).resolveSymbolicLinks();
    if (!_isSameOrWithin(resolvedRevisionsRoot, resolvedSource)) {
      throw const ModelRevisionStoreException('revision_path_outside_root');
    }

    await Directory(stagingRoot).create(recursive: true);
    final resolvedStagingRoot = await _resolvedDirectoryWithin(
      stagingRoot,
      resolvedModelRoot,
      missingCode: 'revision_staging_missing',
    );
    await _deleteOwnedFileIfPresent(temporaryTarget, resolvedStagingRoot);
    await _deleteOwnedFileIfPresent(target, resolvedStagingRoot);
    try {
      await _copyVerifiedArtifact(
        source: source,
        resolvedSourceOwner: resolvedRevisionsRoot,
        target: temporaryTarget,
        expectedSizeBytes: expectedSizeBytes,
        expectedChecksum: expectedChecksum,
      );
      await File(temporaryTarget).rename(target);
    } catch (_) {
      await _deleteOwnedFileIfPresent(temporaryTarget, resolvedStagingRoot);
      rethrow;
    }
    return StagedModelArtifact(
      artifactId: artifactId,
      relativePath: relativePath,
      stagingPath: target,
      expectedSizeBytes: expectedSizeBytes,
      expectedChecksum: expectedChecksum,
    );
  }
}
