import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/device_tier_card.dart';

void main() {
  testWidgets(
    'device tier card shows complete facts and advisory default recommendation',
    (tester) async {
      final report = const DeviceCapabilityAssessor().assess(
        catalog: const <ModelCatalogEntry>[_model],
        profile: _profile,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceTierCard(profile: _profile, capabilityReport: report),
          ),
        ),
      );

      expect(find.text('Huawei'), findsOneWidget);
      expect(find.text('SPN-AL00'), findsOneWidget);
      expect(find.text('arm64-v8a, armeabi-v7a'), findsOneWidget);
      expect(find.text('设备默认推荐：Local Model'), findsOneWidget);
      expect(find.textContaining('已就绪'), findsNothing);
    },
  );
}

const _profile = DeviceProfile(
  manufacturer: 'Huawei',
  brand: 'HUAWEI',
  model: 'SPN-AL00',
  device: 'HWSPN',
  product: 'SPN-AL00',
  sdkInt: 29,
  release: '10',
  supportedAbis: <String>['arm64-v8a', 'armeabi-v7a'],
  totalRamMb: 8192,
  availableRamMb: 4096,
  totalStorageMb: 128000,
  availableStorageMb: 64000,
);

const _model = ModelCatalogEntry(
  id: 'local-model',
  type: 'llm',
  tier: 'local',
  displayName: 'Local Model',
  description: 'fixture',
  sizeBytes: 1024,
  minRamMb: 2048,
  recommendedTier: 'local',
  sources: <ModelSourceEntry>[],
  artifacts: <ModelArtifactSpec>[
    ModelArtifactSpec(
      id: 'model',
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
