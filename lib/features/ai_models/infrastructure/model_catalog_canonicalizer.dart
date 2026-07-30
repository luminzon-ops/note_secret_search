part of 'model_catalog_trust.dart';

class ModelCatalogCanonicalizer {
  const ModelCatalogCanonicalizer._();

  static String encode(Object? value) {
    final buffer = StringBuffer();
    _write(value, buffer);
    return buffer.toString();
  }

  static List<int> encodeBytes(Object? value) => utf8.encode(encode(value));

  static void _write(Object? value, StringBuffer buffer) {
    switch (value) {
      case null:
        buffer.write('null');
      case bool():
        buffer.write(value ? 'true' : 'false');
      case int():
        buffer.write(value);
      case num():
        if (!value.isFinite || value != value.roundToDouble()) {
          throw const ModelCatalogTrustException('catalog_number_not_integer');
        }
        buffer.write(value.toInt());
      case String():
        buffer.write(jsonEncode(value));
      case List<Object?>():
        buffer.write('[');
        for (var index = 0; index < value.length; index += 1) {
          if (index > 0) {
            buffer.write(',');
          }
          _write(value[index], buffer);
        }
        buffer.write(']');
      case Map<String, Object?>():
        final keys = value.keys.toList(growable: false)..sort();
        buffer.write('{');
        for (var index = 0; index < keys.length; index += 1) {
          if (index > 0) {
            buffer.write(',');
          }
          final key = keys[index];
          buffer
            ..write(jsonEncode(key))
            ..write(':');
          _write(value[key], buffer);
        }
        buffer.write('}');
      default:
        throw const ModelCatalogTrustException('catalog_value_type_invalid');
    }
  }
}
