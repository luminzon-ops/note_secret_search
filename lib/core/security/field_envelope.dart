import 'dart:typed_data';

class FieldEnvelope {
  FieldEnvelope({
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> tag,
  }) : nonce = _copyBytes(nonce, 'nonce'),
       ciphertext = _copyBytes(ciphertext, 'ciphertext'),
       tag = _copyBytes(tag, 'tag') {
    if (this.nonce.length != FieldEnvelopeCodec.nonceLength) {
      throw ArgumentError.value(
        this.nonce.length,
        'nonce',
        'Must contain ${FieldEnvelopeCodec.nonceLength} bytes.',
      );
    }
    if (this.tag.length != FieldEnvelopeCodec.tagLength) {
      throw ArgumentError.value(
        this.tag.length,
        'tag',
        'Must contain ${FieldEnvelopeCodec.tagLength} bytes.',
      );
    }
  }

  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;

  static Uint8List _copyBytes(List<int> value, String name) {
    if (value.any((byte) => byte < 0 || byte > 0xff)) {
      throw ArgumentError.value(value, name, 'Must contain byte values.');
    }
    return Uint8List.fromList(value);
  }
}

abstract final class FieldEnvelopeCodec {
  static const int version = 1;
  static const int aes256GcmAlgorithm = 1;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int _headerLength = 12;
  static const List<int> _magic = <int>[0x4e, 0x53, 0x53, 0x46];

  static Uint8List encode(FieldEnvelope envelope) {
    if (envelope.ciphertext.length > 0xffffffff) {
      throw ArgumentError.value(
        envelope.ciphertext.length,
        'ciphertext',
        'Is too large for the NSSF envelope.',
      );
    }
    final encoded = Uint8List(
      _headerLength +
          envelope.nonce.length +
          envelope.ciphertext.length +
          envelope.tag.length,
    );
    encoded.setRange(0, _magic.length, _magic);
    encoded[4] = version;
    encoded[5] = aes256GcmAlgorithm;
    encoded[6] = envelope.nonce.length;
    encoded[7] = envelope.tag.length;
    ByteData.sublistView(
      encoded,
    ).setUint32(8, envelope.ciphertext.length, Endian.big);
    var offset = _headerLength;
    encoded.setRange(offset, offset + envelope.nonce.length, envelope.nonce);
    offset += envelope.nonce.length;
    encoded.setRange(
      offset,
      offset + envelope.ciphertext.length,
      envelope.ciphertext,
    );
    offset += envelope.ciphertext.length;
    encoded.setRange(offset, offset + envelope.tag.length, envelope.tag);
    return encoded;
  }

  static FieldEnvelope decode(List<int> encoded) {
    if (encoded.length < _headerLength ||
        encoded.any((byte) => byte < 0 || byte > 0xff)) {
      throw const FormatException('Invalid NSSF field envelope.');
    }
    final bytes = Uint8List.fromList(encoded);
    if (!_hasMagic(bytes) ||
        bytes[4] != version ||
        bytes[5] != aes256GcmAlgorithm ||
        bytes[6] != nonceLength ||
        bytes[7] != tagLength) {
      throw const FormatException('Unsupported NSSF field envelope.');
    }
    final ciphertextLength = ByteData.sublistView(
      bytes,
    ).getUint32(8, Endian.big);
    final expectedLength =
        _headerLength + nonceLength + ciphertextLength + tagLength;
    if (bytes.length != expectedLength) {
      throw const FormatException('Invalid NSSF field envelope length.');
    }

    const nonceStart = _headerLength;
    const ciphertextStart = nonceStart + nonceLength;
    final tagStart = ciphertextStart + ciphertextLength;
    return FieldEnvelope(
      nonce: bytes.sublist(nonceStart, ciphertextStart),
      ciphertext: bytes.sublist(ciphertextStart, tagStart),
      tag: bytes.sublist(tagStart),
    );
  }

  static bool _hasMagic(Uint8List bytes) {
    for (var index = 0; index < _magic.length; index += 1) {
      if (bytes[index] != _magic[index]) {
        return false;
      }
    }
    return true;
  }
}
