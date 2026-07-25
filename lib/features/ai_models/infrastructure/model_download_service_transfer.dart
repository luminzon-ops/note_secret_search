part of 'model_download_service.dart';

extension _ModelDownloadServiceTransfer on ModelDownloadService {
  Future<ModelDownloadResult> _run(
    _Job job, {
    required bool installOnSuccess,
  }) async {
    final files = _Files(job.target);
    final token = CancelToken();
    _cancelTokens[job.taskId] = token;
    final startedAt = DateTime.now();
    var resumed = false;
    var restarted = false;
    _Validator? validator;
    int? total;

    try {
      await files.partial.parent.create(recursive: true);
      if (job.resumeFromBytes > 0) {
        if (installOnSuccess) {
          await _copyLegacy(files);
        }
      } else {
        await _clear(files);
      }
      final partialLength = await _length(files.partial);
      if (job.resumeFromBytes > 0 && partialLength > 0) {
        final state = await _readState(files.metadata);
        if (state != null && state.matches(job) && state.validator.resumable) {
          final offset = job.resumeFromBytes < partialLength
              ? job.resumeFromBytes
              : partialLength;
          await _truncate(files.partial, offset);
          final response = await _get(
            job.sourceUrl,
            token,
            rangeStart: offset,
            ifRange: state.validator.ifRange,
          );
          final range = _contentRange(response);
          final responseValidator = _validator(response);
          if (_validPartial(
            response,
            range,
            offset,
            state,
            responseValidator,
            job.expectedSizeBytes,
          )) {
            final acceptedRange = range!;
            total = acceptedRange.total;
            validator = responseValidator;
            await _writeState(
              files.metadata,
              _State(
                modelId: job.modelId,
                operationId: job.operationId,
                artifactId: job.artifactId,
                sourceUrl: job.sourceUrl,
                checksum: job.checksum,
                totalBytes: total,
                expectedSizeBytes: job.expectedSizeBytes,
                validator: validator,
              ),
            );
            try {
              await _write(
                response,
                files.partial,
                job,
                startedAt,
                append: true,
                offset: offset,
                total: total,
                bodySize: acceptedRange.end - acceptedRange.start + 1,
                validator: validator,
              );
              await _checkSize(files.partial, total);
              resumed = true;
            } on _DownloadIntegrityException {
              await _clear(files);
              restarted = true;
            }
          } else {
            await _discard(response);
            await _clear(files);
            restarted = true;
          }
        } else {
          await _clear(files);
          restarted = true;
        }
      }

      if (!resumed) {
        await _clear(files);
        if (restarted) {
          await Future.sync(
            () => job.onProgress(
              ModelDownloadProgress(
                receivedBytes: 0,
                totalBytes: job.expectedSizeBytes,
                averageSpeedBytesPerSecond: null,
                resumable: false,
                restarted: true,
              ),
            ),
          );
        }
        final full = await _full(job, files, token, startedAt);
        total = full.total;
        validator = full.validator;
      }

      String checksum;
      try {
        await _checkSize(files.partial, job.expectedSizeBytes ?? total);
        checksum = await verifyChecksum(
          filePath: files.partial.path,
          expectedChecksum: job.checksum,
        );
      } on Object {
        await _clear(files);
        rethrow;
      }
      if (installOnSuccess) {
        await _install(files);
        await _delete(files.metadata);
      }
      _logger.info('model_download_completed');
      final completedFile = installOnSuccess ? files.finalFile : files.partial;
      return ModelDownloadResult(
        localPath: completedFile.path,
        totalBytes: await completedFile.length(),
        verifiedChecksum: checksum,
        resumed: resumed,
        fellBackToRestart: restarted,
        resumable: validator?.resumable ?? false,
        etag: validator?.etag,
        lastModified: validator?.lastModified,
      );
    } on _DownloadIntegrityException {
      await _clear(files);
      rethrow;
    } finally {
      if (identical(_cancelTokens[job.taskId], token)) {
        _cancelTokens.remove(job.taskId);
      }
    }
  }

