import 'package:note_secret_search/features/ai_models/domain/active_model_selection_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesActiveModelSelectionStore
    implements ActiveModelSelectionStore {
  const SharedPreferencesActiveModelSelectionStore({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  static const activeEmbeddingModelIdKey = 'ai.active_embedding_model_id';

  final SharedPreferences _preferences;

  @override
  Future<String?> loadActiveEmbeddingModelId() async {
    final modelId = _preferences.getString(activeEmbeddingModelIdKey);
    return modelId == null || modelId.isEmpty ? null : modelId;
  }

  @override
  Future<void> saveActiveEmbeddingModelId(String? modelId) async {
    if (modelId == null || modelId.isEmpty) {
      await _preferences.remove(activeEmbeddingModelIdKey);
      return;
    }
    await _preferences.setString(activeEmbeddingModelIdKey, modelId);
  }
}
