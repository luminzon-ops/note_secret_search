import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';

void main() {
  test('float32-le-v1 encodes deterministic little-endian bytes', () {
    final encoded = Float32VectorCodec.encode(const <double>[1, -2.5, 0.25]);

    expect(
      encoded,
      Uint8List.fromList(const <int>[
        0x00,
        0x00,
        0x80,
        0x3f,
        0x00,
        0x00,
        0x20,
        0xc0,
        0x00,
        0x00,
        0x80,
        0x3e,
      ]),
    );
    expect(
      Float32VectorCodec.decode(encoded, expectedDimension: 3).values,
      closeToList(const <double>[1, -2.5, 0.25]),
    );
  });

  test('codec rejects empty and non-finite vectors on write', () {
    expect(
      () => Float32VectorCodec.encode(const <double>[]),
      throwsArgumentError,
    );
    expect(
      () => Float32VectorCodec.encode(const <double>[double.nan]),
      throwsArgumentError,
    );
    expect(
      () => Float32VectorCodec.encode(const <double>[double.infinity]),
      throwsArgumentError,
    );
  });

  test(
    'decode classifies invalid dimension, length, and non-finite values',
    () {
      expect(
        Float32VectorCodec.decode(Uint8List(4), expectedDimension: 0).error,
        Float32VectorDecodeError.invalidDimension,
      );
      expect(
        Float32VectorCodec.decode(Uint8List(4), expectedDimension: 2).error,
        Float32VectorDecodeError.lengthMismatch,
      );

      final infinity = ByteData(4)..setUint32(0, 0x7f800000, Endian.little);
      expect(
        Float32VectorCodec.decode(
          infinity.buffer.asUint8List(),
          expectedDimension: 1,
        ).error,
        Float32VectorDecodeError.nonFiniteValue,
      );
    },
  );
}

Matcher closeToList(List<double> expected) {
  return predicate<List<double>>((actual) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < actual.length; index++) {
      if ((actual[index] - expected[index]).abs() > 0.000001) {
        return false;
      }
    }
    return true;
  });
}
