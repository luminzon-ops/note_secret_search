import 'dart:io';

import 'package:flutter/services.dart';
import 'package:note_secret_search/features/ai_models/domain/bundled_model_artifact_stager.dart';

class AssetBundledModelArtifactStager implements BundledModelArtifactStager {
  const AssetBundledModelArtifactStager({required AssetBundle assetBundle})
    : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;

  @override
  Future<BundledModelArtifactStageResult> stage({
    required String assetPath,
    required String targetPath,
    required int expectedSizeBytes,
  }) async {
    final data = await _assetBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != expectedSizeBytes) {
      throw StateError('bundled_artifact_size_mismatch');
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return BundledModelArtifactStageResult(
      path: file.path,
      sizeBytes: bytes.length,
    );
  }
}
