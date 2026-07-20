import 'package:note_secret_search/core/security/search_index_fingerprint.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_index_document.dart';

class SearchIndexChunker {
  const SearchIndexChunker();

  List<SearchIndexTextChunk> chunk(
    SearchIndexDocument document, {
    required int maxChunkLength,
  }) {
    if (!supportedSearchChunkLengths.contains(maxChunkLength)) {
      throw ArgumentError.value(
        maxChunkLength,
        'maxChunkLength',
        'Unsupported search chunk length.',
      );
    }

    final chunks = <SearchIndexTextChunk>[];
    for (final content in document.fields) {
      final texts = _isTagField(content.field)
          ? content.values
          : <String>[
              for (final value in content.values)
                ..._splitValue(value, maxChunkLength),
            ];
      for (var index = 0; index < texts.length; index++) {
        chunks.add(
          SearchIndexTextChunk(
            field: content.field,
            fieldChunkIndex: index,
            text: texts[index],
          ),
        );
      }
    }
    return List<SearchIndexTextChunk>.unmodifiable(chunks);
  }

  bool _isTagField(SearchSourceField field) {
    return field == SearchSourceField.secretTags ||
        field == SearchSourceField.noteTags;
  }

  List<String> _splitValue(String value, int maxChunkLength) {
    final normalized = canonicalText(value);
    if (normalized.isEmpty) {
      return const <String>[];
    }
    final paragraphs = normalized
        .split(RegExp(r'\n{2,}'))
        .map(canonicalText)
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final chunks = <String>[];
    var pending = '';

    void flush() {
      if (pending.isNotEmpty) {
        chunks.add(pending);
        pending = '';
      }
    }

    for (final paragraph in paragraphs) {
      if (_runeLength(paragraph) > maxChunkLength) {
        flush();
        chunks.addAll(_hardSplit(paragraph, maxChunkLength));
        continue;
      }
      final candidate = pending.isEmpty ? paragraph : '$pending\n\n$paragraph';
      if (_runeLength(candidate) > maxChunkLength) {
        flush();
        pending = paragraph;
      } else {
        pending = candidate;
      }
    }
    flush();
    return chunks;
  }

  List<String> _hardSplit(String value, int maxChunkLength) {
    final runes = value.runes.toList(growable: false);
    return <String>[
      for (var start = 0; start < runes.length; start += maxChunkLength)
        String.fromCharCodes(
          runes.sublist(start, (start + maxChunkLength).clamp(0, runes.length)),
        ),
    ];
  }

  int _runeLength(String value) => value.runes.length;
}
