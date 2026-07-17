import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;
  late SqliteNoteRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    security = SecurityTestFixture();
    repository = SqliteNoteRepository(database: database);
  });

  tearDown(() async {
    security.dispose();
    await database.close();
  });

  test('persists contextual NSSF fields and restores them', () async {
    final item = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Recovery',
        content: 'private note body',
        summary: 'account recovery',
        tags: ['security'],
        categoryId: null,
        favorite: true,
      ),
      cryptoService: security.crypto,
    );

    await repository.save(item);

    final rawRows = await (await database.database).query(
      DatabaseSchema.noteItems,
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(
      () => FieldEnvelopeCodec.decode(
        rawRows.single['content_ciphertext']! as List<int>,
      ),
      returnsNormally,
    );
    final restored = await repository.getById(item.id);
    expect(restored, isNotNull);
    expect(
      NoteFormMapper.toDraft(restored!, security.crypto).content,
      'private note body',
    );
    expect(restored.tags, ['security']);
  });

  test('rejects legacy plaintext fields before saving', () async {
    final item = _legacyNote();

    await expectLater(repository.save(item), throwsFormatException);

    final rows = await (await database.database).query(
      DatabaseSchema.noteItems,
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows, isEmpty);
  });

  test('rejects legacy plaintext fields loaded from the database', () async {
    final item = _legacyNote();
    await (await database.database).insert(DatabaseSchema.noteItems, {
      'id': item.id,
      'vault_id': item.vaultId,
      'title': item.title,
      'content_ciphertext': item.contentCiphertext,
      'summary_ciphertext': item.summaryCacheCiphertext,
      'favorite': 0,
      'created_at': item.createdAt.millisecondsSinceEpoch,
      'updated_at': item.updatedAt.millisecondsSinceEpoch,
    });

    await expectLater(repository.getById(item.id), throwsFormatException);
  });
}

NoteItem _legacyNote() {
  return NoteItem(
    id: 'legacy-note',
    vaultId: 'vault-1',
    title: 'Legacy',
    contentCiphertext: _legacyBytes('legacy body'),
    summaryCacheCiphertext: _legacyBytes('legacy summary'),
    tags: const [],
    categoryId: null,
    favorite: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );
}

Uint8List _legacyBytes(String value) => Uint8List.fromList(value.codeUnits);
