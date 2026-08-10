import 'dart:io';

import 'package:dio/dio.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_source_probe.dart';

export 'package:note_secret_search/features/ai_models/domain/model_source_probe.dart';

class ModelSourceProbeService implements ModelSourceProbe {
  ModelSourceProbeService({required Dio dio, required AppLogger logger})
    : _dio = dio,
      _logger = logger;

  final Dio _dio;
  final AppLogger _logger;

  @override
  Future<ModelSourceProbeResult> probeSource({
    required ModelSourceEntry source,
    int? expectedSizeBytes,
  }) async {
    final startedAt = DateTime.now();
    try {
      final headResponse = await _dio.head<void>(source.url);
      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      final headers = headResponse.headers;
      final contentLength = int.tryParse(
        headers.value(HttpHeaders.contentLengthHeader) ?? '',
      );
      final acceptRanges = headers
          .value(HttpHeaders.acceptRangesHeader)
          ?.toLowerCase();

      return ModelSourceProbeResult(
        sourceId: source.id,
        reachable: (headResponse.statusCode ?? 0) < 500,
        statusCode: headResponse.statusCode,
        contentLength: contentLength,
        rangeSupported: acceptRanges == 'bytes',
        latencyMs: latencyMs,
        usedFallbackRangeProbe: false,
      );
    } catch (_) {
      _logger.warning('model_source_head_probe_failed');
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
      final latencyMs = DateTime.now()
          .difference(fallbackStartedAt)
          .inMilliseconds;
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      final contentLength =
          _contentLengthFromContentRange(contentRange) ?? expectedSizeBytes;

      return ModelSourceProbeResult(
        sourceId: source.id,
        reachable: (response.statusCode ?? 0) < 500,
        statusCode: response.statusCode,
        contentLength: contentLength,
        rangeSupported: response.statusCode == HttpStatus.partialContent,
        latencyMs: latencyMs,
        usedFallbackRangeProbe: true,
      );
    } catch (_) {
      _logger.warning('model_source_range_probe_failed');
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
