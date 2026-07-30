part of 'model_management_page.dart';

Widget _buildDeviceCapabilitySection({
  required AsyncValue<DeviceProfile?> profileAsync,
  required AsyncValue<DeviceCapabilityReport> capabilityReportAsync,
}) {
  final states = <AsyncValue<dynamic>>[profileAsync, capabilityReportAsync];
  final failure = _firstAsyncFailure(states);
  if (failure != null) {
    return _ModelAsyncStatusCard(
      title: '设备能力评级',
      message: '设备能力读取失败：${failure.error}',
    );
  }
  if (_hasPendingAsyncValue(states)) {
    return const _ModelAsyncStatusCard(
      title: '设备能力评级',
      message: '正在读取设备能力...',
      loading: true,
    );
  }
  return DeviceTierCard(
    profile: profileAsync.requireValue,
    capabilityReport: capabilityReportAsync.requireValue,
  );
}

Widget _buildInstalledModelsSection({
  required AsyncValue<List<ModelRegistryEntry>> registryAsync,
  required AsyncValue<Map<String, EmbeddingEngineState>> runtimeStatesAsync,
  required AsyncValue<Map<String, LlmRuntimeState>> llmRuntimeStatesAsync,
  required AsyncValue<ActiveModelSelection> selectionAsync,
  required AsyncValue<ModelRegistryEntry?> activeLlmAsync,
}) {
  final states = <AsyncValue<dynamic>>[
    registryAsync,
    runtimeStatesAsync,
    llmRuntimeStatesAsync,
    selectionAsync,
    activeLlmAsync,
  ];
  final failure = _firstAsyncFailure(states);
  if (failure != null) {
    return _ModelAsyncStatusCard(message: '已安装模型状态读取失败：${failure.error}');
  }
  if (_hasPendingAsyncValue(states)) {
    return const _ModelAsyncStatusCard(
      message: '正在读取已安装模型状态...',
      loading: true,
    );
  }
  return _InstalledModelsCard(
    entries: registryAsync.requireValue,
    runtimeStates: runtimeStatesAsync.requireValue,
    llmRuntimeStates: llmRuntimeStatesAsync.requireValue,
    activeEmbeddingModelId: selectionAsync.requireValue.activeEmbeddingModelId,
    activeLlmModelId: activeLlmAsync.requireValue?.id,
  );
}

AsyncValue<dynamic>? _firstAsyncFailure(Iterable<AsyncValue<dynamic>> states) {
  for (final state in states) {
    if (state.hasError) {
      return state;
    }
  }
  return null;
}

bool _hasPendingAsyncValue(Iterable<AsyncValue<dynamic>> states) {
  return states.any((state) => state.isLoading || !state.hasValue);
}

class _ModelAsyncStatusCard extends StatelessWidget {
  const _ModelAsyncStatusCard({
    this.title,
    required this.message,
    this.loading = false,
  });

  final String? title;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            _ModelAsyncMessage(message: message, loading: loading),
          ],
        ),
      ),
    );
  }
}

class _ModelAsyncMessage extends StatelessWidget {
  const _ModelAsyncMessage({required this.message, this.loading = false});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (loading) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: Text(message)),
      ],
    );
  }
}
