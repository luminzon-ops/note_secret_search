import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_download_status_view_model.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

part 'model_management_catalog_entry.dart';
part 'model_management_download_status_card.dart';

class ModelManagementPage extends ConsumerWidget {
  const ModelManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(modelCatalogEntriesProvider);
    final taskAsync = ref.watch(modelDownloadTasksProvider);
    final registryAsync = ref.watch(modelRegistryEntriesProvider);
    final runtimeStatesAsync = ref.watch(embeddingRuntimeStatesProvider);
    final llmRuntimeStatesAsync = ref.watch(llmRuntimeStatesProvider);
    final selectionAsync = ref.watch(activeModelSelectionProvider);
    final activeLlmAsync = ref.watch(activeLocalLlmModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('模型')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DeviceTierCard(),
          const SizedBox(height: 16),
          const _ModelDownloadNoticeCard(),
          const SizedBox(height: 16),
          registryAsync.when(
            data: (entries) {
              final supportedEntries = entries
                  .where((entry) => entry.type != 'multimodal_llm')
                  .toList(growable: false);
              final runtimeStates =
                  runtimeStatesAsync.valueOrNull ??
                  const <String, EmbeddingEngineState>{};
              final llmRuntimeStates =
                  llmRuntimeStatesAsync.valueOrNull ??
                  const <String, LlmRuntimeState>{};
              final activeLlmModelId = activeLlmAsync.valueOrNull?.id;
              return selectionAsync.when(
                data: (selection) => _InstalledModelsCard(
                  entries: supportedEntries,
                  runtimeStates: runtimeStates,
                  llmRuntimeStates: llmRuntimeStates,
                  activeEmbeddingModelId: selection.activeEmbeddingModelId,
                  activeLlmModelId: activeLlmModelId,
                ),
                loading: () => _InstalledModelsCard(
                  entries: supportedEntries,
                  runtimeStates: runtimeStates,
                  llmRuntimeStates: llmRuntimeStates,
                  activeEmbeddingModelId: null,
                  activeLlmModelId: activeLlmModelId,
                ),
                error: (error, stackTrace) => _InstalledModelsCard(
                  entries: supportedEntries,
                  runtimeStates: runtimeStates,
                  llmRuntimeStates: llmRuntimeStates,
                  activeEmbeddingModelId: null,
                  activeLlmModelId: activeLlmModelId,
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('已安装模型读取失败：$error'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          catalogAsync.when(
            data: (entries) => taskAsync.when(
              data: (tasks) => _CatalogSection(
                entries: entries
                    .where((entry) => entry.type != 'multimodal_llm')
                    .toList(growable: false),
                tasks: tasks,
              ),
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, stackTrace) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('下载任务读取失败：$error'),
                ),
              ),
            ),
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('模型目录读取失败：$error'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTierCard extends StatelessWidget {
  const _DeviceTierCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设备能力评级'),
            SizedBox(height: 8),
            Text('当前为 MVP 保守实现：先展示模型目录，再接设备探测、下载状态机与安装校验。'),
          ],
        ),
      ),
    );
  }
}

class _ModelDownloadNoticeCard extends StatelessWidget {
  const _ModelDownloadNoticeCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模型下载与本地部署说明'),
            SizedBox(height: 8),
            Text(
              '当前已接入目录驱动下载、checksum 校验、断点续传、自动切源、下载恢复与下载后 runtime 校验。MVP 阶段仍未完成签名校验、安装探测增强、benchmark 与更完整设备分级。',
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledModelsCard extends ConsumerWidget {
  const _InstalledModelsCard({
    required this.entries,
    required this.runtimeStates,
    required this.llmRuntimeStates,
    required this.activeEmbeddingModelId,
    required this.activeLlmModelId,
  });

  final List<ModelRegistryEntry> entries;
  final Map<String, EmbeddingEngineState> runtimeStates;
  final Map<String, LlmRuntimeState> llmRuntimeStates;
  final String? activeEmbeddingModelId;
  final String? activeLlmModelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('当前尚未安装本地模型。')),
      );
    }

