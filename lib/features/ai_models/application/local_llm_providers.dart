import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/domain/local_llm_selection_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_runtime.dart';

final localLlmSelectionStoreProvider = Provider<LocalLlmSelectionStore>((ref) {
  throw StateError(
    'localLlmSelectionStoreProvider must be overridden by app composition',
  );
});

final llmRuntimeStatesProvider = FutureProvider<Map<String, LlmRuntimeState>>((
  ref,
) {
  return guardSensitiveFuture<Map<String, LlmRuntimeState>>(
    ref,
    lockedValue: const <String, LlmRuntimeState>{},
    load: () async {
      final entries = await ref.watch(modelRegistryEntriesProvider.future);
      final coordinator = ref.watch(modelRuntimeCoordinatorProvider);
      final resolved = <String, LlmRuntimeState>{};

      for (final entry in entries) {
        if (entry.type != 'llm') {
          continue;
        }
        resolved[entry.id] = await _runtimeStateFor(coordinator, entry);
      }

      return resolved;
    },
  );
});

final activeLocalLlmModelProvider = FutureProvider<ModelRegistryEntry?>((ref) {
  return guardSensitiveFuture<ModelRegistryEntry?>(
    ref,
    lockedValue: null,
    load: () async {
      final store = ref.watch(localLlmSelectionStoreProvider);
      final storedModelId = await store.loadActiveModelId();
      if (storedModelId == null || storedModelId.isEmpty) {
        return null;
      }

      final entries = await ref.watch(modelRegistryEntriesProvider.future);
      final runtimeStates = await ref.watch(llmRuntimeStatesProvider.future);
      final selectedEntry = entries
          .where((entry) => entry.id == storedModelId && entry.type == 'llm')
          .firstOrNull;
      if (selectedEntry == null) {
        await store.saveActiveModelId(null);
        return null;
      }

      final runtimeState =
          runtimeStates[selectedEntry.id] ??
          _fallbackRuntimeState(selectedEntry);
      final isBrokenState =
          runtimeState.status == LlmRuntimeStatus.missing ||
          runtimeState.status == LlmRuntimeStatus.corrupted;
      if (isBrokenState) {
        await store.saveActiveModelId(null);
        return null;
      }

      return selectedEntry;
    },
  );
});

final localLlmReadinessProvider = FutureProvider<LocalLlmReadiness>((ref) {
  return guardSensitiveFuture<LocalLlmReadiness>(
    ref,
    lockedValue: const LocalLlmReadiness(
      ready: false,
      reason: '应用已锁定。',
      activeModel: null,
      runtimeState: null,
    ),
    load: () async {
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
      final runtimeState =
          runtimeStates[model.id] ?? _fallbackRuntimeState(model);

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
    },
  );
});

final activeLocalLlmSelectionControllerProvider =
    Provider<ActiveLocalLlmSelectionController>((ref) {
      return ActiveLocalLlmSelectionController(
        ref: ref,
        store: ref.watch(localLlmSelectionStoreProvider),
        runtimeCoordinator: ref.watch(modelRuntimeCoordinatorProvider),
      );
    });

class ActiveLocalLlmSelectionController {
  ActiveLocalLlmSelectionController({
    required Ref ref,
    required LocalLlmSelectionStore store,
    required ModelRuntimeCoordinator runtimeCoordinator,
  }) : _ref = ref,
       _store = store,
       _runtimeCoordinator = runtimeCoordinator;

  final Ref _ref;
  final LocalLlmSelectionStore _store;
  final ModelRuntimeCoordinator _runtimeCoordinator;

  Future<void> setActiveLocalLlmModel(String? modelId) async {
    final normalized = modelId?.trim();
    final nextModelId = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    final previousModelId = await _store.loadActiveModelId();
    if (previousModelId != null &&
        previousModelId.isNotEmpty &&
        previousModelId != nextModelId) {
      await _runtimeCoordinator.releaseForMutation(
        previousModelId,
        modelType: 'llm',
      );
    }
    await _store.saveActiveModelId(nextModelId);

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

Future<LlmRuntimeState> _runtimeStateFor(
  ModelRuntimeCoordinator coordinator,
  ModelRegistryEntry entry,
) async {
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
  return coordinator.inspectInstalledModel(entry);
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
    status: entry.isInstalled
        ? LlmRuntimeStatus.ready
        : LlmRuntimeStatus.degraded,
    modelPath: entry.localPath,
  );
}
