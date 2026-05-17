import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

abstract interface class ExternalProviderRepository {
  Future<ExternalProviderConfig?> loadById(String id);

  Future<ExternalProviderConfig?> loadEnabled();

  Future<List<ExternalProviderConfig>> loadAll();

  Future<void> save(ExternalProviderConfig config);
}