    final controller = ref.watch(modelDownloadControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本地已安装模型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final entry in entries)
              Builder(
                builder: (context) {
                  final runtimeState = runtimeStates[entry.id];
                  final llmRuntimeState = llmRuntimeStates[entry.id];
                  final isRuntimeReady = switch (entry.type) {
                    'embedding' => runtimeState?.ready == true,
                    'llm' => llmRuntimeState?.ready == true,
                    _ => entry.isInstalled,
                  };
                  final isBroken = !isRuntimeReady || !entry.filePresent;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isRuntimeReady && entry.isInstalled
                              ? Icons.inventory_2_outlined
                              : Icons.warning_amber_outlined,
                        ),
                        title: Text(entry.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatModelCapabilitySummary(entry)),
                            const SizedBox(height: 2),
                            Text(
                              formatInstalledModelDeploymentStatus(
                                entry,
                                runtimeState: runtimeState,
                                llmRuntimeState: llmRuntimeState,
                              ),
                            ),
                            if (entry.type == 'embedding' &&
                                runtimeState != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '运行时状态：${_runtimeStatusLabel(runtimeState.status)}',
                              ),
                            ],
                            if (entry.type == 'llm' &&
                                llmRuntimeState != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '运行时状态：${_llmRuntimeStatusLabel(llmRuntimeState.status)}',
                              ),
                            ],
                            if (entry.localPath != null &&
                                entry.localPath!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(entry.localPath!),
                            ],
                          ],
                        ),
                        trailing: Text(
                          activeEmbeddingModelId == entry.id
                              ? '当前语义模型'
                              : activeLlmModelId == entry.id
                              ? '当前本地LLM'
                              : (isRuntimeReady && entry.isInstalled
                                    ? '已安装模型'
                                    : '本地记录失效'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                controller.revalidateInstalledModel(entry.id),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: const Text('校验'),
                          ),
                          if (isBroken)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  controller.repairInstalledModel(entry.id),
                              icon: const Icon(Icons.build_outlined, size: 18),
                              label: const Text('修复'),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

String _llmRuntimeStatusLabel(LlmRuntimeStatus status) {
  switch (status) {
    case LlmRuntimeStatus.notInstalled:
      return '未安装';
    case LlmRuntimeStatus.missing:
      return '文件缺失';
    case LlmRuntimeStatus.corrupted:
      return '文件损坏';
    case LlmRuntimeStatus.installedUnverified:
      return '待校验';
    case LlmRuntimeStatus.ready:
      return '已就绪';
    case LlmRuntimeStatus.degraded:
      return '运行时异常';
  }
}

class _CatalogSection extends ConsumerWidget {
  const _CatalogSection({required this.entries, required this.tasks});

  final List<ModelCatalogEntry> entries;
  final List<ModelDownloadTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedAsync = ref.watch(modelRegistryEntriesProvider);
    final runtimeStatesAsync = ref.watch(embeddingRuntimeStatesProvider);
    final llmRuntimeStatesAsync = ref.watch(llmRuntimeStatesProvider);

    if (entries.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('暂无可用模型目录。')),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('可下载模型目录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            installedAsync.when(
              data: (installedEntries) {
                final runtimeStates =
                    runtimeStatesAsync.valueOrNull ??
                    const <String, EmbeddingEngineState>{};
                final llmRuntimeStates =
                    llmRuntimeStatesAsync.valueOrNull ??
                    const <String, LlmRuntimeState>{};
                return Column(
                  children: [
                    for (final entry in entries) ...[
                      Builder(
                        builder: (context) {
                          final displayTask = _displayTaskFor(entry.id);
                          return _CatalogEntryTile(
                            entry: entry,
                            latestTask: displayTask,
                            installedEntry: _installedFor(
                              installedEntries,
                              entry.id,
                            ),
                            runtimeState: runtimeStates[entry.id],
                            llmRuntimeState: llmRuntimeStates[entry.id],
                            allTasks: _tasksFor(entry.id),
                          );
                        },
                      ),
                      if (entry != entries.last) const Divider(height: 24),
                    ],
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('安装状态读取失败：$error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ModelDownloadTask? _latestTaskFor(String modelId) {
    for (final task in tasks) {
      if (task.modelId == modelId) {
        return task;
      }
    }
    return null;
  }

  List<ModelDownloadTask> _tasksFor(String modelId) {
    return tasks
        .where((task) => task.modelId == modelId)
        .toList(growable: false);
  }

  ModelDownloadTask? _displayTaskFor(String modelId) {
    final modelTasks = _tasksFor(modelId);
    if (modelTasks.isEmpty) {
      return null;
    }

    for (final task in modelTasks) {
      if (task.status == ModelDownloadStatus.downloading) {
        return task;
      }
    }

    for (final task in modelTasks) {
      if ((task.status == ModelDownloadStatus.queued ||
              task.status == ModelDownloadStatus.paused) &&
          task.downloadedBytes > 0 &&
          task.resumable) {
        return task;
      }
    }

    for (final task in modelTasks) {
      if (task.status == ModelDownloadStatus.failed) {
        return task;
      }
    }

    return _latestTaskFor(modelId);
  }

  ModelRegistryEntry? _installedFor(
    List<ModelRegistryEntry> entries,
    String modelId,
  ) {
    for (final entry in entries) {
      if (entry.id == modelId) {
        return entry;
      }
    }
    return null;
  }
}
