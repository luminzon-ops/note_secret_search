import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

abstract interface class ModelRegistryRepository {
  Future<List<ModelRegistryEntry>> listInstalledModels();

  Future<ModelRegistryEntry?> getById(String id);

  Future<void> save(ModelRegistryEntry entry);

  Future<void> deleteById(String id);
}