  Future<({int? total, _Validator validator})> _full(
    _Job job,
    _Files files,
    CancelToken token,
    DateTime startedAt,
  ) async {
    final response = await _get(job.sourceUrl, token);
    if (response.statusCode != HttpStatus.ok) {
      await _discard(response);
      throw StateError('Expected HTTP 200, got ${response.statusCode}.');
    }
    final responseTotal = _bodyLength(response);
    if (job.expectedSizeBytes != null &&
        responseTotal != null &&
        responseTotal != job.expectedSizeBytes) {
      await _discard(response);
      throw _DownloadIntegrityException('Signed artifact size mismatch.');
    }
    final total = job.expectedSizeBytes ?? responseTotal;
    final validator = _validator(response);
    await _writeState(
      files.metadata,
      _State(
        modelId: job.modelId,
        operationId: job.operationId,
        artifactId: job.artifactId,
        sourceUrl: job.sourceUrl,
        checksum: job.checksum,
        totalBytes: total,
        expectedSizeBytes: job.expectedSizeBytes,
        validator: validator,
      ),
    );
    await _write(
      response,
      files.partial,
      job,
      startedAt,
      append: false,
      offset: 0,
      total: total,
      bodySize: total,
      validator: validator,
    );
    await _checkSize(files.partial, total);
    return (total: total, validator: validator);
  }

