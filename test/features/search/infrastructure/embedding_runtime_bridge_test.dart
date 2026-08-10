import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/embedding_runtime');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('embedText forwards verified identity and request id', () async {
    MethodCall? recordedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return <String, Object?>{
        'values': <double>[1, 0],
        'tokenCount': 2,
        'vectorDimension': 2,
      };
    });
    final bridge = MethodChannelEmbeddingRuntimeBridge(channel: channel);

    await bridge.embedText(
      modelId: 'embed-1',
      modelPath: '/models/embed-1.onnx',
      verifiedChecksum: 'sha256:verified',
      requestId: 'request-7',
      text: 'hello',
      tokenizer: const EmbeddingTokenizerSpec(
        format: 'tokenizer_json',
        assetPath: 'assets/tokenizer.json',
        maxSequenceLength: 256,
        lowercase: false,
      ),
      runtime: const EmbeddingRuntimeSpec(
        inputIdsName: 'input_ids',
        attentionMaskName: 'attention_mask',
        outputName: 'last_hidden_state',
        pooling: 'mean',
        normalization: 'l2',
      ),
    );

    expect(recordedCall?.method, 'embedText');
    final arguments = recordedCall?.arguments as Map<Object?, Object?>;
    expect(arguments['verifiedChecksum'], 'sha256:verified');
    expect(arguments['requestId'], 'request-7');
  });

  test('cancelRequest forwards request id', () async {
    MethodCall? recordedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });
    final bridge = MethodChannelEmbeddingRuntimeBridge(channel: channel);

    await bridge.cancelRequest(requestId: 'request-8');

    expect(recordedCall?.method, 'cancelRequest');
    expect(recordedCall?.arguments, <String, Object?>{
      'requestId': 'request-8',
    });
  });

  test('maps native cancellation without exposing platform message', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'CANCELLED',
        message: '/private/model/path should not escape',
        details: <String, Object?>{'stage': 'inference', 'modelId': 'embed-1'},
      );
    });
    final bridge = MethodChannelEmbeddingRuntimeBridge(channel: channel);

    await expectLater(
      bridge.embedText(
        modelId: 'embed-1',
        modelPath: '/models/embed-1.onnx',
        verifiedChecksum: 'sha256:verified',
        requestId: 'request-9',
        text: 'secret input',
      ),
      throwsA(
        isA<EmbeddingRuntimeCancelledException>()
            .having((error) => error.code, 'code', 'CANCELLED')
            .having((error) => error.stage, 'stage', 'inference')
            .having((error) => error.modelId, 'modelId', 'embed-1')
            .having(
              (error) => error.toString(),
              'safe string',
              isNot(contains('/private/model/path')),
            ),
      ),
    );
  });

  test('ignores non-string native error details', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'ORT_FAILURE',
        details: <String, Object?>{
          'stage': 42,
          'modelId': <String>['embed-1'],
        },
      );
    });
    final bridge = MethodChannelEmbeddingRuntimeBridge(channel: channel);

    await expectLater(
      bridge.ensureModelReady(
        modelId: 'embed-1',
        modelPath: '/models/embed-1.onnx',
        verifiedChecksum: 'sha256:verified',
      ),
      throwsA(
        isA<EmbeddingRuntimeException>()
            .having((error) => error.code, 'code', 'ORT_FAILURE')
            .having((error) => error.stage, 'stage', isNull)
            .having((error) => error.modelId, 'modelId', isNull),
      ),
    );
  });
}
