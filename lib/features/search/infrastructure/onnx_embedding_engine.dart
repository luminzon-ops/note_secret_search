import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

typedef EmbeddingMetadataResolver = Future<EmbeddingModelMetadata?> Function(String modelId);

class OnnxEmbeddingEngine implements EmbeddingEngine {
  const OnnxEmbeddingEngine({
    required EmbeddingRuntimeBridge bridge,
    this.resolveMetadata,
  }) : _bridge = bridge;

  final EmbeddingRuntimeBridge _bridge;
  final EmbeddingMetadataResolver? resolveMetadata;

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
      throw StateError('Embedding metadata is missing for model ${request.model.id}.');
    }

    final result = await _bridge.embedText(
      modelId: request.model.id,
      modelPath: path,
      text: request.text,
      tokenizer: metadata.tokenizer,
      runtime: metadata.runtime,
    );

    final rawValues = (result['values'] as List<dynamic>? ?? const <dynamic>[])
        .map((value) => (value as num).toDouble())
        .toList(growable: false);

    return EmbeddingVector(
      values: rawValues,
      tokenCount: (result['tokenCount'] as num?)?.toInt() ?? request.text.length,
    );
  }

  Future<EmbeddingModelMetadata?> _resolveMetadata(String modelId) async {
    final resolver = resolveMetadata;
    if (resolver == null) {
      return null;
    }
    return resolver(modelId);
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
    'installedUnverified' || 'installed_unverified' => EmbeddingRuntimeStatus.installedUnverified,
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
