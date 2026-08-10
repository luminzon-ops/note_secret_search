import 'dart:typed_data';

const int float32VectorFormatVersion = 1;

enum Float32VectorDecodeError {
  invalidDimension,
  lengthMismatch,
  nonFiniteValue,
}

class Float32VectorDecodeResult {
  const Float32VectorDecodeResult.valid(this.values) : error = null;

  const Float32VectorDecodeResult.invalid(this.error)
    : values = const <double>[];

  final List<double> values;
  final Float32VectorDecodeError? error;

  bool get isValid => error == null;
}

abstract final class Float32VectorCodec {
  static Uint8List encode(List<double> values) {
    if (values.isEmpty) {
      throw ArgumentError.value(values.length, 'values', 'Must not be empty.');
    }
    final bytes = ByteData(values.length * 4);
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (!value.isFinite) {
        throw ArgumentError.value(value, 'values', 'Values must be finite.');
      }
      bytes.setFloat32(index * 4, value, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static Float32VectorDecodeResult decode(
    List<int> blob, {
    required int expectedDimension,
  }) {
    if (expectedDimension <= 0) {
      return const Float32VectorDecodeResult.invalid(
        Float32VectorDecodeError.invalidDimension,
      );
    }
    if (blob.length != expectedDimension * 4) {
      return const Float32VectorDecodeResult.invalid(
        Float32VectorDecodeError.lengthMismatch,
      );
    }

    final bytes = Uint8List.fromList(blob);
    final data = ByteData.sublistView(bytes);
    final values = List<double>.filled(expectedDimension, 0);
    for (var index = 0; index < expectedDimension; index++) {
      final value = data.getFloat32(index * 4, Endian.little);
      if (!value.isFinite) {
        return const Float32VectorDecodeResult.invalid(
          Float32VectorDecodeError.nonFiniteValue,
        );
      }
      values[index] = value;
    }
    return Float32VectorDecodeResult.valid(List<double>.unmodifiable(values));
  }
}
