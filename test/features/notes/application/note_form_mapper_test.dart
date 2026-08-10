import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';

import '../../../support/security_test_fixture.dart';

void main() {
  late SecurityTestFixture fixture;

  setUp(() {
    fixture = SecurityTestFixture();
  });

  tearDown(() {
    fixture.dispose();
  });

  test('encrypts and round-trips contextual note fields', () {
    const draft = NoteDraft(
      title: '  Backup codes  ',
      content: 'one-time recovery codes',
      summary: 'account recovery',
      tags: ['security'],
      categoryId: 'category-1',
      favorite: true,
    );

    final item = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: draft,
      cryptoService: fixture.crypto,
    );

    expect(
      () => FieldEnvelopeCodec.decode(item.contentCiphertext),
      returnsNormally,
    );
    expect(
      () => FieldEnvelopeCodec.decode(item.summaryCacheCiphertext!),
      returnsNormally,
    );
    final restored = NoteFormMapper.toDraft(item, fixture.crypto);
    expect(restored.content, draft.content);
    expect(restored.summary, draft.summary);
    expect(item.title, 'Backup codes');
  });

  test('rejects moving note ciphertext to another row or field', () {
    final item = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Note',
        content: 'private body',
        summary: 'private summary',
        tags: [],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: fixture.crypto,
    );

    expect(
      () => fixture.crypto.decryptField(
        item.contentCiphertext,
        field: EncryptedDatabaseField.noteContent,
        rowId: 'different-note',
      ),
      _authenticationFailure,
    );
    expect(
      () => fixture.crypto.decryptField(
        item.contentCiphertext,
        field: EncryptedDatabaseField.noteSummary,
        rowId: item.id,
      ),
      _authenticationFailure,
    );
  });
}

final Matcher _authenticationFailure = throwsA(
  isA<FieldCryptoException>().having(
    (error) => error.failure,
    'failure',
    FieldCryptoFailure.authenticationFailed,
  ),
);
