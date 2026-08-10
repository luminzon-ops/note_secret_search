part of 'model_catalog_trust.dart';

class StrictJsonParser {
  const StrictJsonParser._();

  static Object? parse(String source) => _StrictJsonReader(source).parse();
}

class _StrictJsonReader {
  _StrictJsonReader(this.source);

  final String source;
  var offset = 0;

  Object? parse() {
    _skipWhitespace();
    final result = _parseValue();
    _skipWhitespace();
    if (offset != source.length) {
      _fail('catalog_json_trailing_data');
    }
    return result;
  }

  Object? _parseValue() {
    if (offset >= source.length) {
      _fail('catalog_json_unexpected_end');
    }
    return switch (source.codeUnitAt(offset)) {
      0x7b => _parseObject(),
      0x5b => _parseArray(),
      0x22 => _parseString(),
      0x74 => _parseLiteral('true', true),
      0x66 => _parseLiteral('false', false),
      0x6e => _parseLiteral('null', null),
      _ => _parseNumber(),
    };
  }

  Map<String, Object?> _parseObject() {
    offset += 1;
    _skipWhitespace();
    final result = <String, Object?>{};
    if (_consume(0x7d)) {
      return result;
    }
    while (true) {
      if (!_peek(0x22)) {
        _fail('catalog_json_object_key_invalid');
      }
      final key = _parseString();
      if (result.containsKey(key)) {
        _fail('catalog_json_duplicate_key');
      }
      _skipWhitespace();
      _expect(0x3a);
      _skipWhitespace();
      result[key] = _parseValue();
      _skipWhitespace();
      if (_consume(0x7d)) {
        return result;
      }
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  List<Object?> _parseArray() {
    offset += 1;
    _skipWhitespace();
    final result = <Object?>[];
    if (_consume(0x5d)) {
      return result;
    }
    while (true) {
      result.add(_parseValue());
      _skipWhitespace();
      if (_consume(0x5d)) {
        return result;
      }
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  String _parseString() {
    final start = offset;
    offset += 1;
    var escaped = false;
    while (offset < source.length) {
      final code = source.codeUnitAt(offset);
      if (code < 0x20) {
        _fail('catalog_json_string_invalid');
      }
      offset += 1;
      if (escaped) {
        if (code == 0x75) {
          for (var index = 0; index < 4; index += 1) {
            if (offset >= source.length || !_isHex(source.codeUnitAt(offset))) {
              _fail('catalog_json_unicode_escape_invalid');
            }
            offset += 1;
          }
        } else if (!const <int>{
          0x22,
          0x5c,
          0x2f,
          0x62,
          0x66,
          0x6e,
          0x72,
          0x74,
        }.contains(code)) {
          _fail('catalog_json_escape_invalid');
        }
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        try {
          return jsonDecode(source.substring(start, offset)) as String;
        } on FormatException {
          _fail('catalog_json_string_invalid');
        }
      }
    }
    _fail('catalog_json_unexpected_end');
  }

  Object? _parseLiteral(String literal, Object? value) {
    if (!source.startsWith(literal, offset)) {
      _fail('catalog_json_literal_invalid');
    }
    offset += literal.length;
    return value;
  }

  num _parseNumber() {
    final start = offset;
    if (_consume(0x2d) && offset >= source.length) {
      _fail('catalog_json_number_invalid');
    }
    if (_consume(0x30)) {
      if (offset < source.length && _isDigit(source.codeUnitAt(offset))) {
        _fail('catalog_json_number_invalid');
      }
    } else {
      _consumeDigits(required: true);
    }
    if (_consume(0x2e)) {
      _consumeDigits(required: true);
    }
    if (_consume(0x65) || _consume(0x45)) {
      _consume(0x2b);
      _consume(0x2d);
      _consumeDigits(required: true);
    }
    final token = source.substring(start, offset);
    try {
      final value = jsonDecode(token);
      if (value is num && value.isFinite) {
        return value;
      }
    } on FormatException {
      // Fall through to the stable error below.
    }
    _fail('catalog_json_number_invalid');
  }

  void _consumeDigits({required bool required}) {
    final start = offset;
    while (offset < source.length && _isDigit(source.codeUnitAt(offset))) {
      offset += 1;
    }
    if (required && start == offset) {
      _fail('catalog_json_number_invalid');
    }
  }

  void _skipWhitespace() {
    while (offset < source.length &&
        const <int>{
          0x20,
          0x09,
          0x0a,
          0x0d,
        }.contains(source.codeUnitAt(offset))) {
      offset += 1;
    }
  }

  bool _peek(int code) =>
      offset < source.length && source.codeUnitAt(offset) == code;

  bool _consume(int code) {
    if (!_peek(code)) {
      return false;
    }
    offset += 1;
    return true;
  }

  void _expect(int code) {
    if (!_consume(code)) {
      _fail('catalog_json_token_invalid');
    }
  }

  Never _fail(String code) => throw ModelCatalogTrustException(code);

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isHex(int code) =>
      _isDigit(code) ||
      (code >= 0x41 && code <= 0x46) ||
      (code >= 0x61 && code <= 0x66);
}
