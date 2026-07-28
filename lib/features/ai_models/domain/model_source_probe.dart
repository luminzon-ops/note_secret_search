import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

class ModelSourceProbeResult {
  const ModelSourceProbeResult({
    required this.sourceId,
    required this.reachable,
    required this.statusCode,
    required this.contentLength,
    required this.rangeSupported,
    required this.latencyMs,
    required this.usedFallbackRangeProbe,
  });

  final String sourceId;
  final bool reachable;
  final int? statusCode;
  final int? contentLength;
  final bool rangeSupported;
  final int? latencyMs;
  final bool usedFallbackRangeProbe;
}

abstract interface class ModelSourceProbe {
  Future<ModelSourceProbeResult> probeSource({
    required ModelSourceEntry source,
    int? expectedSizeBytes,
  });
}

List<ModelSourceProbeResult> rankProbeResults(
  List<ModelSourceProbeResult> results, {
  int? expectedSizeBytes,
}) {
  final indexed = results.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final reachableCompare =
        _boolPriority(right.$2.reachable) - _boolPriority(left.$2.reachable);
    if (reachableCompare != 0) {
      return reachableCompare;
    }

    final expectedSizeCompare =
        _boolPriority(right.$2.contentLength == expectedSizeBytes) -
        _boolPriority(left.$2.contentLength == expectedSizeBytes);
    if (expectedSizeCompare != 0) {
      return expectedSizeCompare;
    }

    final contentLengthCompare =
        _boolPriority(right.$2.contentLength != null) -
        _boolPriority(left.$2.contentLength != null);
    if (contentLengthCompare != 0) {
      return contentLengthCompare;
    }

    final rangeCompare =
        _boolPriority(right.$2.rangeSupported) -
        _boolPriority(left.$2.rangeSupported);
    if (rangeCompare != 0) {
      return rangeCompare;
    }

    final leftLatency = left.$2.latencyMs ?? 1 << 30;
    final rightLatency = right.$2.latencyMs ?? 1 << 30;
    if (leftLatency != rightLatency) {
      return leftLatency.compareTo(rightLatency);
    }

    return left.$1.compareTo(right.$1);
  });
  return indexed.map((item) => item.$2).toList(growable: false);
}

int _boolPriority(bool value) => value ? 1 : 0;
