import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final llmRuntimeBridgeProvider = Provider<LlmRuntimeBridge>((ref) {
  return MethodChannelLlmRuntimeBridge();
});

final llmEngineProvider = Provider<LlmEngine>((ref) {
  return LocalLlmEngine(bridge: ref.watch(llmRuntimeBridgeProvider));
});

final llmRuntimeStatesProvider = FutureProvider<Map<String, LlmRuntimeState>>((ref) async {
  final entries = await ref.watch(modelRegistryEntriesProvider.future);
  final llmEngine = ref.watch(llmEngineProvider);
  final resolved = <String, LlmRuntimeState>{};

  for (final entry in entries) {
    if (entry.type != 'llm') {
      continue;
    }

    if (entry.localPath == null || entry.localPath!.trim().isEmpty) {
      resolved[entry.id] = const LlmRuntimeState(
        ready: false,
        reason: '尚未配置本地 LLM 模型文件。',
        status: LlmRuntimeStatus.notInstalled,
      );
      continue;
    }

    if (!entry.filePresent) {
      resolved[entry.id] = LlmRuntimeState(
        ready: false,
        reason: '本地模型文件缺失，需要重新下载或修复。',
        status: LlmRuntimeStatus.missing,
        modelPath: entry.localPath,
      );
      continue;
    }

    if (entry.integrityStatus == ModelIntegrityStatus.corrupted) {
      resolved[entry.id] = LlmRuntimeState(
        ready: false,
        reason: '本地模型文件校验失败，需要重新下载或修复。',
        status: LlmRuntimeStatus.corrupted,
        modelPath: entry.localPath,
      );
      continue;
    }

    resolved[entry.id] = await llmEngine.getState(entry);
  }

  return resolved;
});

final activeLocalLlmModelProvider = FutureProvider<ModelRegistryEntry?>((ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  final storedModelId = preferences.getString(_activeLlmModelIdKey);
  if (storedModelId == null || storedModelId.isEmpty) {
    return null;
  }

  final entries = await ref.watch(modelRegistryEntriesProvider.future);
  final runtimeStates = await ref.watch(llmRuntimeStatesProvider.future);
  final selectedEntry = entries.where((entry) => entry.id == storedModelId && entry.type == 'llm').firstOrNull;
  if (selectedEntry == null) {
    await preferences.remove(_activeLlmModelIdKey);
    return null;
  }

  final runtimeState = runtimeStates[selectedEntry.id] ?? _fallbackRuntimeState(selectedEntry);
  // Only clear for truly broken states; recoverable states (degraded, installedUnverified)
  // keep the selection so localLlmReadinessProvider can report the blocked reason.
  final isBrokenState = runtimeState.status == LlmRuntimeStatus.missing ||
      runtimeState.status == LlmRuntimeStatus.corrupted;
  if (isBrokenState) {
    await preferences.remove(_activeLlmModelIdKey);
    return null;
  }

  return selectedEntry;
});

final localLlmReadinessProvider = FutureProvider<LocalLlmReadiness>((ref) async {
  final model = await ref.watch(activeLocalLlmModelProvider.future);
  if (model == null) {
    return const LocalLlmReadiness(
      ready: false,
      reason: '尚未选择本地 LLM 模型。',
      activeModel: null,
      runtimeState: null,
    );
  }

  final runtimeStates = await ref.watch(llmRuntimeStatesProvider.future);
  final runtimeState = runtimeStates[model.id] ?? _fallbackRuntimeState(model);

  if (!runtimeState.ready) {
    return LocalLlmReadiness(
      ready: false,
      reason: runtimeState.reason,
      activeModel: model,
      runtimeState: runtimeState,
    );
  }

  return LocalLlmReadiness(
    ready: true,
    reason: '本地 LLM 模型已就绪：${model.name}',
    activeModel: model,
    runtimeState: runtimeState,
  );
});

final activeLocalLlmSelectionControllerProvider = Provider<ActiveLocalLlmSelectionController>((ref) {
  return ActiveLocalLlmSelectionController(ref: ref);
});

class ActiveLocalLlmSelectionController {
  ActiveLocalLlmSelectionController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> setActiveLocalLlmModel(String? modelId) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    if (modelId == null || modelId.isEmpty) {
      await preferences.remove(_activeLlmModelIdKey);
    } else {
      await preferences.setString(_activeLlmModelIdKey, modelId);
    }

    _ref.invalidate(activeLocalLlmModelProvider);
    _ref.invalidate(localLlmReadinessProvider);
  }
}

class LocalLlmReadiness {
  const LocalLlmReadiness({
    required this.ready,
    required this.reason,
    required this.activeModel,
    required this.runtimeState,
  });

  final bool ready;
  final String reason;
  final ModelRegistryEntry? activeModel;
  final LlmRuntimeState? runtimeState;
}

LlmRuntimeState _fallbackRuntimeState(ModelRegistryEntry entry) {
  if (entry.localPath == null || entry.localPath!.trim().isEmpty) {
    return const LlmRuntimeState(
      ready: false,
      reason: '尚未配置本地 LLM 模型文件。',
      status: LlmRuntimeStatus.notInstalled,
    );
  }

  if (!entry.filePresent) {
    return LlmRuntimeState(
      ready: false,
      reason: '本地模型文件缺失，需要重新下载或修复。',
      status: LlmRuntimeStatus.missing,
      modelPath: entry.localPath,
    );
  }

  if (entry.integrityStatus == ModelIntegrityStatus.corrupted) {
    return LlmRuntimeState(
      ready: false,
      reason: '本地模型文件校验失败，需要重新下载或修复。',
      status: LlmRuntimeStatus.corrupted,
      modelPath: entry.localPath,
    );
  }

  return LlmRuntimeState(
    ready: entry.isInstalled,
    reason: entry.isInstalled ? '本地 LLM 模型已就绪。' : '本地 LLM 模型当前不可用。',
    status: entry.isInstalled ? LlmRuntimeStatus.ready : LlmRuntimeStatus.degraded,
    modelPath: entry.localPath,
  );
}

const _activeLlmModelIdKey = 'ai.active_llm_model_id';
