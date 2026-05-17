import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

class LlmInferenceRequest {
  const LlmInferenceRequest({
    required this.model,
    required this.prompt,
    required this.usedPrivateContext,
    this.maxOutputTokens = 96,
    this.maxPromptChars = 1200,
    this.contextLength = 1024,
    this.conservativeMode = true,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.9,
    this.seed = 42,
    this.stopSequences = const <String>[
      '</s>',
      '<|im_end|>',
      '<|endoftext|>',
    ],
    this.emitPartialCompletion = false,
  });

  final ModelRegistryEntry model;
  final String prompt;
  final bool usedPrivateContext;
  final int maxOutputTokens;
  final int maxPromptChars;
  final int contextLength;
  final bool conservativeMode;
  final double temperature;
  final int topK;
  final double topP;
  final int seed;
  final List<String> stopSequences;
  final bool emitPartialCompletion;
}

class LlmInferenceResponse {
  const LlmInferenceResponse({
    required this.text,
    required this.finishReason,
    required this.usedPrivateContext,
  });

  final String text;
  final String finishReason;
  final bool usedPrivateContext;
}

abstract interface class LlmEngine {
  Future<LlmRuntimeState> getState(ModelRegistryEntry model);

  Future<LlmInferenceResponse> generate(LlmInferenceRequest request);

  Future<void> releaseModel(String modelId);
}
