import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/domain/multimodal_llm_runtime_bridge.dart';

final multimodalLlmRuntimeBridgeProvider = Provider<MultimodalLlmRuntimeBridge>((
  ref,
) {
  throw StateError(
    'multimodalLlmRuntimeBridgeProvider must be overridden by app composition',
  );
});
