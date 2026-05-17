import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';

void main() {
  test('encodes and decodes registry artifact paths for sqlite persistence', () {
    const artifacts = <ModelArtifactPath>[
      ModelArtifactPath(
        role: 'model',
        sourceId: 'model-source',
        localPath: '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf',
        checksum: 'sha256:model',
        sizeBytes: 10,
      ),
      ModelArtifactPath(
        role: 'mmproj',
        sourceId: 'mmproj-source',
        localPath: '/models/minicpm/mmproj-model-f16.gguf',
        checksum: 'sha256:mmproj',
        sizeBytes: 20,
      ),
    ];

    final encoded = encodeModelArtifactPathsForSqlite(artifacts);
    final decoded = decodeModelArtifactPathsFromSqlite(encoded);

    expect(decoded, hasLength(2));
    expect(decoded.first.role, 'model');
    expect(decoded.first.localPath, '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf');
    expect(decoded.last.role, 'mmproj');
    expect(decoded.last.localPath, '/models/minicpm/mmproj-model-f16.gguf');
  });

  test('decodes missing sqlite artifact json as empty list', () {
    expect(decodeModelArtifactPathsFromSqlite(null), isEmpty);
    expect(decodeModelArtifactPathsFromSqlite(''), isEmpty);
  });
}
