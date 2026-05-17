import 'dart:io';

import 'package:dio/dio.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
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

List<ModelSourceProbeResult> rankProbeResults(
  List<ModelSourceProbeResult> results, {
  int? expectedSizeBytes,
}) {
  final indexed = results.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final reachableCompare = _boolPriority(right.$2.reachable) - _boolPriority(left.$2.reachable);
    if (reachableCompare != 0) {
      return reachableCompare;
    }

    final expectedSizeCompare = _boolPriority(right.$2.contentLength == expectedSizeBytes) -
        _boolPriority(left.$2.contentLength == expectedSizeBytes);
    if (expectedSizeCompare != 0) {
      return expectedSizeCompare;
    }

    final contentLengthCompare = _boolPriority(right.$2.contentLength != null) - _boolPriority(left.$2.contentLength != null);
    if (contentLengthCompare != 0) {
      return contentLengthCompare;
    }

    final rangeCompare = _boolPriority(right.$2.rangeSupported) - _boolPriority(left.$2.rangeSupported);
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

class ModelSourceProbeService {
  ModelSourceProbeService({
    required Dio dio,
    required AppLogger logger,
  })  : _dio = dio,
        _logger = logger;

  final Dio _dio;
  final AppLogger _logger;

  Future<ModelSourceProbeResult> probeSource({
    required ModelSourceEntry source,
    int? expectedSizeBytes,
  }) async {
    final startedAt = DateTime.now();
    try {
      final headResponse = await _dio.head<void>(source.url);
      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      final headers = headResponse.headers;
      final contentLength = int.tryParse(headers.value(HttpHeaders.contentLengthHeader) ?? '');
      final acceptRanges = headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();

      return ModelSourceProbeResult(
        sourceId: source.id,
        reachable: (headResponse.statusCode ?? 0) < 500,
        statusCode: headResponse.statusCode,
        contentLength: contentLength,
        rangeSupported: acceptRanges == 'bytes',
        latencyMs: latencyMs,
        usedFallbackRangeProbe: false,
      );
    } catch (error) {
      _logger.warning('HEAD probe failed for ${source.id}: $error');
    }

    final fallbackStartedAt = DateTime.now();
    try {
      final response = await _dio.get<List<int>>(
        source.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const <String, Object>{HttpHeaders.rangeHeader: 'bytes=0-0'},
        ),
      );
      final latencyMs = DateTime.now().difference(fallbackStartedAt).inMilliseconds;
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      final contentLength = _contentLengthFromContentRange(contentRange) ?? expectedSizeBytes;

      return ModelSourceProbeResult(
        sourceId: source.id,
        reachable: (response.statusCode ?? 0) < 500,
        statusCode: response.statusCode,
        contentLength: contentLength,
        rangeSupported: response.statusCode == HttpStatus.partialContent,
        latencyMs: latencyMs,
        usedFallbackRangeProbe: true,
      );
    } catch (error) {
      _logger.warning('Fallback probe failed for ${source.id}: $error');
      return ModelSourceProbeResult(
        sourceId: source.id,
        reachable: false,
        statusCode: null,
        contentLength: expectedSizeBytes,
        rangeSupported: false,
        latencyMs: null,
        usedFallbackRangeProbe: true,
      );
    }
  }

  int? _contentLengthFromContentRange(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final slashIndex = value.lastIndexOf('/');
    if (slashIndex < 0 || slashIndex == value.length - 1) {
      return null;
    }
    return int.tryParse(value.substring(slashIndex + 1));
  }
}
