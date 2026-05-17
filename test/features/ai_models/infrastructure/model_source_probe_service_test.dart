import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_source_probe_service.dart';

void main() {
  Future<HttpServer> startServer(Future<void> Function(HttpRequest request) handler) {
    return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
      server.listen(handler);
      return server;
    });
  }

  test('probeSource marks source reachable from HEAD and reads content length', () async {
    final server = await startServer((request) async {
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentLengthHeader, '4096');
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    });
    addTearDown(server.close);

    final service = ModelSourceProbeService(dio: Dio(), logger: const AppLogger());
    final result = await service.probeSource(
      source: ModelSourceEntry(
        id: 'source-a',
        label: '主镜像',
        url: 'http://${server.address.host}:${server.port}/model.onnx',
        checksum: 'sha256:test',
      ),
      expectedSizeBytes: 4096,
    );

    expect(result.reachable, isTrue);
    expect(result.statusCode, 200);
    expect(result.contentLength, 4096);
    expect(result.rangeSupported, isTrue);
    expect(result.usedFallbackRangeProbe, isFalse);
  });

  test('probeSource falls back to GET range probe when HEAD is not useful', () async {
    final server = await startServer((request) async {
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-0');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/4096');
      request.response.contentLength = 1;
      request.response.add([1]);
      await request.response.close();
    });
    addTearDown(server.close);

    final service = ModelSourceProbeService(dio: Dio(), logger: const AppLogger());
    final result = await service.probeSource(
      source: ModelSourceEntry(
        id: 'source-b',
        label: '备用镜像',
        url: 'http://${server.address.host}:${server.port}/model.onnx',
        checksum: 'sha256:test',
      ),
      expectedSizeBytes: 4096,
    );

    expect(result.reachable, isTrue);
    expect(result.statusCode, 206);
    expect(result.contentLength, 4096);
    expect(result.rangeSupported, isTrue);
    expect(result.usedFallbackRangeProbe, isTrue);
  });

  test('rankSources keeps original order when probe facts tie', () {
    final results = <ModelSourceProbeResult>[
      const ModelSourceProbeResult(
        sourceId: 'source-a',
        reachable: true,
        statusCode: 200,
        contentLength: 4096,
        rangeSupported: true,
        latencyMs: 50,
        usedFallbackRangeProbe: false,
      ),
      const ModelSourceProbeResult(
        sourceId: 'source-b',
        reachable: true,
        statusCode: 200,
        contentLength: 4096,
        rangeSupported: true,
        latencyMs: 50,
        usedFallbackRangeProbe: false,
      ),
    ];

    final ranked = rankProbeResults(results);
    expect(ranked.map((item) => item.sourceId).toList(), ['source-a', 'source-b']);
  });

  test('rankSources prefers sources whose content length matches expected size', () {
    final results = <ModelSourceProbeResult>[
      const ModelSourceProbeResult(
        sourceId: 'source-a',
        reachable: true,
        statusCode: 200,
        contentLength: 2048,
        rangeSupported: true,
        latencyMs: 10,
        usedFallbackRangeProbe: false,
      ),
      const ModelSourceProbeResult(
        sourceId: 'source-b',
        reachable: true,
        statusCode: 200,
        contentLength: 4096,
        rangeSupported: false,
        latencyMs: 30,
        usedFallbackRangeProbe: false,
      ),
    ];

    final ranked = rankProbeResults(results, expectedSizeBytes: 4096);
    expect(ranked.map((item) => item.sourceId).toList(), ['source-b', 'source-a']);
  });
}
