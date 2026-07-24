import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

class DeviceProfile {
  const DeviceProfile({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.device,
    required this.product,
    required this.sdkInt,
    required this.release,
    required this.supportedAbis,
    required this.totalRamMb,
    required this.availableRamMb,
    required this.totalStorageMb,
    required this.availableStorageMb,
  });

  factory DeviceProfile.fromPlatformMap(Map<String, Object?> value) {
    final legacyAbi = _readString(value['cpuAbi']);
    final abis = _readStringList(value['supportedAbis']);
    final supportedAbis = abis.isNotEmpty
        ? abis
        : (legacyAbi == null ? const <String>[] : <String>[legacyAbi]);
    return DeviceProfile(
      manufacturer: _readString(value['manufacturer']) ?? 'unknown',
      brand: _readString(value['brand']) ?? 'unknown',
      model: _readString(value['model']) ?? 'unknown',
      device: _readString(value['device']) ?? 'unknown',
      product: _readString(value['product']) ?? 'unknown',
      sdkInt: _readInt(value['sdkInt'], fallback: -1),
      release: _readString(value['release']) ?? 'unknown',
      supportedAbis: List<String>.unmodifiable(supportedAbis),
      totalRamMb: _readInt(value['totalRamMb']),
      availableRamMb: _readInt(value['availableRamMb']),
      totalStorageMb: _readInt(value['totalStorageMb']),
      availableStorageMb: _readInt(value['availableStorageMb']),
    );
  }

  final String manufacturer;
  final String brand;
  final String model;
  final String device;
  final String product;
  final int sdkInt;
  final String release;
  final List<String> supportedAbis;
  final int totalRamMb;
  final int availableRamMb;
  final int totalStorageMb;
  final int availableStorageMb;

  String get cpuAbi => supportedAbis.isEmpty ? 'unknown' : supportedAbis.first;

  String get cpuDisplay =>
      supportedAbis.isEmpty ? 'unknown' : supportedAbis.join(', ');

  String get ramDisplay => '${(totalRamMb / 1024).toStringAsFixed(1)} GB';

  String get storageDisplay =>
      '${(totalStorageMb / 1024).toStringAsFixed(0)} GB';

  String get osDisplay => 'Android $release (SDK $sdkInt)';

  /// Kept as a display compatibility getter; it is derived in Dart.
  String get tier {
    if (totalRamMb >= 8192) {
      return 'high';
    }
    if (totalRamMb >= 4096) {
      return 'mid';
    }
    return 'low';
  }
}

enum ModelCompatibility { compatible, constrained, incompatible, unknown }

enum ModelCapabilityReason {
  profileUnavailable,
  sdkUnsupported,
  abiUnavailable,
  abiUnsupported,
  totalRamUnavailable,
  totalRamInsufficient,
  availableRamConstrained,
  storageUnavailable,
  storageInsufficient,
  storageConstrained,
  compatibleByProfile,
}

/// Advisory output only. It intentionally has no runtime readiness or enabled
/// state; native runtime validation remains authoritative.
class ModelCapabilityAssessment {
  const ModelCapabilityAssessment({
    required this.model,
    required this.compatibility,
    required this.reasons,
    required this.explanation,
    this.isDefaultRecommendation = false,
  });

  final ModelCatalogEntry model;
  final ModelCompatibility compatibility;
  final List<ModelCapabilityReason> reasons;
  final String explanation;
  final bool isDefaultRecommendation;

  ModelCapabilityAssessment withDefaultRecommendation(
    bool isDefaultRecommendation,
  ) {
    return ModelCapabilityAssessment(
      model: model,
      compatibility: compatibility,
      reasons: reasons,
      explanation: explanation,
      isDefaultRecommendation: isDefaultRecommendation,
    );
  }
}

class DeviceCapabilityReport {
  DeviceCapabilityReport({
    required List<ModelCapabilityAssessment> assessments,
    required Map<String, String> defaultRecommendationsByType,
  }) : assessments = List<ModelCapabilityAssessment>.unmodifiable(assessments),
       defaultRecommendationsByType = Map<String, String>.unmodifiable(
         defaultRecommendationsByType,
       );

  final List<ModelCapabilityAssessment> assessments;
  final Map<String, String> defaultRecommendationsByType;

  String? defaultModelIdForType(String type) =>
      defaultRecommendationsByType[type];

  ModelCapabilityAssessment? maybeAssessmentFor(String modelId) {
    for (final assessment in assessments) {
      if (assessment.model.id == modelId) {
        return assessment;
      }
    }
    return null;
  }

