class ModelArtifactPath {
  const ModelArtifactPath({
    required this.role,
    required this.sourceId,
    required this.localPath,
    this.artifactId = '',
    this.releaseId = '',
    this.relativePath = '',
    this.required = true,
    this.expectedChecksum,
    this.verifiedChecksum,
    this.expectedSizeBytes,
    this.verifiedSizeBytes,
    this.checksum,
    this.sizeBytes,
    this.state = 'unknown',
    this.verifiedAt,
  });

  factory ModelArtifactPath.fromJson(Map<String, dynamic> json) {
    return ModelArtifactPath(
      role: json['role'] as String? ?? 'model',
      sourceId: json['source_id'] as String? ?? '',
      localPath: json['local_path'] as String? ?? '',
      artifactId: json['artifact_id'] as String? ?? '',
      releaseId: json['release_id'] as String? ?? '',
      relativePath: json['relative_path'] as String? ?? '',
      required: json['required'] as bool? ?? true,
      expectedChecksum:
          json['expected_sha256'] as String? ?? json['checksum'] as String?,
      verifiedChecksum: json['verified_sha256'] as String?,
      expectedSizeBytes:
          (json['expected_size_bytes'] as num?)?.toInt() ??
          (json['size_bytes'] as num?)?.toInt(),
      verifiedSizeBytes: (json['verified_size_bytes'] as num?)?.toInt(),
      checksum: json['checksum'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      state: json['state'] as String? ?? 'unknown',
      verifiedAt: (json['verified_at'] as num?)?.toInt(),
    );
  }

  final String role;
  final String sourceId;
  final String localPath;
  final String artifactId;
  final String releaseId;
  final String relativePath;
  final bool required;

  /// Manifest identity, never inferred from an untrusted download source.
  final String? expectedChecksum;
  final int? expectedSizeBytes;

  /// Bytes observed during per-artifact verification.
  final String? verifiedChecksum;
  final int? verifiedSizeBytes;

  /// Legacy cleanup compatibility. New installation paths use the explicit
  /// expected and verified fields above.
  final String? checksum;
  final int? sizeBytes;
  final String state;
  final int? verifiedAt;

  bool get isVerified =>
      (state == 'verified' || state == 'installed') &&
      RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(effectiveExpectedChecksum) &&
      effectiveVerifiedChecksum == effectiveExpectedChecksum &&
      effectiveExpectedSizeBytes > 0 &&
      effectiveVerifiedSizeBytes == effectiveExpectedSizeBytes &&
      verifiedAt != null;

  String get effectiveExpectedChecksum => expectedChecksum ?? checksum ?? '';

  String? get effectiveVerifiedChecksum => verifiedChecksum;

  int get effectiveExpectedSizeBytes => expectedSizeBytes ?? sizeBytes ?? 0;

  int? get effectiveVerifiedSizeBytes => verifiedSizeBytes;

  ModelArtifactPath copyWith({
    String? role,
    String? sourceId,
    String? localPath,
    String? artifactId,
    String? releaseId,
    String? relativePath,
    bool? required,
    String? expectedChecksum,
    bool clearExpectedChecksum = false,
    String? verifiedChecksum,
    bool clearVerifiedChecksum = false,
    int? expectedSizeBytes,
    bool clearExpectedSizeBytes = false,
    int? verifiedSizeBytes,
    bool clearVerifiedSizeBytes = false,
    String? checksum,
    bool clearChecksum = false,
    int? sizeBytes,
    bool clearSizeBytes = false,
    String? state,
    int? verifiedAt,
    bool clearVerifiedAt = false,
  }) {
    return ModelArtifactPath(
      role: role ?? this.role,
      sourceId: sourceId ?? this.sourceId,
      localPath: localPath ?? this.localPath,
      artifactId: artifactId ?? this.artifactId,
      releaseId: releaseId ?? this.releaseId,
      relativePath: relativePath ?? this.relativePath,
      required: required ?? this.required,
      expectedChecksum: clearExpectedChecksum
          ? null
          : (expectedChecksum ?? this.expectedChecksum),
      verifiedChecksum: clearVerifiedChecksum
          ? null
          : (verifiedChecksum ?? this.verifiedChecksum),
      expectedSizeBytes: clearExpectedSizeBytes
          ? null
          : (expectedSizeBytes ?? this.expectedSizeBytes),
      verifiedSizeBytes: clearVerifiedSizeBytes
          ? null
          : (verifiedSizeBytes ?? this.verifiedSizeBytes),
      checksum: clearChecksum ? null : (checksum ?? this.checksum),
      sizeBytes: clearSizeBytes ? null : (sizeBytes ?? this.sizeBytes),
      state: state ?? this.state,
      verifiedAt: clearVerifiedAt ? null : (verifiedAt ?? this.verifiedAt),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role,
      'source_id': sourceId,
      'local_path': localPath,
      'artifact_id': artifactId,
      'release_id': releaseId,
      'relative_path': relativePath,
      'required': required,
      'expected_sha256': expectedChecksum,
      'expected_size_bytes': expectedSizeBytes,
      'verified_sha256': verifiedChecksum,
      'verified_size_bytes': verifiedSizeBytes,
      'checksum': checksum,
      'size_bytes': sizeBytes,
      'state': state,
      'verified_at': verifiedAt,
    };
  }
}
