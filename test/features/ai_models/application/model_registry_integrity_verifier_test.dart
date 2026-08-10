import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/application/model_registry_integrity_verifier.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

void main() {
  test(
    'verifies every required artifact and records corruption or absence',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'model-registry-integrity',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final modelBytes = <int>[1, 2, 3, 4];
      final sidecarBytes = <int>[5, 6];
      final modelFile = File('${tempDir.path}/model.onnx');
      final sidecarFile = File('${tempDir.path}/sidecar.json');
      await modelFile.writeAsBytes(modelBytes);
      await sidecarFile.writeAsBytes(<int>[9, 9]);
      final modelDigest = 'sha256:${sha256.convert(modelBytes)}';
      final sidecarDigest = 'sha256:${sha256.convert(sidecarBytes)}';
      final verifier = ModelRegistryIntegrityVerifier(
        downloadService: ModelDownloadService(
          dio: Dio(),
          logger: const AppLogger(),
          applicationSupportDirectoryProvider: () async => tempDir,
        ),
      );
      final entry = _entry(
        modelPath: modelFile.path,
        sidecarPath: sidecarFile.path,
        modelDigest: modelDigest,
        sidecarDigest: sidecarDigest,
      );

      var result = await verifier.verify(entry);

      expect(result.filePresent, isTrue);
      expect(result.enabled, isFalse);
      expect(result.integrityStatus, ModelIntegrityStatus.corrupted);
      expect(result.artifactById('model')?.state, 'installed');
      expect(result.artifactById('sidecar')?.state, 'corrupted');

      await sidecarFile.writeAsBytes(sidecarBytes);
      result = await verifier.verify(result, enableWhenValid: true);

      expect(result.filePresent, isTrue);
      expect(result.enabled, isTrue);
      expect(result.integrityStatus, ModelIntegrityStatus.valid);
      expect(result.artifacts.every((artifact) => artifact.isVerified), isTrue);

      await sidecarFile.delete();
      result = await verifier.verify(result, enableWhenValid: true);

      expect(result.filePresent, isFalse);
      expect(result.enabled, isFalse);
      expect(result.integrityStatus, ModelIntegrityStatus.unknown);
      expect(result.artifactById('sidecar')?.state, 'unknown');
      expect(result.artifactById('sidecar')?.verifiedChecksum, isNull);
      expect(result.artifactById('sidecar')?.verifiedSizeBytes, isNull);
    },
  );
}

ModelRegistryEntry _entry({
  required String modelPath,
  required String sidecarPath,
  required String modelDigest,
  required String sidecarDigest,
}) {
  return ModelRegistryEntry(
    id: 'model-1',
    type: 'embedding',
    provider: 'builtin_catalog',
    name: 'Model 1',
    version: 'release-1',
    sizeBytes: 6,
    quantization: null,
    minRamMb: 512,
    recommendedTier: 'local',
    localPath: modelPath,
    checksum: modelDigest,
    enabled: true,
    installedAt: DateTime(2026, 7, 24),
    filePresent: true,
    integrityStatus: ModelIntegrityStatus.valid,
    releaseId: 'release-1',
    catalogVersion: 7,
    catalogDigest:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    generation: 1,
    revisionRoot: 'revisions/1',
    artifacts: <ModelArtifactPath>[
      ModelArtifactPath(
        artifactId: 'model',
        releaseId: 'release-1',
        role: 'model',
        sourceId: 'model-source',
        localPath: modelPath,
        relativePath: 'runtime/model.onnx',
        required: true,
        expectedChecksum: modelDigest,
        verifiedChecksum: modelDigest,
        expectedSizeBytes: 4,
        verifiedSizeBytes: 4,
        state: 'installed',
        verifiedAt: 1,
      ),
      ModelArtifactPath(
        artifactId: 'sidecar',
        releaseId: 'release-1',
        role: 'sidecar',
        sourceId: 'sidecar-source',
        localPath: sidecarPath,
        relativePath: 'runtime/sidecar.json',
        required: true,
        expectedChecksum: sidecarDigest,
        verifiedChecksum: sidecarDigest,
        expectedSizeBytes: 2,
        verifiedSizeBytes: 2,
        state: 'installed',
        verifiedAt: 1,
      ),
    ],
  );
}
