import 'package:note_secret_search/core/security/search_index_fingerprint.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';

class SearchIndexFieldContent {
  SearchIndexFieldContent({
    required this.field,
    required Iterable<String> values,
  }) : values = List<String>.unmodifiable(
         values.map(canonicalText).where((value) => value.isNotEmpty),
       );

  final SearchSourceField field;
  final List<String> values;
}

class SearchIndexDocument {
  SearchIndexDocument({
    required this.sourceKey,
    required this.vaultId,
    required this.title,
    required this.updatedAt,
    required List<SearchIndexFieldContent> fields,
  }) : fields = List<SearchIndexFieldContent>.unmodifiable(fields) {
    if (sourceKey.id.isEmpty || vaultId.isEmpty) {
      throw ArgumentError('Search index source identifiers must not be empty.');
    }
    var previousOrder = -1;
    for (final content in this.fields) {
      if (content.field.sourceType != sourceKey.type ||
          !content.field.supportsSemanticIndex ||
          content.field.index <= previousOrder) {
        throw ArgumentError(
          'Search index fields must be indexable and canonically ordered.',
        );
      }
      previousOrder = content.field.index;
    }
  }

  final SearchSourceKey sourceKey;
  final String vaultId;
  final String title;
  final DateTime updatedAt;
  final List<SearchIndexFieldContent> fields;
}

class SearchIndexTextChunk {
  const SearchIndexTextChunk({
    required this.field,
    required this.fieldChunkIndex,
    required this.text,
  });

  final SearchSourceField field;
  final int fieldChunkIndex;
  final String text;
}
