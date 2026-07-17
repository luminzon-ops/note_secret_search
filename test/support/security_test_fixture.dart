import 'dart:typed_data';

import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';

class SecurityTestFixture {
  SecurityTestFixture()
    : keys = DatabaseSessionKeys(
        databaseKey: Uint8List.fromList(
          List<int>.generate(32, (index) => 0xa0 + index),
        ),
        fieldKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
      ) {
    keyStore.replace(keys);
    crypto = AesGcmFieldCrypto(
      sessionKeyStore: keyStore,
      nonceSource: _IncrementingNonceSource(),
    );
  }

  final DatabaseSessionKeyStore keyStore = DatabaseSessionKeyStore();
  final DatabaseSessionKeys keys;
  late final AesGcmFieldCrypto crypto;

  void dispose() {
    keyStore.clear();
  }
}

class _IncrementingNonceSource implements FieldNonceSource {
  int _next = 0;

  @override
  Uint8List nextNonce() {
    final start = _next;
    _next += 1;
    return Uint8List.fromList(
      List<int>.generate(
        FieldEnvelopeCodec.nonceLength,
        (index) => (start + index) & 0xff,
      ),
    );
  }
}
