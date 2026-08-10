import 'package:note_secret_search/features/search/domain/search_configuration.dart';

abstract interface class SearchConfigurationRepository {
  Future<SearchConfiguration> load();

  Future<SearchConfiguration> save(SearchConfiguration desired);
}
