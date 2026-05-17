import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

void main() {
  test('multimodal registry entry is installed only when required artifacts exist', () {
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
      artifacts: const <ModelArtifactPath>[
        ModelArtifactPath(
          role: 'model',
          sourceId: 'model-source',
          localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
          checksum: 'sha256:model',
          sizeBytes: 1,
        ),
        ModelArtifactPath(
          role: 'mmproj',
          sourceId: 'mmproj-source',
          localPath: '/models/mmproj-model-f16.gguf',
          checksum: 'sha256:mmproj',
          sizeBytes: 2,
        ),
      ],
    );

    expect(entry.artifactPathForRole('model'), '/models/MiniCPM-V-4_6-Q4_K_M.gguf');
    expect(entry.artifactPathForRole('mmproj'), '/models/mmproj-model-f16.gguf');
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
      artifacts: const <ModelArtifactPath>[
        ModelArtifactPath(
          role: 'model',
          sourceId: 'model-source',
          localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
          checksum: 'sha256:model',
          sizeBytes: 1,
        ),
      ],
    );

    expect(entry.artifactPathForRole('mmproj'), isNull);
    expect(entry.isInstalled, isFalse);
  });
}
