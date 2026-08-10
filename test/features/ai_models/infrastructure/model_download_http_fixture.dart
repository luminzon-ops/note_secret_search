import 'dart:convert';
import 'dart:io';

import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

class ModelDownloadHttpResponse {
  const ModelDownloadHttpResponse({
    required this.statusCode,
    this.body = const <int>[],
    this.etag,
    this.lastModified,
    this.contentRange,
    this.includeContentLength = true,
  });

  final int statusCode;
  final List<int> body;
  final String? etag;
  final String? lastModified;
  final String? contentRange;
  final bool includeContentLength;

  Future<void> writeTo(HttpResponse response) async {
    response.statusCode = statusCode;
    if (includeContentLength) {
      response.contentLength = body.length;
    } else {
      response.headers.chunkedTransferEncoding = true;
    }
    if (etag != null) {
      response.headers.set(HttpHeaders.etagHeader, etag!);
    }
    if (lastModified != null) {
      response.headers.set(HttpHeaders.lastModifiedHeader, lastModified!);
    }
    if (contentRange != null) {
      response.headers.set(HttpHeaders.contentRangeHeader, contentRange!);
    }
    response.add(body);
    await response.close();
  }
}

class ModelDownloadHttpRequest {
  const ModelDownloadHttpRequest({required this.range, required this.ifRange});

  final String? range;
  final String? ifRange;
}

class ModelDownloadHttpFixture {
  ModelDownloadHttpFixture._(this._server, this._responses);

  final HttpServer _server;
  final List<ModelDownloadHttpResponse> _responses;
  final List<ModelDownloadHttpRequest> requests = <ModelDownloadHttpRequest>[];
  Object? _handlerError;
  StackTrace? _handlerStackTrace;

  static Future<ModelDownloadHttpFixture> start(
    List<ModelDownloadHttpResponse> responses,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = ModelDownloadHttpFixture._(
      server,
      List<ModelDownloadHttpResponse>.of(responses),
    );
    server.listen(fixture._handle);
    return fixture;
  }

  Uri uri([String path = '/model.bin']) {
    return Uri(
      scheme: 'http',
      host: _server.address.host,
      port: _server.port,
      path: path,
    );
  }

  Future<void> close() async {
    await _server.close(force: true);
    final error = _handlerError;
    if (error != null) {
      Error.throwWithStackTrace(error, _handlerStackTrace!);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add(
      ModelDownloadHttpRequest(
        range: request.headers.value(HttpHeaders.rangeHeader),
        ifRange: request.headers.value(HttpHeaders.ifRangeHeader),
      ),
    );
    try {
      if (_responses.isEmpty) {
        throw StateError('No scripted response remains.');
      }
      await _responses.removeAt(0).writeTo(request.response);
    } catch (error, stackTrace) {
      _handlerError ??= error;
      _handlerStackTrace ??= stackTrace;
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
}

Future<void> seedModelDownloadPartial({
  required ModelDownloadStagingTarget target,
  required List<int> bytes,
  required String sourceUrl,
  required String expectedChecksum,
  required int? totalBytes,
  String? modelId,
  String? operationId,
  String? artifactId,
  int? expectedSizeBytes,
  String? etag,
  String? lastModified,
}) async {
  final partial = File(target.stagingPath);
  await partial.parent.create(recursive: true);
  await partial.writeAsBytes(bytes);
  await File(target.metadataPath).writeAsString(
    jsonEncode(<String, Object?>{
      'version': operationId == null ? 1 : 2,
      'modelId': modelId,
      'operationId': operationId,
      'artifactId': artifactId,
      'sourceUrl': sourceUrl,
      'expectedChecksum': expectedChecksum,
      'totalBytes': totalBytes,
      'expectedSizeBytes': expectedSizeBytes,
      'etag': etag,
      'lastModified': lastModified,
    }),
    flush: true,
  );
}
