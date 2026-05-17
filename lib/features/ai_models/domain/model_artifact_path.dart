class ModelArtifactPath {
  const ModelArtifactPath({
    required this.role,
    required this.sourceId,
    required this.localPath,
    this.checksum,
    this.sizeBytes,
  });

  factory ModelArtifactPath.fromJson(Map<String, dynamic> json) {
    return ModelArtifactPath(
      role: json['role'] as String? ?? 'model',
      sourceId: json['source_id'] as String? ?? '',
      localPath: json['local_path'] as String? ?? '',
      checksum: json['checksum'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
    );
  }

  final String role;
  final String sourceId;
  final String localPath;
  final String? checksum;
  final int? sizeBytes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role,
      'source_id': sourceId,
      'local_path': localPath,
      'checksum': checksum,
      'size_bytes': sizeBytes,
    };
  }
}
