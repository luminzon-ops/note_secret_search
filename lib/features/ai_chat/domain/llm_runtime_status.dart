enum LlmRuntimeStatus {
  notInstalled,
  missing,
  corrupted,
  installedUnverified,
  ready,
  degraded,
}

class LlmRuntimeState {
  const LlmRuntimeState({
    required this.ready,
    required this.reason,
    required this.status,
    this.modelPath,
    this.checkedAt,
  });

  final bool ready;
  final String reason;
  final LlmRuntimeStatus status;
  final String? modelPath;
  final DateTime? checkedAt;
}
