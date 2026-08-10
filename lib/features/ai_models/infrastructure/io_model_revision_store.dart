import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/features/ai_models/domain/model_revision_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'package:note_secret_search/features/ai_models/domain/model_revision_store.dart';

part 'io_model_revision_store_install.dart';
part 'io_model_revision_store_path_safety.dart';
part 'io_model_revision_store_staging.dart';

class IoModelRevisionStore implements ModelRevisionStore {
  IoModelRevisionStore({
    Future<Directory> Function()? applicationSupportDirectoryProvider,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory;

  final Future<Directory> Function() _applicationSupportDirectoryProvider;

  @override
  Future<StagedModelArtifact> stageExistingArtifact({
    required String modelId,
    required String operationId,
    required String artifactId,
    required String relativePath,
    required String sourcePath,
    required int expectedSizeBytes,
    required String expectedChecksum,
  }) => _stageExistingArtifact(
    modelId: modelId,
    operationId: operationId,
    artifactId: artifactId,
    relativePath: relativePath,
    sourcePath: sourcePath,
    expectedSizeBytes: expectedSizeBytes,
    expectedChecksum: expectedChecksum,
  );

  @override
  Future<InstalledModelRevision> installVerifiedRevision({
    required String modelId,
    required String operationId,
    required int generation,
    required List<StagedModelArtifact> artifacts,
  }) => _installVerifiedRevision(
    modelId: modelId,
    operationId: operationId,
    generation: generation,
    artifacts: artifacts,
  );

  @override
  Future<void> recoverInterruptedInstalls({required String modelId}) =>
      _recoverInterruptedInstalls(modelId: modelId);

  @override
  Future<void> discardInstalledRevision({
    required String modelId,
    required String revisionRoot,
  }) => _discardInstalledRevision(modelId: modelId, revisionRoot: revisionRoot);
}
