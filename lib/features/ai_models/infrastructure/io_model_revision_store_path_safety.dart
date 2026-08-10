part of 'io_model_revision_store.dart';

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
  required String resolvedSourceOwner,
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
    if (!_isSameOrWithin(resolvedSourceOwner, resolvedSource)) {
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

Future<void> _deleteOwnedFileIfPresent(
  String path,
  String resolvedOwner,
) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return;
  }
  if (type != FileSystemEntityType.file) {
    throw const ModelRevisionStoreException('revision_cleanup_target_invalid');
  }
  final resolved = await File(path).resolveSymbolicLinks();
  if (!_isSameOrWithin(resolvedOwner, resolved)) {
    throw const ModelRevisionStoreException('revision_path_outside_root');
  }
  await File(path).delete();
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
