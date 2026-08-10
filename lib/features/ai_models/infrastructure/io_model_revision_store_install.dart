part of 'io_model_revision_store.dart';

extension _IoModelRevisionStoreInstall on IoModelRevisionStore {
  Future<InstalledModelRevision> _installVerifiedRevision({
    required String modelId,
    required String operationId,
    required int generation,
    required List<StagedModelArtifact> artifacts,
  }) async {
    _validateIdentifier(modelId, 'model_id_invalid');
    _validateIdentifier(operationId, 'operation_id_invalid');
    if (generation <= 0 || artifacts.isEmpty) {
      throw const ModelRevisionStoreException('revision_request_invalid');
    }
    _validateArtifacts(artifacts);

    final support = await _applicationSupportDirectoryProvider();
    final supportRoot = _absolute(support.path);
    final modelsRoot = _absolute(p.join(supportRoot, 'models'));
    final modelRoot = _absolute(p.join(modelsRoot, modelId));
    final stagingRoot = _absolute(p.join(modelRoot, '.staging', operationId));
    final revisionsRoot = _absolute(p.join(modelRoot, 'revisions'));
    final revisionRoot = _absolute(p.join(revisionsRoot, '$generation'));
    final temporaryRoot = _absolute(
      p.join(revisionsRoot, '.installing-$generation-$operationId'),
    );
    if (!p.isWithin(modelsRoot, modelRoot) ||
        !p.isWithin(modelRoot, stagingRoot) ||
        !p.isWithin(modelRoot, revisionsRoot) ||
        !p.isWithin(revisionsRoot, revisionRoot) ||
        !p.isWithin(revisionsRoot, temporaryRoot)) {
      throw const ModelRevisionStoreException('revision_path_outside_root');
    }

    await Directory(modelsRoot).create(recursive: true);
    await Directory(modelRoot).create(recursive: true);
    await Directory(revisionsRoot).create(recursive: true);
    final resolvedModelRoot = await Directory(modelRoot).resolveSymbolicLinks();
    final resolvedModelsRoot = await Directory(
      modelsRoot,
    ).resolveSymbolicLinks();
    if (!_isSameOrWithin(resolvedModelsRoot, resolvedModelRoot)) {
      throw const ModelRevisionStoreException('revision_path_outside_root');
    }
    final resolvedRevisionsRoot = await _resolvedDirectoryWithin(
      revisionsRoot,
      resolvedModelRoot,
      missingCode: 'revision_root_missing',
    );
    final resolvedStagingRoot = await _resolvedDirectoryWithin(
      stagingRoot,
      resolvedModelRoot,
      missingCode: 'revision_staging_missing',
    );

    final existing = await _existingRevision(
      revisionRoot: revisionRoot,
      resolvedRevisionsRoot: resolvedRevisionsRoot,
      artifacts: artifacts,
    );
    if (existing != null) {
      await _deleteOwnedDirectory(stagingRoot, resolvedModelRoot);
      return existing;
    }

    await _deleteOwnedDirectory(temporaryRoot, resolvedModelRoot);
    await Directory(temporaryRoot).create(recursive: true);
    var renamed = false;
    try {
      for (final artifact in artifacts) {
        final source = _absolute(artifact.stagingPath);
        if (!_isSameOrWithin(stagingRoot, source)) {
          throw const ModelRevisionStoreException(
            'revision_staging_path_outside_root',
          );
        }
        if (await FileSystemEntity.type(source, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const ModelRevisionStoreException(
            'revision_staging_artifact_missing',
          );
        }
        final resolvedSource = await File(source).resolveSymbolicLinks();
        if (!_isSameOrWithin(resolvedStagingRoot, resolvedSource)) {
          throw const ModelRevisionStoreException(
            'revision_staging_path_outside_root',
          );
        }
        final target = _absolute(
          p.joinAll(<String>[
            temporaryRoot,
            ...artifact.relativePath.split('/'),
          ]),
        );
        if (!p.isWithin(temporaryRoot, target)) {
          throw const ModelRevisionStoreException(
            'revision_artifact_path_invalid',
          );
        }
        await Directory(p.dirname(target)).create(recursive: true);
        await _copyVerifiedArtifact(
          source: source,
          resolvedSourceOwner: resolvedStagingRoot,
          target: target,
          expectedSizeBytes: artifact.expectedSizeBytes,
          expectedChecksum: artifact.expectedChecksum,
        );
      }

      await Directory(temporaryRoot).rename(revisionRoot);
      renamed = true;
      final installed = await _existingRevision(
        revisionRoot: revisionRoot,
        resolvedRevisionsRoot: resolvedRevisionsRoot,
        artifacts: artifacts,
      );
      if (installed == null) {
        throw const ModelRevisionStoreException('revision_target_invalid');
      }
      await _deleteOwnedDirectory(stagingRoot, resolvedModelRoot);
      return installed;
    } catch (_) {
      await _deleteOwnedDirectory(
        renamed ? revisionRoot : temporaryRoot,
        resolvedModelRoot,
      );
      rethrow;
    }
  }

  Future<void> _recoverInterruptedInstalls({required String modelId}) async {
    _validateIdentifier(modelId, 'model_id_invalid');
    final support = await _applicationSupportDirectoryProvider();
    final supportRoot = _absolute(support.path);
    final modelsRoot = _absolute(p.join(supportRoot, 'models'));
    final modelRoot = _absolute(p.join(modelsRoot, modelId));
    final revisionsRoot = _absolute(p.join(modelRoot, 'revisions'));
    if (!_isSameOrWithin(modelsRoot, modelRoot)) {
      throw const ModelRevisionStoreException('revision_path_outside_root');
    }
    if (await FileSystemEntity.type(modelRoot, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
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
    if (await FileSystemEntity.type(revisionsRoot, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    final resolvedRevisionsRoot = await _resolvedDirectoryWithin(
      revisionsRoot,
      resolvedModelRoot,
      missingCode: 'revision_root_missing',
    );
    await for (final entity in Directory(
      revisionsRoot,
    ).list(followLinks: false)) {
      if (!p.basename(entity.path).startsWith('.installing-')) {
        continue;
      }
      final resolved = await _resolveEntity(entity.path);
      if (!_isSameOrWithin(resolvedRevisionsRoot, resolved)) {
        throw const ModelRevisionStoreException('revision_path_outside_root');
      }
      await _deleteOwnedDirectory(entity.path, resolvedModelRoot);
    }
  }

  Future<void> _discardInstalledRevision({
    required String modelId,
    required String revisionRoot,
  }) async {
    _validateIdentifier(modelId, 'model_id_invalid');
    final support = await _applicationSupportDirectoryProvider();
    final supportRoot = _absolute(support.path);
    final modelsRoot = _absolute(p.join(supportRoot, 'models'));
    final modelRoot = _absolute(p.join(modelsRoot, modelId));
    final rawRevisionRoot = p.isAbsolute(revisionRoot)
        ? revisionRoot
        : p.join(modelRoot, revisionRoot);
    final target = _absolute(rawRevisionRoot);
    if (!p.isWithin(modelRoot, target) || !p.isWithin(modelsRoot, modelRoot)) {
      throw const ModelRevisionStoreException('revision_path_outside_root');
    }
    if (await FileSystemEntity.type(modelRoot, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
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
    await _deleteOwnedDirectory(target, resolvedModelRoot);
  }
}
