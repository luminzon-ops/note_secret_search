import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

void main() {
  test('verified structured registry entry requires every required artifact', () {
    final entry = ModelRegistryEntry(
      id: 'minicpm_v_4_6_q4_k_m',
      type: 'multimodal_llm',
      provider: 'builtin_catalog',
      name: 'MiniCPM-V 4.6',
      version: null,
      sizeBytes: 1516275776,
      quantization: 'Q4_K_M',
      minRamMb: 6144,
      recommendedTier: 'vision_language_local',
      localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
      checksum: 'sha256:model',
      enabled: true,
      installedAt: DateTime.fromMillisecondsSinceEpoch(1),
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.valid,
      releaseId: 'release-1',
      catalogVersion: 1,
      catalogDigest: 'a' * 64,
      generation: 1,
      revisionRoot: 'revisions/1',
      artifacts: const <ModelArtifactPath>[
        ModelArtifactPath(
          artifactId: 'model',
          releaseId: 'release-1',
          role: 'model',
          sourceId: 'model-source',
          localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
          relativePath: 'model.gguf',
          expectedChecksum:
              'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          expectedSizeBytes: 1,
          verifiedChecksum:
              'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          verifiedSizeBytes: 1,
          state: 'installed',
          verifiedAt: 1,
        ),
        ModelArtifactPath(
          artifactId: 'mmproj',
          releaseId: 'release-1',
          role: 'mmproj',
          sourceId: 'mmproj-source',
          localPath: '/models/mmproj-model-f16.gguf',
          relativePath: 'mmproj.gguf',
          expectedChecksum:
              'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          expectedSizeBytes: 2,
          verifiedChecksum:
              'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          verifiedSizeBytes: 2,
          state: 'installed',
          verifiedAt: 1,
        ),
      ],
    );

    expect(
      entry.artifactPathForRole('model'),
      '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
    );
    expect(
      entry.artifactPathForRole('mmproj'),
      '/models/mmproj-model-f16.gguf',
    );
    expect(entry.isInstalled, isTrue);
  });

  test('multimodal registry entry without mmproj is not installed', () {
    final entry = ModelRegistryEntry(
      id: 'minicpm_v_4_6_q4_k_m',
      type: 'multimodal_llm',
      provider: 'builtin_catalog',
      name: 'MiniCPM-V 4.6',
      version: null,
      sizeBytes: 1516275776,
      quantization: 'Q4_K_M',
      minRamMb: 6144,
      recommendedTier: 'vision_language_local',
      localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
      checksum: 'sha256:model',
      enabled: true,
      installedAt: DateTime.fromMillisecondsSinceEpoch(1),
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.valid,
      releaseId: 'release-1',
      catalogVersion: 1,
      catalogDigest: 'a' * 64,
      generation: 1,
      revisionRoot: 'revisions/1',
      artifacts: const <ModelArtifactPath>[
        ModelArtifactPath(
          artifactId: 'model',
          releaseId: 'release-1',
          role: 'model',
          sourceId: 'model-source',
          localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
          relativePath: 'model.gguf',
          expectedChecksum:
              'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          expectedSizeBytes: 1,
          verifiedChecksum:
              'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          verifiedSizeBytes: 1,
          state: 'installed',
          verifiedAt: 1,
        ),
      ],
    );

    expect(entry.artifactPathForRole('mmproj'), isNull);
    expect(entry.isInstalled, isFalse);
  });

  test(
    'legacy provenance and unknown artifact state never become installed',
    () {
      final legacy = ModelRegistryEntry(
        id: 'legacy',
        type: 'llm',
        provider: 'legacy',
        name: 'Legacy',
        version: null,
        sizeBytes: 1,
        quantization: null,
        minRamMb: null,
        recommendedTier: null,
        localPath: '/models/legacy/model.gguf',
        checksum: 'sha256:${'a' * 64}',
        enabled: true,
        installedAt: DateTime.fromMillisecondsSinceEpoch(1),
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.valid,
      );
      final unknown = legacy.copyWith(
        releaseId: 'release-1',
        catalogVersion: 1,
        catalogDigest: 'b' * 64,
        generation: 1,
        revisionRoot: 'revisions/1',
        artifacts: <ModelArtifactPath>[
          ModelArtifactPath(
            artifactId: 'model',
            releaseId: 'release-1',
            role: 'model',
            sourceId: 'source-1',
            localPath: '/models/legacy/revisions/1/model.gguf',
            relativePath: 'model.gguf',
            expectedChecksum: 'sha256:${'a' * 64}',
            expectedSizeBytes: 1,
            state: 'unknown',
          ),
        ],
      );

      expect(legacy.isInstalled, isFalse);
      expect(unknown.isInstalled, isFalse);
    },
  );
}
