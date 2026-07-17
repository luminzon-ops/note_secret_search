import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';

void main() {
  test('encodes and decodes the version 1 NSSF binary layout', () {
    final envelope = FieldEnvelope(
      nonce: List<int>.generate(12, (index) => index),
      ciphertext: const <int>[0xaa, 0xbb],
      tag: List<int>.generate(16, (index) => 0xf0 + index),
    );

    final encoded = FieldEnvelopeCodec.encode(envelope);

    expect(encoded, <int>[
      0x4e,
      0x53,
      0x53,
      0x46,
      0x01,
      0x01,
      0x0c,
      0x10,
      0x00,
      0x00,
      0x00,
      0x02,
      ...List<int>.generate(12, (index) => index),
      0xaa,
      0xbb,
      ...List<int>.generate(16, (index) => 0xf0 + index),
    ]);

    final decoded = FieldEnvelopeCodec.decode(encoded);
    expect(decoded.nonce, orderedEquals(envelope.nonce));
    expect(decoded.ciphertext, orderedEquals(envelope.ciphertext));
    expect(decoded.tag, orderedEquals(envelope.tag));
  });

  test('rejects legacy bytes and malformed NSSF framing', () {
    final valid = FieldEnvelopeCodec.encode(
      FieldEnvelope(
        nonce: List<int>.filled(12, 1),
        ciphertext: const <int>[2, 3],
        tag: List<int>.filled(16, 4),
      ),
    );

    expect(
      () => FieldEnvelopeCodec.decode('legacy plaintext'.codeUnits),
      throwsFormatException,
    );
    expect(
      () => FieldEnvelopeCodec.decode(valid.sublist(0, valid.length - 1)),
      throwsFormatException,
    );
    expect(
      () => FieldEnvelopeCodec.decode(<int>[...valid, 0]),
      throwsFormatException,
    );
    expect(
      () => FieldEnvelopeCodec.decode(
        List<int>.from(valid)..[4] = FieldEnvelopeCodec.version + 1,
      ),
      throwsFormatException,
    );
    expect(
      () => FieldEnvelopeCodec.decode(List<int>.from(valid)..[5] = 0xff),
      throwsFormatException,
    );
  });

  test('allows a zero-length ciphertext with an authenticated tag', () {
    final encoded = FieldEnvelopeCodec.encode(
      FieldEnvelope(
        nonce: List<int>.filled(12, 1),
        ciphertext: const <int>[],
        tag: List<int>.filled(16, 2),
      ),
    );

    final decoded = FieldEnvelopeCodec.decode(encoded);

    expect(decoded.ciphertext, isEmpty);
    expect(encoded, hasLength(40));
  });
}
