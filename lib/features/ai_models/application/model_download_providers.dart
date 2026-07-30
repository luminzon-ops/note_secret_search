import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/logging/logging_providers.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/storage/database/model_state_records.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_lifecycle_controller.dart';
import 'package:note_secret_search/features/ai_models/application/model_registry_integrity_verifier.dart';
import 'package:note_secret_search/features/ai_models/application/model_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_session_releaser.dart';
import 'package:note_secret_search/features/ai_models/domain/bundled_model_artifact_stager.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_gateway.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_revision_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_runtime.dart';
import 'package:note_secret_search/features/ai_models/domain/model_source_probe.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:uuid/uuid.dart';

part 'model_download_sensitive_providers.dart';
part 'model_download_controller_internals.dart';
part 'model_download_dependencies.dart';
part 'model_download_legacy_commands.dart';
part 'model_download_structured.dart';
part 'model_download_structured_artifact_staging.dart';
part 'model_download_structured_resume.dart';
part 'model_download_structured_support.dart';

class ModelDownloadController {
  ModelDownloadController({
    required Ref ref,
    required ModelDownloadRepository repository,
    required ModelRegistryRepository registryRepository,
    required ModelDownloadGateway downloadService,
    required ModelLifecycleStore lifecycleStore,
    required ModelArtifactStore artifactStore,
    required AppLogger logger,
    ModelRevisionStore? revisionStore,
    BundledModelArtifactStager? bundledArtifactStager,
    ModelRuntimeCoordinator? runtimeCoordinator,
    ModelInstallJournalStore? installJournalStore,
    ModelSessionReleaser? sessionReleaser,
  }) : _ref = ref,
       _repository = repository,
       _registryRepository = registryRepository,
       _downloadService = downloadService,
       _integrityVerifier = ModelRegistryIntegrityVerifier(
         downloadService: downloadService,
       ),
       _lifecycleStore = lifecycleStore,
       _providedRevisionStore = revisionStore,
       _providedBundledArtifactStager = bundledArtifactStager,
       _providedRuntimeCoordinator = runtimeCoordinator,
       _installJournalStore =
           installJournalStore ??
           (lifecycleStore is ModelInstallJournalStore
               ? lifecycleStore as ModelInstallJournalStore
               : null),
       _modelLifecycleController = ModelLifecycleController(
         lifecycleStore: lifecycleStore,
         artifactStore: artifactStore,
         sessionReleaser: sessionReleaser,
         prepareModelMutation: (modelId, modelType) {
           final ModelRuntimeCoordinator coordinator =
               runtimeCoordinator ?? ref.read(modelRuntimeCoordinatorProvider);
           return coordinator.releaseForMutation(modelId, modelType: modelType);
         },
       ),
       _logger = logger;

  final Ref _ref;
  final ModelDownloadRepository _repository;
  final ModelRegistryRepository _registryRepository;
  final ModelDownloadGateway _downloadService;
  final ModelRegistryIntegrityVerifier _integrityVerifier;
  final ModelLifecycleStore _lifecycleStore;
  final ModelRevisionStore? _providedRevisionStore;
  final BundledModelArtifactStager? _providedBundledArtifactStager;
  final ModelRuntimeCoordinator? _providedRuntimeCoordinator;
  final ModelInstallJournalStore? _installJournalStore;
  final ModelLifecycleController _modelLifecycleController;
  final AppLogger _logger;
  final Map<String, Future<void>> _modelOperationLocks =
      <String, Future<void>>{};
  final Map<String, int> _modelGenerations = <String, int>{};
  final Map<String, String> _activeOperationIds = <String, String>{};
  static const _uuid = Uuid();

  ModelRevisionStore get _revisionStore =>
      _providedRevisionStore ?? _ref.read(modelRevisionStoreProvider);

  BundledModelArtifactStager get _bundledArtifactStager =>
      _providedBundledArtifactStager ??
      _ref.read(bundledModelArtifactStagerProvider);

  ModelRuntimeCoordinator get _runtimeCoordinator =>
      _providedRuntimeCoordinator ?? _ref.read(modelRuntimeCoordinatorProvider);