  ModelCapabilityAssessment assessmentFor(String modelId) {
    final assessment = maybeAssessmentFor(modelId);
    if (assessment != null) {
      return assessment;
    }
    throw ArgumentError.value(modelId, 'modelId', 'Model was not assessed');
  }
}

class DeviceCapabilityAssessor {
  const DeviceCapabilityAssessor({
    this.minimumSdkInt = 24,
    this.storageHeadroomMultiplier = 2,
  });

  static const int _mebibyte = 1024 * 1024;

  final int minimumSdkInt;
  final int storageHeadroomMultiplier;

  DeviceCapabilityReport assess({
    required List<ModelCatalogEntry> catalog,
    required DeviceProfile? profile,
  }) {
    final assessments = <ModelCapabilityAssessment>[
      for (final model in catalog) _assessModel(model, profile),
    ];
    final defaults = <String, String>{};
    final groupedIndexes = <String, List<int>>{};

    for (var index = 0; index < assessments.length; index += 1) {
      groupedIndexes
          .putIfAbsent(assessments[index].model.type, () => <int>[])
          .add(index);
    }

    for (final group in groupedIndexes.entries) {
      int? selectedIndex;
      var selectedRank = 999;
      for (final index in group.value) {
        final assessment = assessments[index];
        if (assessment.compatibility == ModelCompatibility.incompatible) {
          continue;
        }
        final rank = _compatibilityRank(assessment.compatibility);
        if (rank < selectedRank) {
          selectedIndex = index;
          selectedRank = rank;
        }
      }
      if (selectedIndex != null) {
        defaults[group.key] = assessments[selectedIndex].model.id;
        assessments[selectedIndex] = assessments[selectedIndex]
            .withDefaultRecommendation(true);
      }
    }

    return DeviceCapabilityReport(
      assessments: assessments,
      defaultRecommendationsByType: defaults,
    );
  }

  ModelCapabilityAssessment _assessModel(
    ModelCatalogEntry model,
    DeviceProfile? profile,
  ) {
    if (profile == null) {
      return ModelCapabilityAssessment(
        model: model,
        compatibility: ModelCompatibility.unknown,
        reasons: const <ModelCapabilityReason>[
          ModelCapabilityReason.profileUnavailable,
        ],
        explanation: '设备资料暂不可用，保留 catalog 顺序；仍需通过运行时加载校验。',
      );
    }

    final reasons = <ModelCapabilityReason>[];
    var hardFailure = false;
    var constrained = false;
    var unknown = false;

    if (profile.sdkInt < 0) {
      unknown = true;
    } else if (profile.sdkInt < minimumSdkInt) {
      hardFailure = true;
      reasons.add(ModelCapabilityReason.sdkUnsupported);
    }

    final constrainedArtifacts = model.artifacts
        .where(
          (artifact) => artifact.required && artifact.supportedAbis.isNotEmpty,
        )
        .toList(growable: false);
    if (constrainedArtifacts.isNotEmpty) {
      final deviceAbis = profile.supportedAbis
          .map((abi) => abi.trim().toLowerCase())
          .where((abi) => abi.isNotEmpty)
          .toSet();
      if (deviceAbis.isEmpty) {
        unknown = true;
        reasons.add(ModelCapabilityReason.abiUnavailable);
      } else if (constrainedArtifacts.any(
        (artifact) => !artifact.supportedAbis.any(
          (abi) => deviceAbis.contains(abi.toLowerCase()),
        ),
      )) {
        hardFailure = true;
        reasons.add(ModelCapabilityReason.abiUnsupported);
      }
    }

    if (profile.totalRamMb <= 0) {
      unknown = true;
      reasons.add(ModelCapabilityReason.totalRamUnavailable);
    } else if (profile.totalRamMb < model.minRamMb) {
      hardFailure = true;
      reasons.add(ModelCapabilityReason.totalRamInsufficient);
    } else if (profile.availableRamMb > 0 &&
        profile.availableRamMb * 2 < model.minRamMb) {
      constrained = true;
      reasons.add(ModelCapabilityReason.availableRamConstrained);
    }

    final requiredStorageMb = _requiredStorageMb(model);
    if (profile.availableStorageMb <= 0) {
      unknown = true;
      reasons.add(ModelCapabilityReason.storageUnavailable);
    } else if (profile.availableStorageMb < requiredStorageMb) {
      hardFailure = true;
      reasons.add(ModelCapabilityReason.storageInsufficient);
    } else if (profile.availableStorageMb <
        requiredStorageMb * storageHeadroomMultiplier) {
      constrained = true;
      reasons.add(ModelCapabilityReason.storageConstrained);
    }

    if (hardFailure) {
      return ModelCapabilityAssessment(
        model: model,
        compatibility: ModelCompatibility.incompatible,
        reasons: List<ModelCapabilityReason>.unmodifiable(reasons),
        explanation: _explanation(ModelCompatibility.incompatible, reasons),
      );
    }
    if (unknown) {
      return ModelCapabilityAssessment(
        model: model,
        compatibility: ModelCompatibility.unknown,
        reasons: List<ModelCapabilityReason>.unmodifiable(reasons),
        explanation: _explanation(ModelCompatibility.unknown, reasons),
      );
    }
    if (constrained) {
      return ModelCapabilityAssessment(
        model: model,
        compatibility: ModelCompatibility.constrained,
        reasons: List<ModelCapabilityReason>.unmodifiable(reasons),
        explanation: _explanation(ModelCompatibility.constrained, reasons),
      );
    }

    reasons.add(ModelCapabilityReason.compatibleByProfile);
    return ModelCapabilityAssessment(
      model: model,
      compatibility: ModelCompatibility.compatible,
      reasons: List<ModelCapabilityReason>.unmodifiable(reasons),
      explanation: _explanation(ModelCompatibility.compatible, reasons),
    );
  }

