import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart';

final multimodalLlmRuntimeBridgeProvider = Provider<MultimodalLlmRuntimeBridge>((ref) {
  return MethodChannelMultimodalLlmRuntimeBridge();
});