  Future<void> enqueueDownload({
    required String modelId,
    required String sourceId,
    required int? totalBytes,
  }) => _enqueueLegacyDownload(
    modelId: modelId,
    sourceId: sourceId,
    totalBytes: totalBytes,
  );

  Future<void> markDownloading(String modelId) =>
      _markLegacyDownloading(modelId);

  Future<void> startDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
  }) => _startLegacyDownload(entry: entry, source: source);

  Future<void> pause(String modelId, {required String sourceId}) =>
      _pauseLegacyDownload(modelId, sourceId: sourceId);

  Future<void> deleteInstalledModel(String modelId) =>
      _deleteLegacyInstalledModel(modelId);

  Future<bool> isInstalled(String modelId) => _isLegacyInstalled(modelId);

  Future<void> markFailed(String modelId, String message) =>
      _markLegacyFailed(modelId, message);

  Future<void> markFailedForSource(
    String modelId, {
    required String sourceId,
    required String message,
  }) =>
      _markLegacyFailedForSource(modelId, sourceId: sourceId, message: message);

  Future<void> markCompleted(String modelId) => _markLegacyCompleted(modelId);

  /// Re-validates a single installed model: checks file presence and checksum,
  /// persists the resulting [filePresent], [enabled], and [integrityStatus],
  /// then invalidates the relevant providers.
  Future<void> revalidateInstalledModel(String modelId) async {
    _logger.info('model_revalidation_started');
    final entry = await _registryRepository.getById(modelId);
    if (entry == null) {
      _logger.warning('model_revalidation_missing_entry');
      return;
    }

    var normalized = await _normalizeRegistryEntry(entry);
    _logger.info('model_revalidation_state_checked');
    if (normalized.filePresent &&
        normalized.integrityStatus == ModelIntegrityStatus.valid) {
      if (normalized.type == 'llm' &&
          normalized.localPath != null &&
          normalized.localPath!.trim().isNotEmpty) {
        _logger.info('model_revalidation_runtime_check_started');
        final runtimeState = await _runtimeCoordinator.inspectInstalledModel(
          normalized,
        );
        _logger.info('model_revalidation_runtime_check_finished');
        normalized = normalized.copyWith(
          enabled: runtimeState.acceptsInstallation,
          filePresent: runtimeState.status != ModelRuntimeStatus.missing,
        );
      } else {
        normalized = normalized.copyWith(enabled: true);
      }
    }

    if (normalized.enabled != entry.enabled ||
        normalized.filePresent != entry.filePresent ||
        normalized.integrityStatus != entry.integrityStatus) {
      await _registryRepository.save(normalized);
      _logger.info('model_revalidation_saved');
    }

    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _logger.info('model_revalidation_invalidated');
  }

  /// Repairs a broken installed model from the trusted catalog.
  /// Structured models reuse verified artifacts and replace only broken ones.
  Future<void> repairInstalledModel(String modelId) async {
    final catalogEntries = await _ref.read(modelCatalogEntriesProvider.future);
    final catalogEntry = catalogEntries
        .where((e) => e.id == modelId)
        .firstOrNull;
    if (catalogEntry == null) {
      return;
    }

    final selectedSource =
        catalogEntry.sources.firstOrNull ??
        catalogEntry.primaryArtifact?.sources.firstOrNull;
    if (selectedSource == null) {
      return;
    }
    if (catalogEntry.artifacts.isNotEmpty) {
      final existing = await _registryRepository.getById(modelId);
      if (existing == null) {
        return;
      }
      await _startStructuredDownload(
        entry: catalogEntry,
        source: selectedSource,
        operationType: 'repair',
      );
      return;
    }
    await startDownload(entry: catalogEntry, source: selectedSource);
  }

  /// Normalizes a [ModelRegistryEntry] by checking file presence and checksum,
  /// returning an updated entry with corrected [filePresent], [enabled], and
  /// [integrityStatus]. Does NOT persist — caller decides when to save.
}
