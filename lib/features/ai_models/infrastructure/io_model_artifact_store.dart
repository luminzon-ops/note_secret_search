import 'dart:io';

import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelArtifactStoreException implements Exception {
  const ModelArtifactStoreException(this.code);

  final String code;

  @override
  String toString() => code;
}

class IoModelArtifactStore implements ModelArtifactStore {
  IoModelArtifactStore({
    Future<Directory> Function()? applicationSupportDirectoryProvider,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory;

  final Future<Directory> Function() _applicationSupportDirectoryProvider;

  @override
  Future<void> deleteModelArtifacts({
    required String modelId,
    required String? primaryPath,
    required List<ModelArtifactPath> artifacts,
  }) async {
    _validateModelId(modelId);
    final supportDirectory = await _applicationSupportDirectoryProvider();
    final supportRoot = _absolute(supportDirectory.path);
    final modelsRoot = _absolute(p.join(supportRoot, 'models'));
    final modelDirectory = _absolute(p.join(modelsRoot, modelId));
    if (!p.isWithin(modelsRoot, modelDirectory)) {
      throw const ModelArtifactStoreException(
        'model_artifact_directory_outside_root',
      );
    }
    final resolvedSupportRoot =
        await _resolveExistingPath(supportRoot) ?? supportRoot;
    final resolvedModelsRoot =
        await _resolveExistingPath(modelsRoot) ?? modelsRoot;
    if (!_isSameOrWithin(resolvedSupportRoot, resolvedModelsRoot)) {
      throw const ModelArtifactStoreException(
        'model_artifact_directory_outside_root',
      );
    }
    final resolvedModelDirectory = await _resolveExistingPath(modelDirectory);
    if (resolvedModelDirectory != null &&
        !p.isWithin(resolvedModelsRoot, resolvedModelDirectory)) {
      throw const ModelArtifactStoreException(
        'model_artifact_directory_outside_root',
      );
    }

    final pathsByKey = <String, String>{};
    void addPath(String? rawPath) {
      if (rawPath == null || rawPath.trim().isEmpty) {
        return;
      }
      final path = _absolute(rawPath);
      if (!p.isWithin(modelDirectory, path)) {
        throw const ModelArtifactStoreException(
          'model_artifact_path_outside_directory',
        );
      }
      pathsByKey[_pathKey(path)] = path;
    }

    addPath(primaryPath);
    for (final artifact in artifacts) {
      addPath(artifact.localPath);
    }
    if (resolvedModelDirectory != null) {
      for (final path in pathsByKey.values) {
        await _validateResolvedOwnership(path, resolvedModelDirectory);
      }
    }
    for (final path in pathsByKey.values) {
      await _deleteFileOrLink(path);
    }

    final directory = Directory(modelDirectory);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<void> _deleteFileOrLink(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  switch (type) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.file:
      await File(path).delete();
    case FileSystemEntityType.link:
      await Link(path).delete();
    case FileSystemEntityType.directory:
      throw const ModelArtifactStoreException(
        'model_artifact_path_is_directory',
      );
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
      throw const ModelArtifactStoreException(
        'model_artifact_path_unsupported',
      );
  }
}

void _validateModelId(String modelId) {
  if (modelId.isEmpty ||
      modelId.trim() != modelId ||
      modelId == '.' ||
      modelId == '..' ||
      p.basename(modelId) != modelId) {
    throw ArgumentError.value(modelId, 'modelId', 'Invalid model id.');
  }
}

String _absolute(String path) => p.normalize(p.absolute(path));

String _pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;

bool _isSameOrWithin(String parent, String child) {
  return _pathKey(parent) == _pathKey(child) || p.isWithin(parent, child);
}

Future<void> _validateResolvedOwnership(
  String path,
  String resolvedModelDirectory,
) async {
  final resolvedPath = await _resolveNearestExistingPath(path);
  if (!_isSameOrWithin(resolvedModelDirectory, resolvedPath)) {
    throw const ModelArtifactStoreException(
      'model_artifact_path_outside_directory',
    );
  }
}

Future<String> _resolveNearestExistingPath(String path) async {
  var candidate = path;
  while (true) {
    final resolved = await _resolveExistingPath(candidate);
    if (resolved != null) {
      return resolved;
    }
    final parent = p.dirname(candidate);
    if (parent == candidate) {
      return candidate;
    }
    candidate = parent;
  }
}

Future<String?> _resolveExistingPath(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  return switch (type) {
    FileSystemEntityType.notFound => null,
    FileSystemEntityType.file => File(path).resolveSymbolicLinks(),
    FileSystemEntityType.directory => Directory(path).resolveSymbolicLinks(),
    FileSystemEntityType.link => Link(path).resolveSymbolicLinks(),
    FileSystemEntityType.pipe ||
    FileSystemEntityType.unixDomainSock => _absolute(path),
    _ => _absolute(path),
  };
}
