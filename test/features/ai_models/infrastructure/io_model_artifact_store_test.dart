import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_artifact_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('deletes primary artifacts and the owned model directory', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'model-artifact-store',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final modelDirectory = Directory(
      p.join(supportDirectory.path, 'models', 'model-1'),
    );
    await modelDirectory.create(recursive: true);
    final primary = File(p.join(modelDirectory.path, 'model.onnx'));
    final sidecar = File(p.join(modelDirectory.path, 'tokenizer.json'));
    final partial = File(p.join(modelDirectory.path, 'download.partial'));
    final outside = File(p.join(supportDirectory.path, 'keep.txt'));
    await primary.writeAsString('model');
    await sidecar.writeAsString('tokenizer');
    await partial.writeAsString('partial');
    await outside.writeAsString('keep');
    final store = IoModelArtifactStore(
      applicationSupportDirectoryProvider: () async => supportDirectory,
    );

    await store.deleteModelArtifacts(
      modelId: 'model-1',
      primaryPath: primary.path,
      artifacts: <ModelArtifactPath>[
        ModelArtifactPath(
          role: 'model',
          sourceId: 'source-model',
          localPath: primary.path,
        ),
        ModelArtifactPath(
          role: 'tokenizer',
          sourceId: 'source-tokenizer',
          localPath: sidecar.path,
        ),
      ],
    );

    expect(await modelDirectory.exists(), isFalse);
    expect(await outside.readAsString(), 'keep');
  });

  test(
    'partial cleanup can be retried after an invalid artifact is fixed',
    () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'model-artifact-retry',
      );
      addTearDown(() => supportDirectory.delete(recursive: true));
      final modelDirectory = Directory(
        p.join(supportDirectory.path, 'models', 'model-1'),
      );
      await modelDirectory.create(recursive: true);
      final primary = File(p.join(modelDirectory.path, 'model.onnx'));
      final sidecarPath = p.join(modelDirectory.path, 'sidecar.json');
      final sidecarDirectory = Directory(sidecarPath);
      final partial = File(p.join(modelDirectory.path, 'download.partial'));
      await primary.writeAsString('model');
      await sidecarDirectory.create();
      await partial.writeAsString('partial');
      final store = IoModelArtifactStore(
        applicationSupportDirectoryProvider: () async => supportDirectory,
      );
      final artifacts = <ModelArtifactPath>[
        ModelArtifactPath(
          role: 'model',
          sourceId: 'source-model',
          localPath: primary.path,
        ),
        ModelArtifactPath(
          role: 'tokenizer',
          sourceId: 'source-tokenizer',
          localPath: sidecarPath,
        ),
      ];

      await expectLater(
        store.deleteModelArtifacts(
          modelId: 'model-1',
          primaryPath: primary.path,
          artifacts: artifacts,
        ),
        throwsA(
          isA<ModelArtifactStoreException>().having(
            (error) => error.code,
            'code',
            'model_artifact_path_is_directory',
          ),
        ),
      );

      expect(await primary.exists(), isFalse);
      expect(await modelDirectory.exists(), isTrue);
      expect(await partial.exists(), isTrue);

      await sidecarDirectory.delete();
      await File(sidecarPath).writeAsString('sidecar');
      await store.deleteModelArtifacts(
        modelId: 'model-1',
        primaryPath: primary.path,
        artifacts: artifacts,
      );

      expect(await modelDirectory.exists(), isFalse);
    },
  );

  test('rejects a model directory link that escapes the owned root', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'model-artifact-link',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final modelsRoot = Directory(p.join(supportDirectory.path, 'models'));
    final outsideDirectory = Directory(
      p.join(supportDirectory.path, 'outside-model'),
    );
    await modelsRoot.create(recursive: true);
    await outsideDirectory.create(recursive: true);
    final victim = File(p.join(outsideDirectory.path, 'model.onnx'));
    await victim.writeAsString('keep');
    final modelDirectoryPath = p.join(modelsRoot.path, 'model-1');
    await _createDirectoryLink(
      linkPath: modelDirectoryPath,
      targetPath: outsideDirectory.path,
    );
    final store = IoModelArtifactStore(
      applicationSupportDirectoryProvider: () async => supportDirectory,
    );

    await expectLater(
      store.deleteModelArtifacts(
        modelId: 'model-1',
        primaryPath: p.join(modelDirectoryPath, 'model.onnx'),
        artifacts: const <ModelArtifactPath>[],
      ),
      throwsA(
        isA<ModelArtifactStoreException>().having(
          (error) => error.code,
          'code',
          'model_artifact_directory_outside_root',
        ),
      ),
    );

    expect(await victim.readAsString(), 'keep');
  });
}

Future<void> _createDirectoryLink({
  required String linkPath,
  required String targetPath,
}) async {
  if (!Platform.isWindows) {
    await Link(linkPath).create(targetPath);
    return;
  }
  final result = await Process.run('cmd', <String>[
    '/c',
    'mklink',
    '/J',
    linkPath,
    targetPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Failed to create junction: ${result.stderr}');
  }
}
