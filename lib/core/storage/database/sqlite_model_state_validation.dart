part of 'sqlite_model_state_repository.dart';

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Value is required.');
  }
}

void _requireCatalogDigest(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'Lowercase SHA-256 is required.');
  }
}

void _requireArtifactDigest(String value, String name) {
  if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'A sha256:<64 lowercase hex> digest is required.',
    );
  }
}

void _requireRelativePath(String value, String name) {
  _requireText(value, name);
  final segments = p.posix.split(value);
  if (value.contains(r'\') ||
      value.contains(':') ||
      p.posix.isAbsolute(value) ||
      p.windows.isAbsolute(value) ||
      p.posix.normalize(value) != value ||
      segments.any((segment) => segment == '.' || segment == '..') ||
      value.endsWith('/')) {
    throw ArgumentError.value(
      value,
      name,
      'A normalized relative path is required.',
    );
  }
}

void _validateArtifactVerification(ModelRegistryArtifactRecord artifact) {
  if (artifact.expectedSizeBytes <= 0) {
    throw ArgumentError.value(
      artifact.expectedSizeBytes,
      'expectedSizeBytes',
      'A positive artifact size is required.',
    );
  }
  const trustedStates = <String>{'verified', 'staged', 'installed'};
  if (!trustedStates.contains(artifact.state)) {
    return;
  }
  if (artifact.verifiedSizeBytes != artifact.expectedSizeBytes ||
      artifact.verifiedSha256 != artifact.expectedSha256 ||
      artifact.verifiedAt == null) {
    throw ArgumentError.value(
      artifact,
      'artifact',
      'Trusted artifact state requires matching verified identity.',
    );
  }
}

void _requireStagingPath(
  String? value, {
  required String? operationId,
  required String name,
  bool allowRoot = false,
}) {
  if (value == null) {
    return;
  }
  _requireRelativePath(value, name);
  final root = '.staging/$operationId';
  if (operationId == null ||
      operationId.trim().isEmpty ||
      (!allowRoot && !value.startsWith('$root/')) ||
      (allowRoot && value != root && !value.startsWith('$root/'))) {
    throw ArgumentError.value(
      value,
      name,
      'A model-owned staging path is required.',
    );
  }
}

void _requireRevisionPath(String? value, String name) {
  if (value == null) {
    return;
  }
  _requireRelativePath(value, name);
  if (!value.startsWith('revisions/')) {
    throw ArgumentError.value(
      value,
      name,
      'A model-owned revision path is required.',
    );
  }
}

const Map<String, int> _installJournalPhaseRanks = <String, int>{
  'queued': 0,
  'staging': 10,
  'staged': 20,
  'runtime_validating': 30,
  'releasing_sessions': 40,
  'installing': 50,
  'committing': 60,
  'rollback_pending': 70,
  'deleting': 50,
  'completed': 100,
  'failed': 100,
};

void _requireInstallJournalPhase(ModelInstallJournalRecord journal) {
  final phase = journal.phase;
  if (!_installJournalPhaseRanks.containsKey(phase)) {
    throw ArgumentError.value(phase, 'phase', 'Unknown install journal phase.');
  }
  final terminal = phase == 'completed' || phase == 'failed';
  if (terminal != (journal.completedAt != null)) {
    throw ArgumentError.value(
      journal.completedAt,
      'completedAt',
      'Terminal phases require a completion timestamp.',
    );
  }
}

bool _canAdvanceInstallJournal(
  ModelInstallJournalRecord current,
  ModelInstallJournalRecord next,
) {
  if (next.attemptGeneration < current.attemptGeneration) {
    return false;
  }
  if (next.attemptGeneration > current.attemptGeneration) {
    return true;
  }
  if (next.modelId != current.modelId ||
      next.releaseId != current.releaseId ||
      next.operationType != current.operationType ||
      next.oldRevision != current.oldRevision ||
      next.newRevision != current.newRevision ||
      next.stagingRoot != current.stagingRoot ||
      next.targetRoot != current.targetRoot ||
      next.createdAt != current.createdAt ||
      next.updatedAt < current.updatedAt) {
    return false;
  }
  final currentTerminal =
      current.phase == 'completed' || current.phase == 'failed';
  if (currentTerminal) {
    return next.phase == current.phase;
  }
  if (next.phase == 'completed' || next.phase == 'failed') {
    return true;
  }
  return _installJournalPhaseRanks[next.phase]! >=
      _installJournalPhaseRanks[current.phase]!;
}
