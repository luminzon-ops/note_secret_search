import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/application/device_capability_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

void main() {
  test(
    'device capability report combines the trusted catalog with profile facts',
    () async {
      final container = ProviderContainer(
        overrides: <Override>[
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const <ModelCatalogEntry>[
              _compatibleModel,
              _unsupportedModel,
            ],
          ),
          deviceProfileProvider.overrideWith((ref) async => _arm64Profile),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(
        deviceCapabilityReportProvider.future,
      );

      expect(report.defaultModelIdForType('llm'), _compatibleModel.id);
      expect(
        report.assessmentFor(_compatibleModel.id).compatibility,
        ModelCompatibility.compatible,
      );
      expect(
        report.assessmentFor(_unsupportedModel.id).compatibility,
        ModelCompatibility.incompatible,
      );
    },
  );
}

const _arm64Profile = DeviceProfile(
  manufacturer: 'Huawei',
  brand: 'HUAWEI',
  model: 'SPN-AL00',
  device: 'HWSPN',
  product: 'SPN-AL00',
  sdkInt: 29,
  release: '10',
  supportedAbis: <String>['arm64-v8a'],
  totalRamMb: 8192,
  availableRamMb: 4096,
  totalStorageMb: 128000,
  availableStorageMb: 64000,
);

const _compatibleModel = ModelCatalogEntry(
  id: 'arm64-model',
  type: 'llm',
  tier: 'local',
  displayName: 'Arm64 Model',
  description: 'fixture',
  sizeBytes: 1024,
  minRamMb: 2048,
  recommendedTier: 'local',
  sources: <ModelSourceEntry>[],
  artifacts: <ModelArtifactSpec>[
    ModelArtifactSpec(
      id: 'arm64-artifact',
      releaseId: 'release-1',
      role: 'model',
      required: true,
      relativePath: 'model.gguf',
      sizeBytes: 1024,
      checksum:
          'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      origin: ModelArtifactOrigin.download,
      sources: <ModelSourceEntry>[],
      supportedAbis: <String>['arm64-v8a'],
    ),
  ],
);

const _unsupportedModel = ModelCatalogEntry(
  id: 'x86-model',
  type: 'llm',
  tier: 'local',
  displayName: 'X86 Model',
  description: 'fixture',
  sizeBytes: 1024,
  minRamMb: 2048,
  recommendedTier: 'local',
  sources: <ModelSourceEntry>[],
  artifacts: <ModelArtifactSpec>[
    ModelArtifactSpec(
      id: 'x86-artifact',
      releaseId: 'release-1',
      role: 'model',
      required: true,
      relativePath: 'model.gguf',
      sizeBytes: 1024,
      checksum:
          'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      origin: ModelArtifactOrigin.download,
      sources: <ModelSourceEntry>[],
      supportedAbis: <String>['x86_64'],
    ),
  ],
);
