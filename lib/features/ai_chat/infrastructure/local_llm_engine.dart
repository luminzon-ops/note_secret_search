import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

class LocalLlmEngine implements LlmEngine {
  const LocalLlmEngine({required LlmRuntimeBridge bridge}) : _bridge = bridge;

  final LlmRuntimeBridge _bridge;

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) async {
    final path = model.localPath;
    if (path == null || path.trim().isEmpty) {
      return const LlmRuntimeState(
        ready: false,
        reason: '尚未配置本地 LLM 模型文件。',
        status: LlmRuntimeStatus.notInstalled,
      );
    }

    final result = await _bridge.ensureModelReady(modelId: model.id, modelPath: path);
    return mapLlmRuntimeState(result, fallbackPath: path);
  }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    final path = request.model.localPath;
    if (path == null || path.trim().isEmpty) {
      throw StateError('Active local LLM model path is missing.');
    }

    final result = await _bridge.generateText(
      modelId: request.model.id,
      modelPath: path,
      prompt: request.prompt,
      usedPrivateContext: request.usedPrivateContext,
      maxOutputTokens: request.maxOutputTokens,
      maxPromptChars: request.maxPromptChars,
      contextLength: request.contextLength,
      conservativeMode: request.conservativeMode,
      temperature: request.temperature,
      topK: request.topK,
      topP: request.topP,
      seed: request.seed,
      stopSequences: request.stopSequences,
    );

    return LlmInferenceResponse(
      text: result['text'] as String? ?? '',
      finishReason: result['finishReason'] as String? ?? 'unknown',
      usedPrivateContext: result['usedPrivateContext'] as bool? ?? request.usedPrivateContext,
    );
  }

  @override
  Future<void> releaseModel(String modelId) => _bridge.releaseModel(modelId: modelId);
}

LlmRuntimeState mapLlmRuntimeState(
  Map<String, dynamic> payload, {
  String? fallbackPath,
}) {
  final rawStatus = payload['status'] as String? ?? 'degraded';
  final status = switch (rawStatus) {
    'notInstalled' || 'not_installed' => LlmRuntimeStatus.notInstalled,
    'missing' => LlmRuntimeStatus.missing,
    'corrupted' => LlmRuntimeStatus.corrupted,
    'installedUnverified' || 'installed_unverified' => LlmRuntimeStatus.installedUnverified,
    'ready' => LlmRuntimeStatus.ready,
    'degraded' => LlmRuntimeStatus.degraded,
    _ => LlmRuntimeStatus.degraded,
  };

  return LlmRuntimeState(
    ready: payload['ready'] as bool? ?? status == LlmRuntimeStatus.ready,
    reason: payload['reason'] as String? ?? '当前本地 LLM runtime 未就绪。',
    status: status,
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
