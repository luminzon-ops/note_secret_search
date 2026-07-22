import 'dart:async';

import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

typedef EmbeddingMetadataResolver =
    Future<EmbeddingModelMetadata?> Function(String modelId);
typedef EmbeddingRequestIdFactory = String Function();

class OnnxEmbeddingEngine implements EmbeddingEngine {
  const OnnxEmbeddingEngine({
    required EmbeddingRuntimeBridge bridge,
    this.resolveMetadata,
    this.requestIdFactory,
  }) : _bridge = bridge;

  final EmbeddingRuntimeBridge _bridge;
  final EmbeddingMetadataResolver? resolveMetadata;
  final EmbeddingRequestIdFactory? requestIdFactory;
  static int _requestSequence = 0;

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    final path = model.localPath;
    if (path == null || path.trim().isEmpty) {
      return const EmbeddingEngineState(
        ready: false,
        reason: '尚未配置本地 embedding 模型文件。',
        status: EmbeddingRuntimeStatus.notInstalled,
      );
    }

    final metadata = await _resolveMetadata(model.id);
    if (metadata == null) {
      return const EmbeddingEngineState(
        ready: false,
        reason: '当前 embedding model metadata 缺失，无法完成标准 ONNX runtime 校验。',
        status: EmbeddingRuntimeStatus.degraded,
      );
    }

    final result = await _bridge.inspectModel(
      modelId: model.id,
      modelPath: path,
      tokenizer: metadata.tokenizer,
      runtime: metadata.runtime,
      verifiedChecksum: model.checksum,
    );
    return mapEmbeddingEngineState(result, fallbackPath: path);
  }

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    final path = request.model.localPath;
    if (path == null || path.trim().isEmpty) {
      throw StateError('Active embedding model path is missing.');
    }

    final metadata = await _resolveMetadata(request.model.id);
    if (metadata == null) {
      throw StateError(
        'Embedding metadata is missing for model ${request.model.id}.',
      );
    }
    final verifiedChecksum = request.model.checksum?.trim() ?? '';
    if (verifiedChecksum.isEmpty) {
      throw EmbeddingRuntimeException(
        code: 'INVALID_ARGUMENT',
        stage: 'argument',
        modelId: request.model.id,
      );
    }

    final cancellation = request.cancellationToken;
    if (cancellation.isCancelled) {
      throw EmbeddingRuntimeCancelledException(
        stage: 'queue',
        modelId: request.model.id,
      );
    }
    final requestId = requestIdFactory?.call() ?? _nextRequestId();
    final cancellationRegistration = cancellation.register(() {
      unawaited(_bridge.cancelRequest(requestId: requestId).catchError((_) {}));
    });
    if (cancellation.isCancelled) {
      cancellationRegistration.dispose();
      throw EmbeddingRuntimeCancelledException(
        stage: 'queue',
        modelId: request.model.id,
      );
    }
    late final Map<String, dynamic> result;
    try {
      result = await _bridge.embedText(
        modelId: request.model.id,
        modelPath: path,
        text: request.text,
        tokenizer: metadata.tokenizer,
        runtime: metadata.runtime,
        verifiedChecksum: verifiedChecksum,
        requestId: requestId,
      );
      if (cancellation.isCancelled) {
        throw EmbeddingRuntimeCancelledException(
          stage: 'inference',
          modelId: request.model.id,
        );
      }
    } finally {
      cancellationRegistration.dispose();
    }

    final values = result['values'];
    if (values is! List || values.isEmpty) {
      throw _invalidOutput(request.model.id);
    }
    final rawValues = <double>[];
    for (final value in values) {
      if (value is! num) {
        throw _invalidOutput(request.model.id);
      }
      final numericValue = value.toDouble();
      if (!numericValue.isFinite) {
        throw _invalidOutput(request.model.id);
      }
      rawValues.add(numericValue);
    }
    final vectorDimension = result['vectorDimension'];
    if (vectorDimension is! num ||
        vectorDimension.toInt() != rawValues.length ||
        vectorDimension.toInt() <= 0) {
      throw _invalidOutput(request.model.id);
    }

    return EmbeddingVector(
      values: List<double>.unmodifiable(rawValues),
      tokenCount:
          (result['tokenCount'] as num?)?.toInt() ?? request.text.length,
    );
  }

  Future<EmbeddingModelMetadata?> _resolveMetadata(String modelId) async {
    final resolver = resolveMetadata;
    if (resolver == null) {
      return null;
    }
    return resolver(modelId);
  }

  static String _nextRequestId() {
    _requestSequence += 1;
    return 'embedding-request-$_requestSequence';
  }

  static EmbeddingRuntimeException _invalidOutput(String modelId) {
    return EmbeddingRuntimeException(
      code: 'INVALID_OUTPUT',
      stage: 'output',
      modelId: modelId,
    );
  }
}

EmbeddingEngineState mapEmbeddingEngineState(
  Map<String, dynamic> payload, {
  String? fallbackPath,
}) {
  final rawStatus = payload['status'] as String? ?? 'degraded';
  final status = switch (rawStatus) {
    'notInstalled' || 'not_installed' => EmbeddingRuntimeStatus.notInstalled,
    'missing' => EmbeddingRuntimeStatus.missing,
    'corrupted' => EmbeddingRuntimeStatus.corrupted,
    'installedUnverified' ||
    'installed_unverified' => EmbeddingRuntimeStatus.installedUnverified,
    'ready' => EmbeddingRuntimeStatus.ready,
    'degraded' => EmbeddingRuntimeStatus.degraded,
    _ => EmbeddingRuntimeStatus.degraded,
  };

  return EmbeddingEngineState(
    ready: status == EmbeddingRuntimeStatus.ready,
    reason: payload['reason'] as String? ?? '当前 embedding runtime 未就绪。',
    status: status,
    vectorDimension: (payload['vectorDimension'] as num?)?.toInt(),
    modelPath: payload['modelPath'] as String? ?? fallbackPath,
    checkedAt: _parseCheckedAt(payload['checkedAt']),
  );
}

DateTime? _parseCheckedAt(Object? raw) {
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  return null;
}
