part of 'sqlite_model_registry_repository.dart';

bool _hasTrustedProvenance(ModelRegistryEntry entry) {
  return entry.releaseId != null &&
      entry.releaseId!.isNotEmpty &&
      (entry.catalogVersion ?? 0) > 0 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.catalogDigest ?? '') &&
      (entry.generation ?? 0) > 0 &&
      _isSafeRevisionRoot(entry.revisionRoot);
}

bool _rowHasTrustedProvenance(Map<String, Object?> row) {
  return (row['active_release_id'] as String?)?.isNotEmpty == true &&
      (row['catalog_version'] as int? ?? 0) > 0 &&
      RegExp(
        r'^[0-9a-f]{64}$',
      ).hasMatch(row['catalog_digest'] as String? ?? '') &&
      (row['install_generation'] as int? ?? 0) > 0 &&
      _isSafeRevisionRoot(row['revision_root'] as String?);
}

void _validateTrustedEntry(ModelRegistryEntry entry) {
  if (!_hasTrustedProvenance(entry) ||
      entry.localPath == null ||
      entry.localPath!.trim().isEmpty ||
      !_hasCompleteArtifactSet(
        entry.artifacts,
        releaseId: entry.releaseId!,
        requireInstalled:
            entry.enabled ||
            entry.integrityStatus == ModelIntegrityStatus.valid,
      )) {
    throw ArgumentError.value(
      entry,
      'entry',
      'A complete verified signed model revision is required.',
    );
  }
  final primary = entry.artifactPathForRole('model');
  if (primary == null || _pathKey(primary) != _pathKey(entry.localPath!)) {
    throw ArgumentError.value(
      entry,
      'entry',
      'Primary artifact path mismatch.',
    );
  }
}

bool _hasCompleteArtifactSet(
  List<ModelArtifactPath> artifacts, {
  required String releaseId,
  required bool requireInstalled,
}) {
  if (artifacts.isEmpty) {
    return false;
  }
  final ids = <String>{};
  final roles = <String>{};
  final paths = <String>{};
  var hasPrimary = false;
  for (final artifact in artifacts) {
    if (artifact.artifactId.isEmpty ||
        artifact.releaseId != releaseId ||
        artifact.role.isEmpty ||
        artifact.localPath.trim().isEmpty ||
        !_isSafeRelativePath(artifact.relativePath) ||
        !ids.add(artifact.artifactId) ||
        !roles.add(artifact.role) ||
        !paths.add(artifact.relativePath.toLowerCase()) ||
        !artifact.isVerified ||
        (requireInstalled &&
            artifact.required &&
            artifact.state != 'installed')) {
      return false;
    }
    hasPrimary |= artifact.role == 'model';
  }
  return hasPrimary;
}

ModelArtifactPath _mapNormalizedArtifact(
  Map<String, Object?> row, {
  required String? primaryPath,
  required List<ModelArtifactPath> legacyArtifacts,
}) {
  final artifactId = row['artifact_id']! as String;
  final role = row['role']! as String;
  ModelArtifactPath? legacy;
  for (final candidate in legacyArtifacts) {
    if (candidate.artifactId == artifactId ||
        (candidate.artifactId.isEmpty && candidate.role == role)) {
      legacy = candidate;
      break;
    }
  }
  return ModelArtifactPath(
    artifactId: artifactId,
    releaseId: row['release_id']! as String,
    role: role,
    required: (row['required'] as int? ?? 0) == 1,
    relativePath: row['relative_path']! as String,
    sourceId: row['source_id'] as String? ?? legacy?.sourceId ?? '',
    localPath: legacy?.localPath ?? (role == 'model' ? primaryPath ?? '' : ''),
    expectedChecksum: row['expected_sha256']! as String,
    expectedSizeBytes: row['expected_size_bytes']! as int,
    verifiedChecksum: row['verified_sha256'] as String?,
    verifiedSizeBytes: row['verified_size_bytes'] as int?,
    state: row['state']! as String,
    verifiedAt: row['verified_at'] as int?,
  );
}

List<ModelArtifactPath> _cleanupArtifacts(List<ModelArtifactPath> artifacts) {
  return artifacts
      .map(
        (artifact) => ModelArtifactPath(
          artifactId: artifact.artifactId,
          releaseId: artifact.releaseId,
          role: artifact.role,
          sourceId: artifact.sourceId,
          localPath: artifact.localPath,
          relativePath: artifact.relativePath,
          required: artifact.required,
          expectedChecksum: artifact.expectedChecksum,
          expectedSizeBytes: artifact.expectedSizeBytes,
          verifiedChecksum: artifact.verifiedChecksum,
          verifiedSizeBytes: artifact.verifiedSizeBytes,
          checksum: artifact.checksum,
          sizeBytes: artifact.sizeBytes,
          state: 'unknown',
        ),
      )
      .toList(growable: false);
}

Future<bool> _requiredFilesPresent({
  required String? primaryPath,
  required List<ModelArtifactPath> artifacts,
}) async {
  if (!await _filePresent(primaryPath)) {
    return false;
  }
  for (final artifact in artifacts.where((artifact) => artifact.required)) {
    if (!await _filePresent(artifact.localPath)) {
      return false;
    }
  }
  return true;
}

Future<bool> _filePresent(String? path) async {
  if (path == null || path.trim().isEmpty) {
    return false;
  }
  if (!p.isAbsolute(path) && path.startsWith('assets/')) {
    return true;
  }
  return await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.file;
}

ModelIntegrityStatus _parseIntegrityStatus(String? raw) {
  return ModelIntegrityStatus.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => ModelIntegrityStatus.unknown,
  );
}

bool _isSafeRevisionRoot(String? value) =>
    value != null &&
    value.startsWith('revisions/') &&
    _isSafeRelativePath(value);

bool _isSafeRelativePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith(r'\') ||
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

String _pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;

List<ModelArtifactPath> _decodeArtifactsOrEmpty(String? raw) {
  try {
    return decodeModelArtifactPathsFromSqlite(raw);
  } on FormatException {
    return const <ModelArtifactPath>[];
  } on TypeError {
    return const <ModelArtifactPath>[];
  }
}

String encodeModelArtifactPathsForSqlite(List<ModelArtifactPath> artifacts) {
  return jsonEncode(
    artifacts.map((artifact) => artifact.toJson()).toList(growable: false),
  );
}

List<ModelArtifactPath> decodeModelArtifactPathsFromSqlite(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <ModelArtifactPath>[];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List<Object?> ||
      !decoded.every((entry) => entry is Map<String, dynamic>)) {
    throw const FormatException('model_artifact_paths_invalid');
  }
  return decoded
      .cast<Map<String, dynamic>>()
      .map(ModelArtifactPath.fromJson)
      .toList(growable: false);
}
