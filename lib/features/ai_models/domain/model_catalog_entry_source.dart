part of 'model_catalog_entry.dart';

class ModelSourceEntry {
  const ModelSourceEntry({
    required this.id,
    required this.label,
    required this.url,
    this.checksum = '',
    this.role = 'model',
    this.required = true,
    this.signature,
    this.signatureAlgorithm,
    this.keyId,
    this.priority = 0,
    this.artifactId = '',
  });

  factory ModelSourceEntry.fromJson(Map<String, dynamic> json) {
    return ModelSourceEntry(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
      role: json['role'] as String? ?? 'model',
      required: json['required'] as bool? ?? true,
      signature: json['signature'] as String?,
      signatureAlgorithm:
          (json['signature_algorithm'] ?? json['signatureAlgorithm'])
              as String?,
      keyId: (json['key_id'] ?? json['keyId']) as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      artifactId: json['artifact_id'] as String? ?? '',
    );
  }

  factory ModelSourceEntry.fromManifestJson(
    Map<String, Object?> json, {
    required String checksum,
    required String artifactId,
    required bool required,
  }) {
    _expectKeys(json, const <String>{'source_id', 'label', 'url', 'priority'});
    return ModelSourceEntry(
      id: _string(json['source_id'], required: true) ?? '',
      label: _string(json['label'], required: true) ?? '',
      url: _string(json['url'], required: true) ?? '',
      checksum: checksum,
      required: required,
      priority: _integer(json['priority'], required: true),
      artifactId: artifactId,
    );
  }

  bool declaresArtifactTrust() {
    return signature != null && signatureAlgorithm != null;
  }

  final String id;
  final String label;
  final String url;

  /// Deprecated compatibility projection. Trust is owned by the signed artifact.
  final String checksum;
  final String role;
  final bool required;
  final String? signature;
  final String? signatureAlgorithm;
  final String? keyId;
  final int priority;
  final String artifactId;
}
