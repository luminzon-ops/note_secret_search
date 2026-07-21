import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';

const int searchSourcePageSize = 128;
const int searchSourceIdBatchSize = 200;

class SearchCorpusReader {
  const SearchCorpusReader({
    required SecretRepository secretRepository,
    required NoteRepository noteRepository,
  }) : _secretRepository = secretRepository,
       _noteRepository = noteRepository;

  final SecretRepository _secretRepository;
  final NoteRepository _noteRepository;

  Future<List<SecretItem>> secretPage({
    required String vaultId,
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    _validatePageLimit(limit);
    final repository = _secretRepository;
    if (repository is SecretSearchReader) {
      final reader = repository as SecretSearchReader;
      return reader.listByVaultPage(vaultId, afterId: afterId, limit: limit);
    }
    final all = await repository.listByVault(vaultId);
    return _page(
      all.where((item) => item.deletedAt == null),
      afterId: afterId,
      limit: limit,
      idOf: (item) => item.id,
    );
  }

  Future<List<NoteItem>> notePage({
    required String vaultId,
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    _validatePageLimit(limit);
    final repository = _noteRepository;
    if (repository is NoteSearchReader) {
      final reader = repository as NoteSearchReader;
      return reader.listByVaultPage(vaultId, afterId: afterId, limit: limit);
    }
    final all = await repository.listByVault(vaultId);
    return _page(
      all.where((item) => item.deletedAt == null),
      afterId: afterId,
      limit: limit,
      idOf: (item) => item.id,
    );
  }

  Future<List<SecretItem>> secretsByIds({
    required String vaultId,
    required Iterable<String> ids,
  }) async {
    final requested = ids.toSet().toList(growable: false);
    if (requested.isEmpty) {
      return const <SecretItem>[];
    }
    final repository = _secretRepository;
    if (repository is SecretSearchReader) {
      final reader = repository as SecretSearchReader;
      return reader.listByVaultIds(vaultId, requested);
    }
    final byId = <String, SecretItem>{
      for (final item in await repository.listByVault(vaultId))
        if (item.deletedAt == null) item.id: item,
    };
    return <SecretItem>[
      for (final id in requested)
        if (byId[id] case final item?) item,
    ];
  }

  Future<List<NoteItem>> notesByIds({
    required String vaultId,
    required Iterable<String> ids,
  }) async {
    final requested = ids.toSet().toList(growable: false);
    if (requested.isEmpty) {
      return const <NoteItem>[];
    }
    final repository = _noteRepository;
    if (repository is NoteSearchReader) {
      final reader = repository as NoteSearchReader;
      return reader.listByVaultIds(vaultId, requested);
    }
    final byId = <String, NoteItem>{
      for (final item in await repository.listByVault(vaultId))
        if (item.deletedAt == null) item.id: item,
    };
    return <NoteItem>[
      for (final id in requested)
        if (byId[id] case final item?) item,
    ];
  }

  List<T> _page<T>(
    Iterable<T> source, {
    required String? afterId,
    required int limit,
    required String Function(T item) idOf,
  }) {
    final sorted = source.toList(growable: false)
      ..sort((left, right) => idOf(left).compareTo(idOf(right)));
    return sorted
        .where((item) => afterId == null || idOf(item).compareTo(afterId) > 0)
        .take(limit)
        .toList(growable: false);
  }

  void _validatePageLimit(int limit) {
    if (limit < 1 || limit > searchSourcePageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Must be between 1 and $searchSourcePageSize.',
      );
    }
  }
}
