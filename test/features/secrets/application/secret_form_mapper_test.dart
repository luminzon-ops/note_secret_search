import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';

import '../../../support/security_test_fixture.dart';

void main() {
  late SecurityTestFixture fixture;

  setUp(() {
    fixture = SecurityTestFixture();
  });

  tearDown(() {
    fixture.dispose();
  });

  test('encrypts and round-trips every contextual secret field', () {
    const draft = SecretDraft(
      title: '  Primary account  ',
      username: 'alice@example.com',
      password: 'correct horse battery staple',
      websiteUrl: 'https://example.com',
      note: 'private note',
      tags: ['personal'],
      categoryId: 'category-1',
      favorite: true,
    );

    final item = SecretFormMapper.create(
      vaultId: 'vault-1',
      draft: draft,
      cryptoService: fixture.crypto,
    );

    for (final ciphertext in [
      item.usernameCiphertext,
      item.passwordCiphertext,
      item.websiteUrlCiphertext,
      item.noteCiphertext,
    ]) {
      expect(ciphertext, isNotNull);
      expect(() => FieldEnvelopeCodec.decode(ciphertext!), returnsNormally);
    }
    expect(
      SecretFormMapper.toDraft(item, fixture.crypto).username,
      draft.username,
    );
    expect(
      SecretFormMapper.toDraft(item, fixture.crypto).password,
      draft.password,
    );
    expect(
      SecretFormMapper.toDraft(item, fixture.crypto).websiteUrl,
      draft.websiteUrl,
    );
    expect(SecretFormMapper.toDraft(item, fixture.crypto).note, draft.note);
    expect(item.title, 'Primary account');
  });

  test('rejects moving secret ciphertext to another row or field', () {
    final item = SecretFormMapper.create(
      vaultId: 'vault-1',
      draft: const SecretDraft.empty().copyWith(password: 'private-password'),
      cryptoService: fixture.crypto,
    );

    expect(
      () => fixture.crypto.decryptField(
        item.passwordCiphertext,
        field: EncryptedDatabaseField.secretPassword,
        rowId: 'different-secret',
      ),
      _authenticationFailure,
    );
    expect(
      () => fixture.crypto.decryptField(
        item.passwordCiphertext,
        field: EncryptedDatabaseField.secretUsername,
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
