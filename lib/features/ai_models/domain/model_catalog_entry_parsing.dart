part of 'model_catalog_entry.dart';

void _validateArtifacts(
  List<ModelArtifactSpec> artifacts, {
  required bool strict,
}) {
  if (!strict) {
    return;
  }
  if (artifacts.isEmpty) {
    throw const ModelCatalogFormatException('artifact_list_empty');
  }
  final ids = <String>{};
  final roles = <String>{};
  final paths = <String>{};
  for (final artifact in artifacts) {
    if (!ids.add(artifact.id) ||
        !roles.add(artifact.role) ||
        !paths.add(artifact.relativePath.toLowerCase())) {
      throw const ModelCatalogFormatException('artifact_identity_duplicate');
    }
    if (artifact.id.isEmpty ||
        artifact.releaseId.isEmpty ||
        !const <String>{
          'model',
          'tokenizer',
          'mmproj',
          'sidecar',
        }.contains(artifact.role) ||
        artifact.sizeBytes <= 0 ||
        !_isSha256(artifact.checksum) ||
        !_isSafeRelativePath(artifact.relativePath) ||
        (artifact.required == false && artifact.role == 'model')) {
      throw const ModelCatalogFormatException('artifact_contract_invalid');
    }
    if (artifact.origin == ModelArtifactOrigin.download &&
        artifact.sources.isEmpty) {
      throw const ModelCatalogFormatException('artifact_sources_missing');
    }
    if (artifact.origin == ModelArtifactOrigin.bundledAsset &&
        artifact.sources.isNotEmpty) {
      throw const ModelCatalogFormatException(
        'bundled_artifact_source_invalid',
      );
    }
    final sourceIds = <String>{};
    for (final source in artifact.sources) {
      if (!sourceIds.add(source.id) ||
          source.id.isEmpty ||
          !_isHttpsUrl(source.url) ||
          source.artifactId != artifact.id ||
          source.checksum != artifact.checksum) {
        throw const ModelCatalogFormatException('artifact_source_invalid');
      }
    }
  }
  if (!roles.contains('model')) {
    throw const ModelCatalogFormatException('primary_artifact_missing');
  }
}

void _expectKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length || !value.keys.every(expected.contains)) {
    throw const ModelCatalogFormatException('catalog_schema_invalid');
  }
}

String? _string(Object? value, {required bool required}) {
  if (value == null && !required) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw const ModelCatalogFormatException('catalog_string_invalid');
  }
  return value;
}

int _integer(Object? value, {required bool required}) {
  if (value == null && !required) {
    return 0;
  }
  if (value is! int || value < 0) {
    throw const ModelCatalogFormatException('catalog_integer_invalid');
  }
  return value;
}

bool _bool(Object? value, {required bool required}) {
  if (value == null && !required) {
    return false;
  }
  if (value is! bool) {
    throw const ModelCatalogFormatException('catalog_boolean_invalid');
  }
  return value;
}

Map<String, Object?> _objectMap(Object? value, {required bool required}) {
  if (value == null && !required) {
    return const <String, Object?>{};
  }
  if (value is! Map) {
    throw const ModelCatalogFormatException('catalog_object_invalid');
  }
  return Map<String, Object?>.fromEntries(
    value.entries.map((entry) {
      if (entry.key is! String) {
        throw const ModelCatalogFormatException('catalog_object_key_invalid');
      }
      return MapEntry(entry.key as String, entry.value);
    }),
  );
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
  final segments = value.split('/');
  return segments.every(
    (segment) =>
        segment.isNotEmpty &&
        segment != '.' &&
        segment != '..' &&
        !segment.contains(':'),
  );
}

bool _isHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty;
}

bool _isSha256(String value) =>
    RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);
