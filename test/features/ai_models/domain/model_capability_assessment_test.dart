import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

void main() {
  const assessor = DeviceCapabilityAssessor();

  test('evaluates the arm64 runtime across the Android ABI matrix', () {
    final model = _model(
      id: 'arm64-llm',
      supportedAbis: const <String>['arm64-v8a'],
    );
    const expected = <String, ModelCompatibility>{
      'arm64-v8a': ModelCompatibility.compatible,
      'armeabi-v7a': ModelCompatibility.incompatible,
      'x86_64': ModelCompatibility.incompatible,
      'x86': ModelCompatibility.incompatible,
    };

    for (final entry in expected.entries) {
      final report = assessor.assess(
        catalog: <ModelCatalogEntry>[model],
        profile: _profile(supportedAbis: <String>[entry.key]),
      );

      expect(
        report.assessments.single.compatibility,
        entry.value,
        reason: entry.key,
      );
      expect(
        report.defaultModelIdForType('llm'),
        entry.value == ModelCompatibility.compatible ? model.id : isNull,
        reason: entry.key,
      );
    }
  });

  test('accepts any matching ABI from the complete device ABI list', () {
    final report = assessor.assess(
      catalog: <ModelCatalogEntry>[
        _model(id: 'arm64-llm', supportedAbis: const <String>['arm64-v8a']),
      ],
      profile: _profile(supportedAbis: const <String>['x86_64', 'arm64-v8a']),
    );

    final assessment = report.assessments.single;
    expect(assessment.compatibility, ModelCompatibility.compatible);
    expect(assessment.isDefaultRecommendation, isTrue);
    expect(assessment.explanation, contains('运行时加载校验'));
  });

  test(
    'uses RAM storage and ABI constraints for the default recommendation',
    () {
      final compatible = _model(
        id: 'small',
        minRamMb: 2048,
        sizeBytes: 512 * 1024 * 1024,
        supportedAbis: const <String>['arm64-v8a'],
      );
      final ramHeavy = _model(
        id: 'ram-heavy',
        minRamMb: 12288,
        sizeBytes: 512 * 1024 * 1024,
        supportedAbis: const <String>['arm64-v8a'],
      );
      final storageHeavy = _model(
        id: 'storage-heavy',
        minRamMb: 2048,
        sizeBytes: 20 * 1024 * 1024 * 1024,
        supportedAbis: const <String>['arm64-v8a'],
      );

      final report = assessor.assess(
        catalog: <ModelCatalogEntry>[ramHeavy, storageHeavy, compatible],
        profile: _profile(supportedAbis: const <String>['arm64-v8a']),
      );

      expect(report.defaultModelIdForType('llm'), compatible.id);
      expect(
        report.assessmentFor(ramHeavy.id).reasons,
        contains(ModelCapabilityReason.totalRamInsufficient),
      );
      expect(
        report.assessmentFor(storageHeavy.id).reasons,
        contains(ModelCapabilityReason.storageInsufficient),
      );
      expect(
        report.assessmentFor(compatible.id).compatibility,
        ModelCompatibility.compatible,
      );
    },
  );

  test(
    'reports resource pressure as constrained rather than runtime-ready',
    () {
      final model = _model(
        id: 'constrained',
        minRamMb: 2048,
        sizeBytes: 512 * 1024 * 1024,
        supportedAbis: const <String>['arm64-v8a'],
      );

      final report = assessor.assess(
        catalog: <ModelCatalogEntry>[model],
        profile: _profile(
          supportedAbis: const <String>['arm64-v8a'],
          availableRamMb: 512,
          availableStorageMb: 700,
        ),
      );

      final assessment = report.assessments.single;
      expect(assessment.compatibility, ModelCompatibility.constrained);
      expect(
        assessment.reasons,
        containsAll(<ModelCapabilityReason>[
          ModelCapabilityReason.availableRamConstrained,
          ModelCapabilityReason.storageConstrained,
        ]),
      );
      expect(assessment.explanation, contains('运行时加载校验'));
    },
  );

  test(
    'profile failure preserves catalog order and its first default per type',
    () {
      final first = _model(id: 'catalog-first', minRamMb: 8192);
      final second = _model(id: 'catalog-second', minRamMb: 1024);

      final report = assessor.assess(
        catalog: <ModelCatalogEntry>[first, second],
        profile: null,
      );

      expect(
        report.assessments.map((assessment) => assessment.model.id),
        <String>['catalog-first', 'catalog-second'],
      );
      expect(
        report.assessments.map((assessment) => assessment.compatibility),
        everyElement(ModelCompatibility.unknown),
      );
      expect(report.defaultModelIdForType('llm'), 'catalog-first');
      expect(
        report.assessments.first.reasons,
        contains(ModelCapabilityReason.profileUnavailable),
      );
    },
  );

  test('SDK below the supported floor is advisory-incompatible', () {
    final model = _model(id: 'sdk-model');

    final report = assessor.assess(
      catalog: <ModelCatalogEntry>[model],
      profile: _profile(supportedAbis: const <String>['arm64-v8a'], sdkInt: 23),
    );

    final assessment = report.assessments.single;
    expect(assessment.compatibility, ModelCompatibility.incompatible);
    expect(assessment.reasons, contains(ModelCapabilityReason.sdkUnsupported));
    expect(report.defaultModelIdForType('llm'), isNull);
  });
}

DeviceProfile _profile({
  required List<String> supportedAbis,
  int sdkInt = 29,
  int totalRamMb = 8192,
  int availableRamMb = 4096,
  int totalStorageMb = 128000,
  int availableStorageMb = 10000,
}) {
  return DeviceProfile(
    manufacturer: 'Huawei',
    brand: 'HUAWEI',
    model: 'SPN-AL00',
    device: 'HWSPN',
    product: 'SPN-AL00',
    sdkInt: sdkInt,
    release: '10',
    supportedAbis: supportedAbis,
    totalRamMb: totalRamMb,
    availableRamMb: availableRamMb,
    totalStorageMb: totalStorageMb,
    availableStorageMb: availableStorageMb,
  );
}

ModelCatalogEntry _model({
  required String id,
  String type = 'llm',
  int minRamMb = 2048,
  int sizeBytes = 512 * 1024 * 1024,
  List<String> supportedAbis = const <String>['arm64-v8a'],
}) {
  return ModelCatalogEntry(
    id: id,
    type: type,
    tier: 'local',
    displayName: id,
    description: 'fixture',
    sizeBytes: sizeBytes,
    minRamMb: minRamMb,
    recommendedTier: 'local',
    sources: const <ModelSourceEntry>[],
    artifacts: <ModelArtifactSpec>[
      ModelArtifactSpec(
        id: '$id-model',
        releaseId: 'release-1',
        role: 'model',
        required: true,
        relativePath: '$id.gguf',
        sizeBytes: sizeBytes,
        checksum: 'sha256:${'a' * 64}',
        origin: ModelArtifactOrigin.download,
        sources: const <ModelSourceEntry>[],
        supportedAbis: supportedAbis,
      ),
    ],
  );
}
