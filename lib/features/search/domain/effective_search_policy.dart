import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';

enum SearchOperation { keyword, indexing, semanticSearch, aiAutoContext }

class EffectiveSearchPolicy {
  const EffectiveSearchPolicy(this.configuration);

  final SearchConfiguration configuration;

  bool allows(SearchSourceField field, SearchOperation operation) {
    if (operation != SearchOperation.keyword &&
        !configuration.allowLocalEmbedding) {
      return false;
    }

    final fieldEnabled = switch (field) {
      SearchSourceField.secretTitle ||
      SearchSourceField.noteTitle => configuration.includeTitle,
      SearchSourceField.secretUsername => configuration.includeUsername,
      SearchSourceField.secretPassword =>
        configuration.includePasswordField &&
            operation == SearchOperation.keyword,
      SearchSourceField.secretWebsiteUrl => configuration.includeUrl,
      SearchSourceField.secretNote => configuration.includeSecretNote,
      SearchSourceField.secretTags ||
      SearchSourceField.noteTags => configuration.includeTags,
      SearchSourceField.noteSummary ||
      SearchSourceField.noteBody => configuration.includeNoteBody,
    };
    return fieldEnabled;
  }
}
