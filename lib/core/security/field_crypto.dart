import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:pointycastle/export.dart';

enum FieldCryptoFailure {
  invalidEnvelope,
  authenticationFailed,
  invalidPlaintext,
}

class FieldCryptoException implements Exception {
  const FieldCryptoException(this.failure);

  final FieldCryptoFailure failure;

  @override
  String toString() => 'FieldCryptoException(${failure.name})';
}

abstract interface class FieldNonceSource {
  Uint8List nextNonce();
}

class SecureFieldNonceSource implements FieldNonceSource {
  SecureFieldNonceSource({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  Uint8List nextNonce() {
    return Uint8List.fromList(
      List<int>.generate(
        FieldEnvelopeCodec.nonceLength,
        (_) => _random.nextInt(256),
        growable: false,
      ),
    );
  }
}

class AesGcmFieldCrypto implements CryptoService {
  AesGcmFieldCrypto({
    required DatabaseSessionKeyStore sessionKeyStore,
    FieldNonceSource? nonceSource,
  }) : _sessionKeyStore = sessionKeyStore,
       _nonceSource = nonceSource ?? SecureFieldNonceSource();

  final DatabaseSessionKeyStore _sessionKeyStore;
  final FieldNonceSource _nonceSource;

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    if (plaintext == null) {
      return null;
    }
    final nonce = _nonceSource.nextNonce();
    if (nonce.length != FieldEnvelopeCodec.nonceLength) {
      throw StateError('Field nonce source returned an invalid nonce.');
    }
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final aad = _encodeAad(context);
    Uint8List? combined;
    try {
      final encrypted = _sessionKeyStore.requireCurrent().withFieldKey((key) {
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            true,
            AEADParameters(
              KeyParameter(key),
              FieldEnvelopeCodec.tagLength * 8,
              nonce,
              aad,
            ),
          );
        return cipher.process(plaintextBytes);
      });
      combined = encrypted;
      final ciphertextLength = encrypted.length - FieldEnvelopeCodec.tagLength;
      if (ciphertextLength < 0) {
        throw StateError('AES-GCM returned an invalid field payload.');
      }
      return FieldEnvelopeCodec.encode(
        FieldEnvelope(
          nonce: nonce,
          ciphertext: encrypted.sublist(0, ciphertextLength),
          tag: encrypted.sublist(ciphertextLength),
        ),
      );
    } finally {
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
      aad.fillRange(0, aad.length, 0);
      combined?.fillRange(0, combined.length, 0);
    }
  }

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    if (ciphertext == null) {
      return '';
    }
    final envelope = _decodeEnvelope(ciphertext);
    final aad = _encodeAad(context);
    final combined = Uint8List(envelope.ciphertext.length + envelope.tag.length)
      ..setRange(0, envelope.ciphertext.length, envelope.ciphertext)
      ..setRange(
        envelope.ciphertext.length,
        envelope.ciphertext.length + envelope.tag.length,
        envelope.tag,
      );
    Uint8List? plaintext;
    try {
      final decrypted = _sessionKeyStore.requireCurrent().withFieldKey((key) {
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(
              KeyParameter(key),
              FieldEnvelopeCodec.tagLength * 8,
              envelope.nonce,
              aad,
            ),
          );
        try {
          return cipher.process(combined);
        } on InvalidCipherTextException {
          throw const FieldCryptoException(
            FieldCryptoFailure.authenticationFailed,
          );
        }
      });
      plaintext = decrypted;
      try {
        return utf8.decode(decrypted, allowMalformed: false);
      } on FormatException {
        throw const FieldCryptoException(FieldCryptoFailure.invalidPlaintext);
      }
    } finally {
      aad.fillRange(0, aad.length, 0);
      combined.fillRange(0, combined.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  FieldEnvelope _decodeEnvelope(List<int> ciphertext) {
    try {
      return FieldEnvelopeCodec.decode(ciphertext);
    } on FormatException {
      throw const FieldCryptoException(FieldCryptoFailure.invalidEnvelope);
    }
  }

  Uint8List _encodeAad(FieldCryptoContext context) {
    final parts = <Uint8List>[
      Uint8List.fromList(utf8.encode(context.table)),
      Uint8List.fromList(utf8.encode(context.rowId)),
      Uint8List.fromList(utf8.encode(context.column)),
    ];
    final length = parts.fold<int>(0, (total, part) => total + 4 + part.length);
    final aad = Uint8List(length);
    final data = ByteData.sublistView(aad);
    var offset = 0;
    for (final part in parts) {
      data.setUint32(offset, part.length, Endian.big);
      offset += 4;
      aad.setRange(offset, offset + part.length, part);
      offset += part.length;
      part.fillRange(0, part.length, 0);
    }
    return aad;
  }
}

class MigrationLegacyUtf8Decoder {
  const MigrationLegacyUtf8Decoder();

  String decodeNullable(List<int>? value) {
    if (value == null || value.isEmpty) {
      return '';
    }
    return utf8.decode(value, allowMalformed: false);
  }
}
