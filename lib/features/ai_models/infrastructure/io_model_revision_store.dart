import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

class IoModelRevisionStore implements ModelRevisionStore {
  IoModelRevisionStore({
    Future<Directory> Function()? applicationSupportDirectoryProvider,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory;

  final Future<Directory> Function() _applicationSupportDirectoryProvider;

  @override
  Future<InstalledModelRevision> installVerifiedRevision({
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
          resolvedStagingRoot: resolvedStagingRoot,
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

  @override
  Future<void> recoverInterruptedInstalls({required String modelId}) async {
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

  @override
  Future<void> discardInstalledRevision({
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

void _validateArtifacts(List<StagedModelArtifact> artifacts) {
  final ids = <String>{};
  final paths = <String>{};
  for (final artifact in artifacts) {
    _validateIdentifier(artifact.artifactId, 'revision_artifact_id_invalid');
    final relativePath = artifact.relativePath;
    final pathKey = relativePath.toLowerCase();
    if (artifact.expectedSizeBytes <= 0 ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(artifact.expectedChecksum) ||
        !_isSafeRelativePath(relativePath) ||
        !ids.add(artifact.artifactId) ||
        !paths.add(pathKey)) {
      throw const ModelRevisionStoreException('revision_artifact_path_invalid');
    }
  }
}

void _validateIdentifier(String value, String code) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value) ||
      value == '.' ||
      value == '..') {
    throw ModelRevisionStoreException(code);
  }
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
  return value
      .split('/')
      .every(
        (segment) =>
            segment.isNotEmpty &&
            segment != '.' &&
            segment != '..' &&
            !segment.contains(':'),
      );
}

Future<String> _resolvedDirectoryWithin(
  String path,
  String resolvedOwner, {
  required String missingCode,
}) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type != FileSystemEntityType.directory &&
      type != FileSystemEntityType.link) {
    throw ModelRevisionStoreException(missingCode);
  }
  final resolved = await Directory(path).resolveSymbolicLinks();
  if (!_isSameOrWithin(resolvedOwner, resolved)) {
    throw const ModelRevisionStoreException('revision_path_outside_root');
  }
  if (await FileSystemEntity.type(resolved, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw ModelRevisionStoreException(missingCode);
  }
  return resolved;
}

Future<InstalledModelRevision?> _existingRevision({
  required String revisionRoot,
  required String resolvedRevisionsRoot,
  required List<StagedModelArtifact> artifacts,
}) async {
  final type = await FileSystemEntity.type(revisionRoot, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return null;
  }
  if (type != FileSystemEntityType.directory) {
    throw const ModelRevisionStoreException('revision_target_invalid');
  }
  final resolvedRevision = await Directory(revisionRoot).resolveSymbolicLinks();
  if (!_isSameOrWithin(resolvedRevisionsRoot, resolvedRevision)) {
    throw const ModelRevisionStoreException('revision_path_outside_root');
  }
  final paths = <String, String>{};
  for (final artifact in artifacts) {
    final target = _absolute(
      p.joinAll(<String>[revisionRoot, ...artifact.relativePath.split('/')]),
    );
    if (!p.isWithin(revisionRoot, target) ||
        await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.file ||
        await File(target).length() != artifact.expectedSizeBytes ||
        await _sha256Identity(target) != artifact.expectedChecksum) {
      throw const ModelRevisionStoreException('revision_target_conflict');
    }
    paths[artifact.artifactId] = target;
  }
  return InstalledModelRevision(
    revisionRoot: revisionRoot,
    pathsByArtifactId: Map<String, String>.unmodifiable(paths),
  );
}

Future<void> _copyVerifiedArtifact({
  required String source,
  required String resolvedStagingRoot,
  required String target,
  required int expectedSizeBytes,
  required String expectedChecksum,
}) async {
  final input = await File(source).open();
  RandomAccessFile? output;
  final digestOutput = _DigestCollector();
  final digestSink = sha256.startChunkedConversion(digestOutput);
  var copiedBytes = 0;
  try {
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
    output = await File(target).open(mode: FileMode.write);
    final buffer = Uint8List(64 * 1024);
    while (true) {
      final read = await input.readInto(buffer);
      if (read == 0) {
        break;
      }
      copiedBytes += read;
      if (copiedBytes > expectedSizeBytes) {
        throw const ModelRevisionStoreException(
          'revision_staging_size_mismatch',
        );
      }
      digestSink.add(Uint8List.sublistView(buffer, 0, read));
      await output.writeFrom(buffer, 0, read);
    }
    digestSink.close();
    await output.flush();
  } finally {
    await input.close();
    await output?.close();
  }
  if (copiedBytes != expectedSizeBytes) {
    throw const ModelRevisionStoreException('revision_staging_size_mismatch');
  }
  final stagedChecksum = 'sha256:${digestOutput.value}';
  if (stagedChecksum != expectedChecksum) {
    throw const ModelRevisionStoreException(
      'revision_staging_checksum_mismatch',
    );
  }
  if (await File(target).length() != expectedSizeBytes) {
    throw const ModelRevisionStoreException('revision_copy_size_mismatch');
  }
  if (await _sha256Identity(target) != expectedChecksum) {
    throw const ModelRevisionStoreException('revision_copy_checksum_mismatch');
  }
}

Future<String> _sha256Identity(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return 'sha256:$digest';
}

Future<void> _deleteOwnedDirectory(
  String path,
  String resolvedModelRoot,
) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return;
  }
  if (type != FileSystemEntityType.directory) {
    throw const ModelRevisionStoreException('revision_cleanup_target_invalid');
  }
  final resolved = await Directory(path).resolveSymbolicLinks();
  if (!p.isWithin(resolvedModelRoot, resolved)) {
    throw const ModelRevisionStoreException('revision_path_outside_root');
  }
  await Directory(path).delete(recursive: true);
}

Future<String> _resolveEntity(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  return switch (type) {
    FileSystemEntityType.directory => Directory(path).resolveSymbolicLinks(),
    FileSystemEntityType.file => File(path).resolveSymbolicLinks(),
    FileSystemEntityType.link => Link(path).resolveSymbolicLinks(),
    _ => throw const ModelRevisionStoreException(
      'revision_cleanup_target_invalid',
    ),
  };
}

String _absolute(String path) => p.normalize(p.absolute(path));

String _pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;

bool _isSameOrWithin(String parent, String child) {
  return _pathKey(parent) == _pathKey(child) || p.isWithin(parent, child);
}

class _DigestCollector implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final result = _value;
    if (result == null) {
      throw const ModelRevisionStoreException('revision_digest_missing');
    }
    return result;
  }

  @override
  void add(Digest data) {
    if (_value != null) {
      throw const ModelRevisionStoreException('revision_digest_invalid');
    }
    _value = data;
  }

  @override
  void close() {}
}
