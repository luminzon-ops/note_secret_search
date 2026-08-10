import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart'
    show LlmRuntimeCancelledException;
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:uuid/uuid.dart';

class LocalLlmEngine implements LlmEngine, CancellableLlmEngine {
  const LocalLlmEngine({required LlmRuntimeBridge bridge}) : _bridge = bridge;

  static const _uuid = Uuid();
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

    final bridge = _bridge;
    final result = bridge is RequestIdentifiedLlmRuntimeBridge
        ? await (bridge as RequestIdentifiedLlmRuntimeBridge)
              .ensureIdentifiedModelReady(
                modelId: model.id,
                modelPath: path,
                verifiedChecksum: model.checksum,
              )
        : await bridge.ensureModelReady(modelId: model.id, modelPath: path);
    return mapLlmRuntimeState(result, fallbackPath: path);
  }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    final path = request.model.localPath;
    if (path == null || path.trim().isEmpty) {
      throw StateError('Active local LLM model path is missing.');
    }

    final requestId = request.requestId ?? _uuid.v4();
    final bridge = _bridge;
    late final Map<String, dynamic> result;
    try {
      result = bridge is RequestIdentifiedLlmRuntimeBridge
          ? await (bridge as RequestIdentifiedLlmRuntimeBridge)
                .generateIdentifiedText(
                  requestId: requestId,
                  modelId: request.model.id,
                  modelPath: path,
                  verifiedChecksum: request.model.checksum,
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
                  emitPartialCompletion: request.emitPartialCompletion,
                )
          : await bridge.generateText(
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
              emitPartialCompletion: request.emitPartialCompletion,
            );
    } on LlmRuntimeCancelledException {
      throw const LlmGenerationCancelledException();
    }

    return LlmInferenceResponse(
      text: result['text'] as String? ?? '',
      finishReason: result['finishReason'] as String? ?? 'unknown',
      usedPrivateContext:
          result['usedPrivateContext'] as bool? ?? request.usedPrivateContext,
      usage: ChatBackendUsage(
        actualBackend: result['actualBackend'] as String? ?? 'llama.cpp',
        actualModel: result['actualModel'] as String? ?? request.model.id,
      ),
    );
  }

  @override
  Future<void> cancelGeneration(String requestId) {
    final bridge = _bridge;
    if (bridge is RequestIdentifiedLlmRuntimeBridge) {
      return (bridge as RequestIdentifiedLlmRuntimeBridge).cancelGeneration(
        requestId: requestId,
      );
    }
    return Future<void>.value();
  }

  @override
  Future<void> releaseModel(String modelId) =>
      _bridge.releaseModel(modelId: modelId);
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
    'installedUnverified' ||
    'installed_unverified' => LlmRuntimeStatus.installedUnverified,
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
