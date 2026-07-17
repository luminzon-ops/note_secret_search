import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';

void main() {
  test('matches the contextual AES-256-GCM field vector', () {
    final keys = DatabaseSessionKeys(
      databaseKey: Uint8List(32),
      fieldKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
    );
    addTearDown(keys.clear);
    final sessionKeyStore = DatabaseSessionKeyStore()..replace(keys);
    final crypto = AesGcmFieldCrypto(
      sessionKeyStore: sessionKeyStore,
      nonceSource: _FixedFieldNonceSource(
        Uint8List.fromList(List<int>.generate(12, (index) => index)),
      ),
    );
    final context = FieldCryptoContext(
      table: 'secret_items',
      rowId: 'row-1',
      column: 'password_ciphertext',
    );

    final encrypted = crypto.encryptNullable('  p@ss word  ', context: context);

    expect(
      encrypted,
      orderedEquals(
        _hex(
          '4e53534601010c100000000d'
          '000102030405060708090a0b'
          '6722a65bb696e26ce233f3ab91'
          'bcc0b481f14bc658c637f6dee68e374e',
        ),
      ),
    );
    expect(
      crypto.decryptNullable(encrypted, context: context),
      '  p@ss word  ',
    );
  });

  test('preserves null, empty, and whitespace field semantics', () {
    final fixture = _FieldCryptoFixture();
    addTearDown(fixture.keys.clear);
    final context = FieldCryptoContext(
      table: 'note_items',
      rowId: 'note-1',
      column: 'summary_ciphertext',
    );

    expect(fixture.crypto.encryptNullable(null, context: context), isNull);
    expect(fixture.crypto.decryptNullable(null, context: context), isEmpty);

    final encryptedEmpty = fixture.crypto.encryptNullable('', context: context);
    final encryptedWhitespace = fixture.crypto.encryptNullable(
      '   ',
      context: context,
    );

    expect(encryptedEmpty, isNotNull);
    expect(encryptedEmpty, hasLength(40));
    expect(
      fixture.crypto.decryptNullable(encryptedEmpty, context: context),
      isEmpty,
    );
    expect(
      fixture.crypto.decryptNullable(encryptedWhitespace, context: context),
      '   ',
    );
  });

  test('rejects legacy bytes and authenticated payload tampering', () {
    final fixture = _FieldCryptoFixture();
    addTearDown(fixture.keys.clear);
    final context = FieldCryptoContext(
      table: 'secret_items',
      rowId: 'secret-1',
      column: 'note_ciphertext',
    );
    final encrypted = fixture.crypto.encryptNullable(
      'private note',
      context: context,
    )!;
    final tamperedCiphertext = Uint8List.fromList(encrypted)..[24] ^= 0x01;
    final tamperedTag = Uint8List.fromList(encrypted)
      ..[encrypted.length - 1] ^= 0x01;

    expect(
      () => fixture.crypto.decryptNullable(
        'legacy plaintext'.codeUnits,
        context: context,
      ),
      _fieldFailure(FieldCryptoFailure.invalidEnvelope),
    );
    expect(
      () =>
          fixture.crypto.decryptNullable(tamperedCiphertext, context: context),
      _fieldFailure(FieldCryptoFailure.authenticationFailed),
    );
    expect(
      () => fixture.crypto.decryptNullable(tamperedTag, context: context),
      _fieldFailure(FieldCryptoFailure.authenticationFailed),
    );
  });

  test('binds ciphertext to table row and column context', () {
    final fixture = _FieldCryptoFixture();
    addTearDown(fixture.keys.clear);
    final context = FieldCryptoContext(
      table: 'secret_items',
      rowId: 'secret-1',
      column: 'password_ciphertext',
    );
    final encrypted = fixture.crypto.encryptNullable(
      'correct horse battery staple',
      context: context,
    );
    final wrongContexts = <FieldCryptoContext>[
      FieldCryptoContext(
        table: 'note_items',
        rowId: context.rowId,
        column: context.column,
      ),
      FieldCryptoContext(
        table: context.table,
        rowId: 'secret-2',
        column: context.column,
      ),
      FieldCryptoContext(
        table: context.table,
        rowId: context.rowId,
        column: 'username_ciphertext',
      ),
    ];

    for (final wrongContext in wrongContexts) {
      expect(
        () => fixture.crypto.decryptNullable(encrypted, context: wrongContext),
        _fieldFailure(FieldCryptoFailure.authenticationFailed),
      );
    }
  });

  test('rejects field access after session keys are cleared', () {
    final fixture = _FieldCryptoFixture();
    final context = FieldCryptoContext(
      table: 'provider_configs',
      rowId: 'provider-1',
      column: 'encrypted_config',
    );
    final encrypted = fixture.crypto.encryptNullable(
      '{"apiKey":"secret"}',
      context: context,
    );

    fixture.keys.clear();

    expect(
      () => fixture.crypto.encryptNullable('new value', context: context),
      throwsStateError,
    );
    expect(
      () => fixture.crypto.decryptNullable(encrypted, context: context),
      throwsStateError,
    );
  });

  test('rejects ambiguous field context values', () {
    expect(
      () => FieldCryptoContext(
        table: '',
        rowId: 'row-1',
        column: 'value_ciphertext',
      ),
      throwsArgumentError,
    );
    expect(
      () => FieldCryptoContext(
        table: 'app_settings',
        rowId: ' key ',
        column: 'value_ciphertext',
      ),
      throwsArgumentError,
    );
  });

  test('defines the nine encrypted database field identities', () {
    expect(
      EncryptedDatabaseField.values
          .map((field) => '${field.table}.${field.column}')
          .toSet(),
      <String>{
        'secret_items.username_ciphertext',
        'secret_items.password_ciphertext',
        'secret_items.website_url_ciphertext',
        'secret_items.note_ciphertext',
        'note_items.content_ciphertext',
        'note_items.summary_ciphertext',
        'provider_configs.encrypted_config',
        'sync_accounts.encrypted_config',
        'app_settings.value_ciphertext',
      },
    );

    final context = EncryptedDatabaseField.appSettingValue.contextFor(
      'search.scope',
    );
    expect(context.table, 'app_settings');
    expect(context.rowId, 'search.scope');
    expect(context.column, 'value_ciphertext');
  });

  test('migration decoder reads only strict legacy UTF-8 bytes', () {
    const decoder = MigrationLegacyUtf8Decoder();

    expect(decoder.decodeNullable(null), isEmpty);
    expect(decoder.decodeNullable(const <int>[]), isEmpty);
    expect(
      decoder.decodeNullable(utf8.encode('  legacy field value  ')),
      '  legacy field value  ',
    );
    expect(
      () => decoder.decodeNullable(const <int>[0xff]),
      throwsFormatException,
    );
  });
}

