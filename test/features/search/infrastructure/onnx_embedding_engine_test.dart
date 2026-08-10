import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
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
  checksum:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _metadata = EmbeddingModelMetadata(
  tokenizer: EmbeddingTokenizerSpec(
    format: 'tokenizer_json',
    assetPath: 'assets/model_catalog/tokenizers/all_minilm/tokenizer.json',
    maxSequenceLength: 256,
    lowercase: true,
  ),
  runtime: EmbeddingRuntimeSpec(
    inputIdsName: 'input_ids',
    attentionMaskName: 'attention_mask',
    outputName: 'last_hidden_state',
    pooling: 'mean',
    normalization: 'l2',
  ),
);

class _FakeEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  _FakeEmbeddingRuntimeBridge({
    required Map<String, dynamic> inspectResult,
    required Map<String, dynamic> embedResult,
  }) : _inspectResult = inspectResult,
       _embedResult = embedResult;

  final Map<String, dynamic> _inspectResult;
  final Map<String, dynamic> _embedResult;
  EmbeddingTokenizerSpec? lastTokenizer;
  EmbeddingRuntimeSpec? lastRuntime;
  String? lastVerifiedChecksum;
  String? lastRequestId;
  String? cancelledRequestId;
  int embedCalls = 0;
  Future<Map<String, dynamic>> Function()? onEmbed;

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    String? verifiedChecksum,
    String? requestId,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    embedCalls += 1;
    lastTokenizer = tokenizer;
    lastRuntime = runtime;
    lastVerifiedChecksum = verifiedChecksum;
    lastRequestId = requestId;
    final callback = onEmbed;
    if (callback != null) {
      return callback();
    }
    return _embedResult;
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    String? verifiedChecksum,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    lastTokenizer = tokenizer;
    lastRuntime = runtime;
    return _inspectResult;
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    String? verifiedChecksum,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    lastTokenizer = tokenizer;
    lastRuntime = runtime;
    return _inspectResult;
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}

  @override
  Future<void> cancelRequest({required String requestId}) async {
    cancelledRequestId = requestId;
  }
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
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      resolveMetadata: (modelId) async => _metadata,
    );

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
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      resolveMetadata: (modelId) async => _metadata,
    );

    final state = await engine.getState(_model);

    expect(state.ready, isFalse);
    expect(state.status, EmbeddingRuntimeStatus.degraded);
    expect(state.reason, '模型已安装但当前不可运行。');
  });

  test('maps embedText response into EmbeddingVector', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2, 0.3],
        'tokenCount': 7,
        'vectorDimension': 3,
      },
    );
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      resolveMetadata: (modelId) async => _metadata,
    );

    final vector = await engine.embed(
      const EmbeddingRequest(model: _model, text: 'hello runtime'),
    );

    expect(vector.values, <double>[0.1, 0.2, 0.3]);
    expect(vector.tokenCount, 7);
  });

  test(
    'embed rejects empty non-finite and mismatched runtime vectors',
    () async {
      final invalidPayloads = <Map<String, dynamic>>[
        <String, dynamic>{
          'values': <double>[],
          'tokenCount': 0,
          'vectorDimension': 0,
        },
        <String, dynamic>{
          'values': <double>[double.nan, 1],
          'tokenCount': 2,
          'vectorDimension': 2,
        },
        <String, dynamic>{
          'values': <double>[0.1, 0.2],
          'tokenCount': 2,
          'vectorDimension': 3,
        },
      ];

      for (final payload in invalidPayloads) {
        final engine = OnnxEmbeddingEngine(
          bridge: _FakeEmbeddingRuntimeBridge(
            inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
            embedResult: payload,
          ),
          resolveMetadata: (modelId) async => _metadata,
        );

        await expectLater(
          engine.embed(
            const EmbeddingRequest(model: _model, text: 'hello runtime'),
          ),
          throwsA(
            isA<EmbeddingRuntimeException>()
                .having((error) => error.code, 'code', 'INVALID_OUTPUT')
                .having((error) => error.stage, 'stage', 'output'),
          ),
        );
      }
    },
  );

  test('cancellation during registration prevents native submission', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2],
        'tokenCount': 2,
        'vectorDimension': 2,
      },
    );
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      requestIdFactory: () => 'request-pre-submit',
      resolveMetadata: (modelId) async => _metadata,
    );

    await expectLater(
      engine.embed(
        EmbeddingRequest(
          model: _model,
          text: 'hello runtime',
          cancellationToken: _CancelOnRegisterToken(),
        ),
      ),
      throwsA(isA<EmbeddingRuntimeCancelledException>()),
    );

    expect(bridge.cancelledRequestId, 'request-pre-submit');
    expect(bridge.embedCalls, 0);
  });

  test('embed requires a verified checksum before native submission', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2],
        'tokenCount': 2,
        'vectorDimension': 2,
      },
    );
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      resolveMetadata: (modelId) async => _metadata,
    );

    await expectLater(
      engine.embed(
        EmbeddingRequest(
          model: _model.copyWith(clearChecksum: true),
          text: 'hello runtime',
        ),
      ),
      throwsA(
        isA<EmbeddingRuntimeException>().having(
          (error) => error.code,
          'code',
          'INVALID_ARGUMENT',
        ),
      ),
    );

    expect(bridge.embedCalls, 0);
  });

  test('embed forwards tokenizer and runtime metadata to bridge', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2, 0.3],
        'tokenCount': 3,
        'vectorDimension': 3,
      },
    );
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      resolveMetadata: (modelId) async => _metadata,
    );

    await engine.embed(
      const EmbeddingRequest(model: _model, text: 'hello runtime'),
    );

    expect(bridge.lastTokenizer, isNotNull);
    expect(bridge.lastTokenizer?.assetPath, contains('tokenizer.json'));
    expect(bridge.lastRuntime, isNotNull);
    expect(bridge.lastRuntime?.outputName, 'last_hidden_state');
    expect(bridge.lastRuntime?.pooling, 'mean');
    expect(bridge.lastVerifiedChecksum, _model.checksum);
    expect(bridge.lastRequestId, isNotEmpty);
  });

  test(
    'embed cancellation forwards request id and surfaces typed cancellation',
    () async {
      final bridge = _FakeEmbeddingRuntimeBridge(
        inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
        embedResult: <String, dynamic>{
          'values': <double>[0.1, 0.2],
          'tokenCount': 2,
        },
      );
      final embedStarted = Completer<void>();
      final nativeResult = Completer<Map<String, dynamic>>();
      bridge.onEmbed = () {
        embedStarted.complete();
        return nativeResult.future;
      };
      final cancellation = EmbeddingCancellationController();
      final engine = OnnxEmbeddingEngine(
        bridge: bridge,
        requestIdFactory: () => 'request-cancel',
        resolveMetadata: (modelId) async => _metadata,
      );

      final future = engine.embed(
        EmbeddingRequest(
          model: _model,
          text: 'hello runtime',
          cancellationToken: cancellation,
        ),
      );
      await embedStarted.future;
      cancellation.cancel();
      nativeResult.completeError(
        const EmbeddingRuntimeCancelledException(
          stage: 'inference',
          modelId: 'embed-1',
        ),
      );

      await expectLater(
        future,
        throwsA(isA<EmbeddingRuntimeCancelledException>()),
      );
      expect(bridge.cancelledRequestId, 'request-cancel');
    },
  );

  test('getState degrades when embedding metadata is missing', () async {
    final bridge = _FakeEmbeddingRuntimeBridge(
      inspectResult: <String, dynamic>{'status': 'ready', 'reason': 'ok'},
      embedResult: <String, dynamic>{
        'values': <double>[0.1, 0.2, 0.3],
        'tokenCount': 3,
        'vectorDimension': 3,
      },
    );
    final engine = OnnxEmbeddingEngine(
      bridge: bridge,
      resolveMetadata: (modelId) async => null,
    );

    final state = await engine.getState(_model);

    expect(state.ready, isFalse);
    expect(state.status, EmbeddingRuntimeStatus.degraded);
    expect(state.reason, contains('metadata'));
  });
}

class _CancelOnRegisterToken implements EmbeddingCancellationToken {
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  EmbeddingCancellationRegistration register(void Function() listener) {
    _isCancelled = true;
    listener();
    return EmbeddingCancellationToken.none.register(() {});
  }
}
