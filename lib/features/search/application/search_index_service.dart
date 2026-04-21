import 'dart:convert';

import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SearchIndexService {
  const SearchIndexService({
    required SearchRepository repository,
    required CryptoService cryptoService,
    required EmbeddingEngine embeddingEngine,
  })  : _repository = repository,
        _cryptoService = cryptoService,
        _embeddingEngine = embeddingEngine;

  final SearchRepository _repository;
  final CryptoService _cryptoService;
  final EmbeddingEngine _embeddingEngine;

  Future<SearchIndexStatus> buildStatus({
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
    required ModelRegistryEntry? activeEmbeddingModel,
    required SearchIndexSettings settings,
  }) async {
    if (activeEmbeddingModel == null) {
      return const SearchIndexStatus(
        engineReady: false,
        engineReason: '尚未配置可用的本地 embedding 模型。',
        hasActiveEmbeddingModel: false,
        pendingItems: <SearchIndexPendingItem>[],
      );
    }

    final engineState = await _embeddingEngine.getState(activeEmbeddingModel);
    final pending = <SearchIndexPendingItem>[];
    pending.addAll(await _detectPendingSecrets(secrets, activeEmbeddingModel.id, settings));
    pending.addAll(await _detectPendingNotes(notes, activeEmbeddingModel.id, settings));

    pending.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return SearchIndexStatus(
      engineReady: engineState.ready,
      engineReason: engineState.reason,
      hasActiveEmbeddingModel: true,
      pendingItems: pending,
    );
  }

  Future<void> indexPendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required SearchIndexSettings settings,
  }) async {
    final chunks = <EmbeddingChunk>[];
    final now = DateTime.now();

    for (final item in items) {
      final segments = _splitText(item.indexPlainText, settings.maxChunkLength);
      for (var chunkIndex = 0; chunkIndex < segments.length; chunkIndex++) {
        final vector = await _embeddingEngine.embed(
          EmbeddingRequest(model: activeEmbeddingModel, text: segments[chunkIndex]),
        );

        chunks.add(
          EmbeddingChunk(
            id: '${item.sourceType.name}:${item.sourceId}:$chunkIndex:${activeEmbeddingModel.id}',
            sourceType: item.sourceType,
            sourceId: item.sourceId,
            chunkIndex: chunkIndex,
            plainTextHash: item.plainTextHash,
            modelId: activeEmbeddingModel.id,
            vectorBlob: utf8.encode(jsonEncode(vector.values)),
            tokenCount: vector.tokenCount,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    await _repository.upsertEmbeddingChunks(chunks);
  }

  Future<List<SearchIndexPendingItem>> _detectPendingSecrets(
    List<SecretItem> secrets,
    String modelId,
    SearchIndexSettings settings,
  ) async {
    final pending = <SearchIndexPendingItem>[];
    for (final item in secrets) {
      final plainText = _secretPlainText(item, settings);
      final plainTextHash = _hashText(plainText);
      final chunks = await _repository.getChunksBySource(item.id, SearchSourceType.secret, modelId);
      final hasFreshChunk = chunks.any((chunk) => chunk.plainTextHash == plainTextHash);
      if (!hasFreshChunk) {
        pending.add(
          SearchIndexPendingItem(
            sourceId: item.id,
            sourceType: SearchSourceType.secret,
            title: item.title,
            updatedAt: item.updatedAt,
            plainTextHash: plainTextHash,
            indexPlainText: plainText,
          ),
        );
      }
    }
    return pending;
  }

  Future<List<SearchIndexPendingItem>> _detectPendingNotes(
    List<NoteItem> notes,
    String modelId,
    SearchIndexSettings settings,
  ) async {
    final pending = <SearchIndexPendingItem>[];
    for (final item in notes) {
      final plainText = _notePlainText(item, settings);
      final plainTextHash = _hashText(plainText);
      final chunks = await _repository.getChunksBySource(item.id, SearchSourceType.note, modelId);
      final hasFreshChunk = chunks.any((chunk) => chunk.plainTextHash == plainTextHash);
      if (!hasFreshChunk) {
        pending.add(
          SearchIndexPendingItem(
            sourceId: item.id,
            sourceType: SearchSourceType.note,
            title: item.title,
            updatedAt: item.updatedAt,
            plainTextHash: plainTextHash,
            indexPlainText: plainText,
          ),
        );
      }
    }
    return pending;
  }

  String _secretPlainText(SecretItem item, SearchIndexSettings settings) {
    return <String>[
      item.title,
      _cryptoService.decryptNullable(item.usernameCiphertext),
      _cryptoService.decryptNullable(item.websiteUrlCiphertext),
      if (settings.includeSecretNotes) _cryptoService.decryptNullable(item.noteCiphertext),
      item.tags.join(' '),
    ].where((part) => part.trim().isNotEmpty).join('\n');
  }

  String _notePlainText(NoteItem item, SearchIndexSettings settings) {
    return <String>[
      item.title,
      _cryptoService.decryptNullable(item.summaryCacheCiphertext),
      if (settings.includeNoteBody) _cryptoService.decryptNullable(item.contentCiphertext),
      item.tags.join(' '),
    ].where((part) => part.trim().isNotEmpty).join('\n');
  }

  List<String> _splitText(String value, int maxChunkLength) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final paragraphs = normalized
        .split(RegExp(r'\n{2,}'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) {
        return;
      }
      chunks.add(buffer.toString().trim());
      buffer.clear();
    }

    for (final paragraph in paragraphs.isEmpty ? <String>[normalized] : paragraphs) {
      if (paragraph.length > maxChunkLength) {
        flush();
        for (var index = 0; index < paragraph.length; index += maxChunkLength) {
          final end = (index + maxChunkLength).clamp(0, paragraph.length);
          chunks.add(paragraph.substring(index, end).trim());
        }
        continue;
      }

      final candidate = buffer.isEmpty ? paragraph : '${buffer.toString()}\n\n$paragraph';
      if (candidate.length > maxChunkLength) {
        flush();
        buffer.write(paragraph);
      } else {
        if (buffer.isNotEmpty) {
          buffer.write('\n\n');
        }
        buffer.write(paragraph);
      }
    }

    flush();
    return chunks;
  }

  String _hashText(String value) {
    return base64.encode(utf8.encode(value.trim()));
  }
}