class _FixedFieldNonceSource implements FieldNonceSource {
  _FixedFieldNonceSource(this.nonce);

  final Uint8List nonce;

  @override
  Uint8List nextNonce() => Uint8List.fromList(nonce);
}

class _FieldCryptoFixture {
  _FieldCryptoFixture()
    : keys = DatabaseSessionKeys(
        databaseKey: Uint8List(32),
        fieldKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      ) {
    store.replace(keys);
    crypto = AesGcmFieldCrypto(
      sessionKeyStore: store,
      nonceSource: _IncrementingFieldNonceSource(),
    );
  }

  final DatabaseSessionKeyStore store = DatabaseSessionKeyStore();
  final DatabaseSessionKeys keys;
  late final AesGcmFieldCrypto crypto;
}

class _IncrementingFieldNonceSource implements FieldNonceSource {
  int _next = 0;

  @override
  Uint8List nextNonce() {
    final start = _next;
    _next += 1;
    return Uint8List.fromList(
      List<int>.generate(12, (index) => (start + index) & 0xff),
    );
  }
}

Matcher _fieldFailure(FieldCryptoFailure failure) {
  return throwsA(
    isA<FieldCryptoException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );
}

Uint8List _hex(String value) {
  return Uint8List.fromList(
    value
        .split('')
        .fold(<String>[], (pairs, character) {
          if (pairs.isEmpty || pairs.last.length == 2) {
            pairs.add(character);
          } else {
            pairs[pairs.length - 1] += character;
          }
          return pairs;
        })
        .map((pair) => int.parse(pair, radix: 16))
        .toList(growable: false),
  );
}