  Future<Response<ResponseBody>> _get(
    String url,
    CancelToken token, {
    int? rangeStart,
    String? ifRange,
  }) {
    final headers = <String, Object>{
      HttpHeaders.acceptEncodingHeader: 'identity',
      if (rangeStart != null) HttpHeaders.rangeHeader: 'bytes=$rangeStart-',
      if (rangeStart != null && ifRange != null)
        HttpHeaders.ifRangeHeader: ifRange,
    };
    return _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        validateStatus: (status) =>
            status == HttpStatus.ok ||
            status == HttpStatus.partialContent ||
            status == HttpStatus.preconditionFailed ||
            status == HttpStatus.requestedRangeNotSatisfiable,
      ),
    );
  }

  bool _validPartial(
    Response<ResponseBody> response,
    ({int start, int end, int total})? range,
    int offset,
    _State state,
    _Validator validator,
    int? expectedSizeBytes,
  ) {
    if (response.statusCode != HttpStatus.partialContent ||
        range == null ||
        range.start != offset ||
        range.end >= range.total ||
        (state.expectedSizeBytes != null &&
            state.expectedSizeBytes != range.total) ||
        (expectedSizeBytes != null && expectedSizeBytes != range.total) ||
        (state.totalBytes != null && state.totalBytes != range.total) ||
        !_sameValidator(state.validator, validator)) {
      return false;
    }
    final bodyLength = _bodyLength(response);
    return bodyLength == null || bodyLength == range.end - range.start + 1;
  }

  Future<void> _write(
    Response<ResponseBody> response,
    File file,
    _Job job,
    DateTime startedAt, {
    required bool append,
    required int offset,
    required int? total,
    required int? bodySize,
    required _Validator validator,
  }) async {
    final body = response.data;
    if (body == null) {
      throw _DownloadIntegrityException('Empty response body.');
    }
    final sink = file.openWrite(
      mode: append ? FileMode.append : FileMode.writeOnly,
    );
    var received = 0;
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        final current = offset + received;
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        await Future.sync(
          () => job.onProgress(
            ModelDownloadProgress(
              receivedBytes: current,
              totalBytes: total,
              averageSpeedBytesPerSecond: elapsed <= 0
                  ? null
                  : current * 1000 / elapsed,
              etag: validator.etag,
              lastModified: validator.lastModified,
              resumable: validator.resumable,
            ),
          ),
        );
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (bodySize != null && bodySize != received) {
      throw _DownloadIntegrityException('HTTP body length mismatch.');
    }
  }

  Future<ModelDownloadStagingTarget> _resolveTarget({
    required String modelId,
    required String sourceUrl,
    required bool createParent,
  }) async {
    _validateModelId(modelId);
    final root = await _applicationSupportDirectoryProvider();
    final modelDir = Directory(p.join(root.path, 'models', modelId));
    if (createParent) {
      await modelDir.create(recursive: true);
    }
    final filePart = p.basename(Uri.parse(sourceUrl).path);
    final fileName = _sanitizeFileName(
      filePart.isEmpty ? '$modelId.bin' : filePart,
    );
    final sourceKey = sha256
        .convert(utf8.encode(sourceUrl))
        .toString()
        .substring(0, 16);
    final stagingDir = p.join(modelDir.path, '.staging', sourceKey);
    return ModelDownloadStagingTarget(
      localPath: p.join(modelDir.path, fileName),
      stagingPath: p.join(stagingDir, '$fileName.part'),
      metadataPath: p.join(stagingDir, '$fileName.json'),
    );
  }

  Future<_State?> _readState(File file) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic> ? _State.fromJson(value) : null;
    } on Object {
      return null;
    }
  }

  Future<void> _writeState(File file, _State state) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await _delete(temporary);
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    await _delete(file);
    await temporary.rename(file.path);
  }

  Future<void> _copyLegacy(_Files files) async {
    if (!await files.partial.exists() && await files.finalFile.exists()) {
      await files.partial.parent.create(recursive: true);
      await files.finalFile.copy(files.partial.path);
    }
  }

  Future<void> _install(_Files files) async {
    await files.finalFile.parent.create(recursive: true);
    final backup = File('${files.finalFile.path}.previous');
    await _delete(backup);
    var backedUp = false;
    try {
      if (await files.finalFile.exists()) {
        await files.finalFile.rename(backup.path);
        backedUp = true;
      }
      await files.partial.rename(files.finalFile.path);
      await _delete(backup);
    } catch (_) {
      if (backedUp &&
          !await files.finalFile.exists() &&
          await backup.exists()) {
        await backup.rename(files.finalFile.path);
      }
      rethrow;
    }
  }

  Future<void> _clear(_Files files) async {
    await _delete(files.partial);
    await _delete(files.metadata);
  }

  Future<void> _delete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> _length(File file) async {
    return await file.exists() ? file.length() : 0;
  }

  Future<void> _truncate(File file, int length) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.truncate(length);
    } finally {
      await handle.close();
    }
  }

  Future<void> _checkSize(File file, int? expected) async {
    if (expected != null && await file.length() != expected) {
      throw _DownloadIntegrityException('Downloaded file size mismatch.');
    }
  }

  Future<void> _discard(Response<ResponseBody> response) async {
    try {
      await for (final _ in response.data?.stream ?? const Stream.empty()) {}
    } on Object {
      // The next request starts from a clean response.
    }
  }

  _Validator _validator(Response<ResponseBody> response) => _Validator(
    etag: response.headers.value(HttpHeaders.etagHeader),
    lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
  );

  int? _bodyLength(Response<ResponseBody> response) {
    final header = int.tryParse(
      response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    if (header != null && header >= 0) {
      return header;
    }
    final bodyLength = response.data?.contentLength;
    return bodyLength != null && bodyLength >= 0 ? bodyLength : null;
  }

  ({int start, int end, int total})? _contentRange(
    Response<ResponseBody> response,
  ) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null
        ? null
        : RegExp(
            r'^bytes\s+(\d+)-(\d+)/(\d+)$',
            caseSensitive: false,
          ).firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    return start == null || end == null || total == null || end < start
        ? null
        : (start: start, end: end, total: total);
  }

  bool _sameValidator(_Validator expected, _Validator actual) {
    if (_strongEtag(expected.etag)) {
      return actual.etag?.trim() == expected.etag?.trim();
    }
    final date = expected.lastModified?.trim();
    return _validHttpDate(date) && actual.lastModified?.trim() == date;
  }

  String _normalizeChecksum(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(normalized)) {
      throw StateError('Unsupported checksum format: $value');
    }
    return normalized;
  }

  String _sanitizeFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'artifact.bin' : safe;
  }

  void _validateModelId(String modelId) {
    if (modelId.isEmpty ||
        modelId.trim() != modelId ||
        modelId == '.' ||
        modelId == '..' ||
        p.basename(modelId) != modelId) {
      throw ArgumentError.value(modelId, 'modelId', 'Invalid model id.');
    }
  }

  void _validateIdentifier(String value, String name) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value) ||
        value == '.' ||
        value == '..') {
      throw ArgumentError.value(value, name, 'Invalid identifier.');
    }
  }
}
