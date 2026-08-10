part of 'database_schema_v5_end_to_end_test.dart';

class _MigrationCase {
  const _MigrationCase({
    required this.version,
    required this.name,
    required this.sourceSchemaVersion,
    required this.hasChat,
    required this.v4IntegrityStatus,
    required this.v4ArtifactPathsJson,
    required this.v5IntegrityStatus,
    required this.v5ArtifactPaths,
    required this.expectedCanonicalDigest,
    required this.expectedV7CanonicalDigest,
    required this.expectedV8CanonicalDigest,
  });

  final LegacyFixtureVersion version;
  final String name;
  final int sourceSchemaVersion;
  final bool hasChat;
  final String v4IntegrityStatus;
  final String? v4ArtifactPathsJson;
  final String v5IntegrityStatus;
  final List<Object?>? v5ArtifactPaths;
  final String expectedCanonicalDigest;
  final String expectedV7CanonicalDigest;
  final String expectedV8CanonicalDigest;
}

const _structuredModelArtifact = <Object?>[
  <String, Object?>{'role': 'model', 'local_path': '/models/legacy.onnx'},
];

const _migrationCases = <_MigrationCase>[
  _MigrationCase(
    version: LegacyFixtureVersion.v1,
    name: 'v1',
    sourceSchemaVersion: 1,
    hasChat: false,
    v4IntegrityStatus: 'unknown',
    v4ArtifactPathsJson: null,
    v5IntegrityStatus: 'unknown',
    v5ArtifactPaths: null,
    expectedCanonicalDigest:
        'f17d452ee9d4022c9e9a932545675733d3b1f51d513bce0f1bd6ea94ffab2b16',
    expectedV7CanonicalDigest:
        '33a725d32febf78ae244a3e87f96520ce2873853084b44b974b6a8d34b70c922',
    expectedV8CanonicalDigest:
        '436eae19069e1bffadd7a7cc55780c3d0d9e0c2f62a2d6b266af79f8e6ede613',
  ),
  _MigrationCase(
    version: LegacyFixtureVersion.v2,
    name: 'v2',
    sourceSchemaVersion: 2,
    hasChat: true,
    v4IntegrityStatus: 'unknown',
    v4ArtifactPathsJson: null,
    v5IntegrityStatus: 'unknown',
    v5ArtifactPaths: null,
    expectedCanonicalDigest:
        '292f3defcbc27c02e341f7eea25a7cff2c2293896112f60091a78c76fe3a1985',
    expectedV7CanonicalDigest:
        '9109343fa7b2bb193e360272e973720c0eaf12f39dfc868f41bf52960a69cfd5',
    expectedV8CanonicalDigest:
        '2351ac2eaba513e21301401c938c2e7ac08be28bf0943c63a117f6b7824a6cf9',
  ),
  _MigrationCase(
    version: LegacyFixtureVersion.upgradedV3,
    name: 'upgraded v3',
    sourceSchemaVersion: 3,
    hasChat: true,
    v4IntegrityStatus: 'unknown',
    v4ArtifactPathsJson: '["/models/legacy.onnx"]',
    v5IntegrityStatus: 'unknown',
    v5ArtifactPaths: _structuredModelArtifact,
    expectedCanonicalDigest:
        'd20cdb0230f26d4f387d16add55c5a3e09ce58784f61736eef5fa9729b4a2f82',
    expectedV7CanonicalDigest:
        '3ebe17bab1934a20d9d4bc1ba0c472343b4dd878ab815a2e1203e9aef1c13fc5',
    expectedV8CanonicalDigest:
        '78693d89bfd5b7e784f5dbb4095691ad8cc84a84fcb4127f230b99518d5fb6b3',
  ),
  _MigrationCase(
    version: LegacyFixtureVersion.freshV3,
    name: 'fresh v3',
    sourceSchemaVersion: 3,
    hasChat: true,
    v4IntegrityStatus: 'verified',
    v4ArtifactPathsJson: '["/models/legacy.onnx"]',
    v5IntegrityStatus: 'valid',
    v5ArtifactPaths: _structuredModelArtifact,
    expectedCanonicalDigest:
        'c4077e096892228b9a69c6562c1cbccf5b8d9b8b9cf5a8cd98e404c57f076400',
    expectedV7CanonicalDigest:
        '7b14c344ab8fce6b65fe7555a6442e3b3d6fda0f1f3350cd239723155520a7f5',
    expectedV8CanonicalDigest:
        '78693d89bfd5b7e784f5dbb4095691ad8cc84a84fcb4127f230b99518d5fb6b3',
  ),
];
