import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

class MultimodalLlmInferenceRequest {
  const MultimodalLlmInferenceRequest({
    required this.model,
    required this.prompt,
    required this.imagePath,
    this.maxOutputTokens = 96,
    this.contextLength = 1024,
    this.reasoningEnabled = false,
  });

  final ModelRegistryEntry model;
  final String prompt;
  final String imagePath;
  final int maxOutputTokens;
  final int contextLength;
  final bool reasoningEnabled;
}
