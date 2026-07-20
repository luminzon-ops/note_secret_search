import 'dart:typed_data';

enum SearchSourceType {
  secret,
  note;

  static SearchSourceType parse(String value) {
    return SearchSourceType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => throw FormatException('Unknown search source type: $value'),
    );
  }
}

class SearchSourceKey {
  const SearchSourceKey({required this.type, required this.id});

  const SearchSourceKey.secret(this.id) : type = SearchSourceType.secret;

  const SearchSourceKey.note(this.id) : type = SearchSourceType.note;

  final SearchSourceType type;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is SearchSourceKey && other.type == type && other.id == id;
  }

  @override
  int get hashCode => Object.hash(type, id);
}

enum SearchSourceField {
  secretTitle('secret.title', SearchSourceType.secret),
  secretUsername('secret.username', SearchSourceType.secret),
  secretPassword(
    'secret.password',
    SearchSourceType.secret,
    supportsSemanticIndex: false,
  ),
  secretWebsiteUrl('secret.website_url', SearchSourceType.secret),
  secretNote('secret.note', SearchSourceType.secret),
  secretTags('secret.tags', SearchSourceType.secret),
  noteTitle('note.title', SearchSourceType.note),
  noteSummary('note.summary', SearchSourceType.note),
  noteBody('note.body', SearchSourceType.note),
  noteTags('note.tags', SearchSourceType.note);

  const SearchSourceField(
    this.wireName,
    this.sourceType, {
    this.supportsSemanticIndex = true,
  });

  final String wireName;
  final SearchSourceType sourceType;
  final bool supportsSemanticIndex;

  static SearchSourceField parse(String value) {
    return SearchSourceField.values.firstWhere(
      (field) => field.wireName == value,
      orElse: () =>
          throw FormatException('Unknown search source field: $value'),
    );
  }
}

class EmbeddingChunk {
  EmbeddingChunk({
    required this.id,
    required this.indexSetId,
    required this.sourceField,
    required this.fieldChunkIndex,
    required List<int> chunkFingerprint,
    required List<int> vectorBlob,
    required this.tokenCount,
    required this.createdAt,
  }) : chunkFingerprint = Uint8List.fromList(chunkFingerprint),
       vectorBlob = Uint8List.fromList(vectorBlob) {
    if (id.isEmpty || indexSetId.isEmpty) {
      throw ArgumentError('Embedding chunk identifiers must not be empty.');
    }
    if (fieldChunkIndex < 0) {
      throw ArgumentError.value(
        fieldChunkIndex,
        'fieldChunkIndex',
        'Must be non-negative.',
      );
    }
    if (this.chunkFingerprint.length != 32) {
      throw ArgumentError.value(
        this.chunkFingerprint.length,
        'chunkFingerprint',
        'Must contain 32 bytes.',
      );
    }
    if (this.vectorBlob.isEmpty) {
      throw ArgumentError.value(
        this.vectorBlob.length,
        'vectorBlob',
        'Must not be empty.',
      );
    }
    if (tokenCount != null && tokenCount! < 0) {
      throw ArgumentError.value(
        tokenCount,
        'tokenCount',
        'Must be non-negative.',
      );
    }
  }

  final String id;
  final String indexSetId;
  final SearchSourceField sourceField;
  final int fieldChunkIndex;
  final Uint8List chunkFingerprint;
  final Uint8List vectorBlob;
  final int? tokenCount;
  final DateTime createdAt;
}

@Deprecated(
  'Phase 4 migration bridge. Use EmbeddingIndexSet and EmbeddingChunk.',
)
class LegacyEmbeddingChunk {
  const LegacyEmbeddingChunk({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.chunkIndex,
    required this.plainTextHash,
    required this.modelId,
    required this.vectorBlob,
    required this.tokenCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final SearchSourceType sourceType;
  final String sourceId;
  final int chunkIndex;
  final String plainTextHash;
  final String modelId;
  final List<int>? vectorBlob;
  final int? tokenCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}