  int _requiredStorageMb(ModelCatalogEntry model) {
    var bytes = 0;
    final requiredArtifacts = model.artifacts
        .where((artifact) => artifact.required)
        .toList(growable: false);
    if (requiredArtifacts.isEmpty) {
      bytes = model.sizeBytes;
    } else {
      for (final artifact in requiredArtifacts) {
        bytes += artifact.sizeBytes;
      }
    }
    if (bytes <= 0) {
      return 0;
    }
    return (bytes + _mebibyte - 1) ~/ _mebibyte;
  }

  int _compatibilityRank(ModelCompatibility compatibility) {
    return switch (compatibility) {
      ModelCompatibility.compatible => 0,
      ModelCompatibility.constrained => 1,
      ModelCompatibility.unknown => 2,
      ModelCompatibility.incompatible => 3,
    };
  }

  String _explanation(
    ModelCompatibility compatibility,
    List<ModelCapabilityReason> reasons,
  ) {
    final detail = reasons.map(_reasonMessage).join(' ');
    final prefix = switch (compatibility) {
      ModelCompatibility.compatible => '设备资料满足 catalog 的资源与 ABI 建议。',
      ModelCompatibility.constrained => '设备资料显示资源余量有限。',
      ModelCompatibility.incompatible => '设备资料与 catalog 约束不匹配。',
      ModelCompatibility.unknown => '设备资料不完整，无法形成确定的兼容性判断。',
    };
    return '$prefix $detail 仍需通过运行时加载校验。';
  }

  String _reasonMessage(ModelCapabilityReason reason) {
    return switch (reason) {
      ModelCapabilityReason.profileUnavailable => 'profile 缺失。',
      ModelCapabilityReason.sdkUnsupported => 'SDK 低于应用支持下限。',
      ModelCapabilityReason.abiUnavailable => 'supported ABI 资料缺失。',
      ModelCapabilityReason.abiUnsupported => '没有匹配的 runtime ABI。',
      ModelCapabilityReason.totalRamUnavailable => '总内存资料缺失。',
      ModelCapabilityReason.totalRamInsufficient => '总内存低于模型最低建议。',
      ModelCapabilityReason.availableRamConstrained => '当前可用内存偏低。',
      ModelCapabilityReason.storageUnavailable => '可用存储资料缺失。',
      ModelCapabilityReason.storageInsufficient => '可用存储不足以容纳必需 artifact。',
      ModelCapabilityReason.storageConstrained => '安装后存储余量有限。',
      ModelCapabilityReason.compatibleByProfile =>
        'ABI、SDK、内存和存储条件通过 advisory 检查。',
    };
  }
}

String? _readString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

int _readInt(Object? value, {int fallback = 0}) {
  return value is num ? value.toInt() : fallback;
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final result = <String>[];
  final seen = <String>{};
  for (final item in value) {
    final normalized = _readString(item);
    if (normalized != null && seen.add(normalized)) {
      result.add(normalized);
    }
  }
  return result;
}
