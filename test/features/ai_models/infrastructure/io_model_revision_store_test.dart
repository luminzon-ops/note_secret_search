import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_revision_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'installs all staged artifacts atomically and preserves old revision',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_revision_store_',
      );
      addTearDown(() => support.delete(recursive: true));
      final store = IoModelRevisionStore(
        applicationSupportDirectoryProvider: () async => support,
      );
      final oldRevision = Directory(
        p.join(support.path, 'models', 'model-1', 'revisions', '1'),
      );
      await oldRevision.create(recursive: true);
      await File(p.join(oldRevision.path, 'model.bin')).writeAsBytes(<int>[9]);
      final staging = Directory(
        p.join(support.path, 'models', 'model-1', '.staging', 'operation-1'),
      );
      await staging.create(recursive: true);
      final modelPart = File(p.join(staging.path, 'model.part'));
      final tokenizerPart = File(p.join(staging.path, 'tokenizer.part'));
      await modelPart.writeAsBytes(<int>[1, 2, 3]);
      await tokenizerPart.writeAsBytes(<int>[4, 5]);

      final installed = await store.installVerifiedRevision(
        modelId: 'model-1',
        operationId: 'operation-1',
        generation: 2,
        artifacts: <StagedModelArtifact>[
          StagedModelArtifact(
            artifactId: 'model',
            relativePath: 'runtime/model.bin',
            stagingPath: modelPart.path,
            expectedSizeBytes: 3,
            expectedChecksum: _sha123,
          ),
          StagedModelArtifact(
            artifactId: 'tokenizer',
            relativePath: 'runtime/tokenizer.json',
            stagingPath: tokenizerPart.path,
            expectedSizeBytes: 2,
            expectedChecksum: _sha45,
          ),
        ],
      );

      expect(installed.revisionRoot, endsWith(p.join('revisions', '2')));
      expect(
        await File(installed.pathsByArtifactId['model']!).readAsBytes(),
        <int>[1, 2, 3],
      );
      expect(
        await File(installed.pathsByArtifactId['tokenizer']!).readAsBytes(),
        <int>[4, 5],
      );
      expect(await oldRevision.exists(), isTrue);
      expect(await staging.exists(), isFalse);
    },
  );

  test('rejects traversal and case-colliding relative paths', () async {
    final support = await Directory.systemTemp.createTemp(
      'note_secret_search_revision_paths_',
    );
    addTearDown(() => support.delete(recursive: true));
    final store = IoModelRevisionStore(
      applicationSupportDirectoryProvider: () async => support,
    );
    final staging = Directory(
      p.join(support.path, 'models', 'model-1', '.staging', 'operation-1'),
    );
    await staging.create(recursive: true);
    final first = File(p.join(staging.path, 'first.part'));
    final second = File(p.join(staging.path, 'second.part'));
    await first.writeAsBytes(<int>[1]);
    await second.writeAsBytes(<int>[2]);

    await expectLater(
      store.installVerifiedRevision(
        modelId: 'model-1',
        operationId: 'operation-1',
        generation: 1,
        artifacts: <StagedModelArtifact>[
          StagedModelArtifact(
            artifactId: 'model',
            relativePath: '../model.bin',
            stagingPath: first.path,
            expectedSizeBytes: 1,
            expectedChecksum: _sha1,
          ),
        ],
      ),
      throwsA(isA<ModelRevisionStoreException>()),
    );
    await expectLater(
      store.installVerifiedRevision(
        modelId: 'model-1',
        operationId: 'operation-1',
        generation: 1,
        artifacts: <StagedModelArtifact>[
          StagedModelArtifact(
            artifactId: 'first',
            relativePath: 'Model.bin',
            stagingPath: first.path,
            expectedSizeBytes: 1,
            expectedChecksum: _sha1,
          ),
          StagedModelArtifact(
            artifactId: 'second',
            relativePath: 'model.bin',
            stagingPath: second.path,
            expectedSizeBytes: 1,
            expectedChecksum: _sha2,
          ),
        ],
      ),
      throwsA(isA<ModelRevisionStoreException>()),
    );
  });

  test('missing staged artifact leaves the old revision untouched', () async {
    final support = await Directory.systemTemp.createTemp(
      'note_secret_search_revision_failure_',
    );
    addTearDown(() => support.delete(recursive: true));
    final store = IoModelRevisionStore(
      applicationSupportDirectoryProvider: () async => support,
    );
    final oldFile = File(
      p.join(support.path, 'models', 'model-1', 'revisions', '1', 'model.bin'),
    );
    await oldFile.create(recursive: true);
    await oldFile.writeAsBytes(<int>[9]);

    await expectLater(
      store.installVerifiedRevision(
        modelId: 'model-1',
        operationId: 'operation-2',
        generation: 2,
        artifacts: <StagedModelArtifact>[
          StagedModelArtifact(
            artifactId: 'model',
            relativePath: 'model.bin',
            stagingPath: p.join(support.path, 'missing.part'),
            expectedSizeBytes: 1,
            expectedChecksum: _sha1,
          ),
        ],
      ),
      throwsA(isA<ModelRevisionStoreException>()),
    );

    expect(await oldFile.readAsBytes(), <int>[9]);
    expect(
      await Directory(
        p.join(support.path, 'models', 'model-1', 'revisions', '2'),
      ).exists(),
      isFalse,
    );
  });

  test(
    'checksum mismatch cleans temporary revision and preserves the old one',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_revision_checksum_',
      );
      addTearDown(() => support.delete(recursive: true));
      final store = IoModelRevisionStore(
        applicationSupportDirectoryProvider: () async => support,
      );
      final oldFile = File(
        p.join(
          support.path,
          'models',
          'model-1',
          'revisions',
          '1',
          'model.bin',
        ),
      );
      await oldFile.create(recursive: true);
      await oldFile.writeAsBytes(<int>[9]);
      final staging = Directory(
        p.join(support.path, 'models', 'model-1', '.staging', 'operation-3'),
      );
      await staging.create(recursive: true);
      final corrupt = File(p.join(staging.path, 'model.part'));
      await corrupt.writeAsBytes(<int>[1, 2, 3]);

      await expectLater(
        store.installVerifiedRevision(
          modelId: 'model-1',
          operationId: 'operation-3',
          generation: 2,
          artifacts: <StagedModelArtifact>[
            StagedModelArtifact(
              artifactId: 'model',
              relativePath: 'model.bin',
              stagingPath: corrupt.path,
              expectedSizeBytes: 3,
              expectedChecksum: _sha45,
            ),
          ],
        ),
        throwsA(
          isA<ModelRevisionStoreException>().having(
            (error) => error.code,
            'code',
            'revision_staging_checksum_mismatch',
          ),
        ),
      );

      expect(await oldFile.readAsBytes(), <int>[9]);
      final revisions = Directory(p.dirname(oldFile.parent.path));
      expect(
        await revisions
            .list()
            .where(
              (entity) => p.basename(entity.path).startsWith('.installing-'),
            )
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'existing revision is idempotent only when checksum still matches',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_revision_existing_',
      );
      addTearDown(() => support.delete(recursive: true));
      final store = IoModelRevisionStore(
        applicationSupportDirectoryProvider: () async => support,
      );
      final target = File(
        p.join(
          support.path,
          'models',
          'model-1',
          'revisions',
          '2',
          'model.bin',
        ),
      );
      await target.create(recursive: true);
      await target.writeAsBytes(<int>[2]);
      final staging = Directory(
        p.join(support.path, 'models', 'model-1', '.staging', 'operation-4'),
      );
      await staging.create(recursive: true);
      final staged = File(p.join(staging.path, 'model.part'));
      await staged.writeAsBytes(<int>[1]);

      await expectLater(
        store.installVerifiedRevision(
          modelId: 'model-1',
          operationId: 'operation-4',
          generation: 2,
          artifacts: <StagedModelArtifact>[
            StagedModelArtifact(
              artifactId: 'model',
              relativePath: 'model.bin',
              stagingPath: staged.path,
              expectedSizeBytes: 1,
              expectedChecksum: _sha1,
            ),
          ],
        ),
        throwsA(
          isA<ModelRevisionStoreException>().having(
            (error) => error.code,
            'code',
            'revision_target_conflict',
          ),
        ),
      );
      expect(await target.readAsBytes(), <int>[2]);
      expect(await staging.exists(), isTrue);
    },
  );

  test(
    'recovery removes interrupted installs and preserves completed revisions',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_revision_recovery_',
      );
      addTearDown(() => support.delete(recursive: true));
      final revisions = Directory(
        p.join(support.path, 'models', 'model-1', 'revisions'),
      );
      final completed = Directory(p.join(revisions.path, '1'));
      final interrupted = Directory(
        p.join(revisions.path, '.installing-2-operation-5'),
      );
      await completed.create(recursive: true);
      await interrupted.create(recursive: true);
      await File(p.join(completed.path, 'model.bin')).writeAsBytes(<int>[9]);
      await File(p.join(interrupted.path, 'model.bin')).writeAsBytes(<int>[1]);
      final store = IoModelRevisionStore(
        applicationSupportDirectoryProvider: () async => support,
      );

      await store.recoverInterruptedInstalls(modelId: 'model-1');
      await store.recoverInterruptedInstalls(modelId: 'model-1');

      expect(await completed.exists(), isTrue);
      expect(await interrupted.exists(), isFalse);
    },
  );

  test(
    'rejects a staging directory junction that escapes the model root',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'note_secret_search_revision_link_',
      );
      addTearDown(() => support.delete(recursive: true));
      final stagingParent = Directory(
        p.join(support.path, 'models', 'model-1', '.staging'),
      );
      final outside = Directory(p.join(support.path, 'outside'));
      await stagingParent.create(recursive: true);
      await outside.create(recursive: true);
      final victim = File(p.join(outside.path, 'model.part'));
      await victim.writeAsBytes(<int>[1]);
      final linkPath = p.join(stagingParent.path, 'operation-6');
      await _createDirectoryLink(linkPath: linkPath, targetPath: outside.path);
      final store = IoModelRevisionStore(
        applicationSupportDirectoryProvider: () async => support,
      );

      await expectLater(
        store.installVerifiedRevision(
          modelId: 'model-1',
          operationId: 'operation-6',
          generation: 1,
          artifacts: <StagedModelArtifact>[
            StagedModelArtifact(
              artifactId: 'model',
              relativePath: 'model.bin',
              stagingPath: p.join(linkPath, 'model.part'),
              expectedSizeBytes: 1,
              expectedChecksum: _sha1,
            ),
          ],
        ),
        throwsA(
          isA<ModelRevisionStoreException>().having(
            (error) => error.code,
            'code',
            'revision_path_outside_root',
          ),
        ),
      );
      expect(await victim.readAsBytes(), <int>[1]);
    },
  );
}

const _sha123 =
    'sha256:039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';
const _sha45 =
    'sha256:2fa1b377bf67309f65e5e7bc9d924345ca648dec4e601a398a9cb497dcba3765';
const _sha1 =
    'sha256:4bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459a';
const _sha2 =
    'sha256:dbc1b4c900ffe48d575b5da5c638040125f65db0fe3e24494b76ea986457d986';

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
