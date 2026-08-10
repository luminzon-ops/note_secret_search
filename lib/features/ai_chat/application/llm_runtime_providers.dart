import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_bridge.dart';

export 'package:note_secret_search/features/ai_models/application/local_llm_providers.dart';

final llmRuntimeBridgeProvider = Provider<LlmRuntimeBridge>((ref) {
  throw StateError(
    'llmRuntimeBridgeProvider must be overridden by app composition',
  );
});

final llmEngineProvider = Provider<LlmEngine>((ref) {
  throw StateError('llmEngineProvider must be overridden by app composition');
});
