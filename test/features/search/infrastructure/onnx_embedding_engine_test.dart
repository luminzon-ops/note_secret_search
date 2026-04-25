import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';

const _model = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin_catalog',
  name: 'Test Embedding Model',
  version: '1.0.0',
  sizeBytes: 1024,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'tier_1',
  localPath: '/data/user/0/app/models/embed-1.onnx',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

class _FakeEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  _FakeEmbeddingRuntimeBridge({
    required Map<String, dynamic> inspectResult,
    required Map<String, dynamic> embedResult,
  })  : _inspectResult = inspectResult,
        _embedResult = embedResult;

  final Map<String, dynamic> _inspectResult;
  final Map<String, dynamic> _embedResult;

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
  }) async {
    return _embedResult;
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  }) async {
    return _inspectResult;
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  }) async {
    return _inspectResult;
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
}

void main() {
  test('maps ready runtime state from bridge', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{
        'status': 'ready',
        'reason': '模型已完成运行时校验。',
        'vectorDimension': 384,
        'modelPath': _model.localPath,
        'checkedAt': DateTime(2026, 4, 26, 12).millisecondsSinceEpoch,
      },
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2],
        'tokenCount': 2,
        'vectorDimension': 2,
      },
    );
    final engine = OnnxEmbeddingEngine(bridge: bridge);

    final state = await engine.getState(_model);

    expect(state.ready, isTrue);
    expect(state.status, EmbeddingRuntimeStatus.ready);
    expect(state.vectorDimension, 384);
    expect(state.modelPath, _model.localPath);
    expect(state.checkedAt, DateTime(2026, 4, 26, 12));
  });

  test('maps degraded runtime state from bridge', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{
        'status': 'degraded',
        'reason': '模型已安装但当前不可运行。',
      },
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2],
        'tokenCount': 2,
      },
    );
    final engine = OnnxEmbeddingEngine(bridge: bridge);

    final state = await engine.getState(_model);

    expect(state.ready, isFalse);
    expect(state.status, EmbeddingRuntimeStatus.degraded);
    expect(state.reason, '模型已安装但当前不可运行。');
  });

  test('maps embedText response into EmbeddingVector', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{
        'status': 'ready',
        'reason': 'ok',
      },
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2, 0.3],
        'tokenCount': 7,
        'vectorDimension': 3,
      },
    );
    final engine = OnnxEmbeddingEngine(bridge: bridge);

    final vector = await engine.embed(
      const EmbeddingRequest(model: _model, text: 'hello runtime'),
    );

    expect(vector.values, <double>[0.1, 0.2, 0.3]);
    expect(vector.tokenCount, 7);
  });
}
