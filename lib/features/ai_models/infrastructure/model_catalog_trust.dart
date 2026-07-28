import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_trust.dart';

export 'package:note_secret_search/features/ai_models/domain/model_catalog_trust.dart';

class ModelCatalogVerifier {
  ModelCatalogVerifier({
    Map<String, List<int>>? publicKeys,
    Set<String> revokedKeyIds = const <String>{},
    Map<String, ModelCatalogKeyStatus>? keyStatuses,
    this.minimumCatalogVersion = 1,
    this.acceptedCatalogVersion,
    this.acceptedPayloadDigest,
  }) : publicKeys = Map<String, List<int>>.unmodifiable(
         publicKeys ?? _builtInPublicKeys,
       ),
       revokedKeyIds = Set<String>.unmodifiable(revokedKeyIds),
       keyStatuses = Map<String, ModelCatalogKeyStatus>.unmodifiable(
         keyStatuses ??
             <String, ModelCatalogKeyStatus>{
               for (final keyId in (publicKeys ?? _builtInPublicKeys).keys)
                 keyId: ModelCatalogKeyStatus.active,
             },
       );

  static const schemaVersion = 1;
  static const signatureAlgorithm = 'Ed25519';
  static const _domainSeparator = 'NSS-MODEL-CATALOG-V1\u0000';

  static final Map<String, List<int>> _builtInPublicKeys = <String, List<int>>{
    'phase7-v1': _decodeHex(
      'd75a980182b10ab7d54bfed3c964073a'
      '0ee172f3daa62325af021a68f707511a',
    ),
  };

  final Map<String, List<int>> publicKeys;
  final Set<String> revokedKeyIds;
  final Map<String, ModelCatalogKeyStatus> keyStatuses;
  final int minimumCatalogVersion;
  final int? acceptedCatalogVersion;
  final String? acceptedPayloadDigest;

  VerifiedModelCatalog verify(
    String rawJson, {
    int? minimumCatalogVersionOverride,
    int? acceptedCatalogVersionOverride,
    String? acceptedPayloadDigestOverride,
  }) {
    final decoded = StrictJsonParser.parse(rawJson);
    if (decoded is! Map<String, Object?>) {
      throw const ModelCatalogTrustException('catalog_root_invalid');
    }
    return verifyEnvelope(
      decoded,
      minimumCatalogVersionOverride: minimumCatalogVersionOverride,
      acceptedCatalogVersionOverride: acceptedCatalogVersionOverride,
      acceptedPayloadDigestOverride: acceptedPayloadDigestOverride,
    );
  }

  VerifiedModelCatalog verifyEnvelope(
    Map<String, Object?> envelope, {
    int? minimumCatalogVersionOverride,
    int? acceptedCatalogVersionOverride,
    String? acceptedPayloadDigestOverride,
  }) {
    _expectKeys(envelope, const <String>{
      'schema_version',
      'catalog_version',
      'key_id',
      'signature_algorithm',
      'payload',
      'signature',
    });
    final rawSchemaVersion = envelope['schema_version'];
    final rawCatalogVersion = envelope['catalog_version'];
    final keyId = envelope['key_id'];
    final algorithm = envelope['signature_algorithm'];
    final payload = envelope['payload'];
    final encodedSignature = envelope['signature'];
    if (rawSchemaVersion != schemaVersion ||
        rawCatalogVersion is! int ||
        rawCatalogVersion <
            (minimumCatalogVersionOverride ?? minimumCatalogVersion) ||
        keyId is! String ||
        keyId.isEmpty ||
        algorithm != signatureAlgorithm ||
        payload is! Map<String, Object?> ||
        encodedSignature is! String) {
      throw const ModelCatalogTrustException('catalog_envelope_invalid');
    }
    _expectKeys(payload, const <String>{'models'});
    if (payload['models'] is! List<Object?>) {
      throw const ModelCatalogTrustException('catalog_payload_invalid');
    }
    if (revokedKeyIds.contains(keyId) ||
        keyStatuses[keyId] == ModelCatalogKeyStatus.revoked) {
      throw const ModelCatalogTrustException('catalog_key_revoked');
    }
    final keyStatus = keyStatuses[keyId];
    if (keyStatus != null &&
        keyStatus != ModelCatalogKeyStatus.active &&
        keyStatus != ModelCatalogKeyStatus.overlap) {
      throw const ModelCatalogTrustException('catalog_key_revoked');
    }
    final publicKey = publicKeys[keyId];
    if (publicKey == null || publicKey.length != 32) {
      throw const ModelCatalogTrustException('catalog_key_unknown');
    }
    final signature = _decodeBase64Url(encodedSignature);
    if (signature.length != 64) {
      throw const ModelCatalogTrustException('catalog_signature_invalid');
    }

    final signedEnvelope = <String, Object?>{
      'schema_version': rawSchemaVersion,
      'catalog_version': rawCatalogVersion,
      'key_id': keyId,
      'signature_algorithm': algorithm,
      'payload': payload,
    };
    final message = <int>[
      ...utf8.encode(_domainSeparator),
      ...ModelCatalogCanonicalizer.encodeBytes(signedEnvelope),
    ];
    if (!Ed25519Verifier.verify(
      publicKey: publicKey,
      message: message,
      signature: signature,
    )) {
      throw const ModelCatalogTrustException(
        'catalog_signature_verification_failed',
      );
    }

    final payloadDigest = sha256
        .convert(ModelCatalogCanonicalizer.encodeBytes(payload))
        .toString();
    final acceptedVersion =
        acceptedCatalogVersionOverride ?? acceptedCatalogVersion;
    final acceptedDigest =
        acceptedPayloadDigestOverride ?? acceptedPayloadDigest;
    if (acceptedVersion != null) {
      if (rawCatalogVersion < acceptedVersion) {
        throw const ModelCatalogTrustException('catalog_version_rollback');
      }
      if (rawCatalogVersion == acceptedVersion &&
          acceptedDigest != null &&
          payloadDigest != acceptedDigest) {
        throw const ModelCatalogTrustException(
          'catalog_version_digest_conflict',
        );
      }
    }
    return VerifiedModelCatalog(
      schemaVersion: rawSchemaVersion as int,
      catalogVersion: rawCatalogVersion,
      keyId: keyId,
      payloadDigest: payloadDigest,
      payload: payload,
    );
  }

  static void _expectKeys(Map<String, Object?> value, Set<String> expected) {
    if (value.length != expected.length ||
        !value.keys.every(expected.contains)) {
      throw const ModelCatalogTrustException('catalog_schema_invalid');
    }
  }
}

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

class Ed25519Verifier {
  const Ed25519Verifier._();

  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _l =
      (BigInt.one << 252) +
      BigInt.parse('27742317777372353535851937790883648493');
  static final BigInt _d = _mod(
    -BigInt.from(121665) * BigInt.from(121666).modInverse(_p),
  );
  static final BigInt _sqrtMinusOne = BigInt.from(
    2,
  ).modPow((_p - BigInt.one) >> 2, _p);
  static final _EdwardsPoint _base = _EdwardsPoint.fromAffine(
    BigInt.parse(
      '15112221349535400772501151409588531511454012693041857206046113283949847762202',
    ),
    BigInt.parse(
      '46316835694926478169428394003475163141307993866256225615783033603165251855960',
    ),
  );

  static bool verify({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  }) {
    if (publicKey.length != 32 || signature.length != 64) {
      return false;
    }
    final rBytes = signature.sublist(0, 32);
    final s = _littleEndian(signature.sublist(32));
    if (s >= _l) {
      return false;
    }
    final publicPoint = _decodePoint(publicKey);
    final rPoint = _decodePoint(rBytes);
    if (publicPoint == null ||
        rPoint == null ||
        publicPoint.multiply(BigInt.from(8)).isIdentity ||
        rPoint.multiply(BigInt.from(8)).isIdentity) {
      return false;
    }
    final challenge =
        _littleEndian(
          sha512.convert(<int>[...rBytes, ...publicKey, ...message]).bytes,
        ) %
        _l;
    final left = _base.multiply(s);
    final right = rPoint.add(publicPoint.multiply(challenge));
    return left.equals(right);
  }

  static _EdwardsPoint? _decodePoint(List<int> encoded) {
    if (encoded.length != 32) {
      return null;
    }
    final bytes = Uint8List.fromList(encoded);
    final sign = (bytes[31] >> 7) & 1;
    bytes[31] &= 0x7f;
    final y = _littleEndian(bytes);
    if (y >= _p) {
      return null;
    }
    final ySquared = _mod(y * y);
    final numerator = _mod(ySquared - BigInt.one);
    final denominator = _mod(_d * ySquared + BigInt.one);
    final xSquared = _mod(numerator * denominator.modInverse(_p));
    var x = xSquared.modPow((_p + BigInt.from(3)) >> 3, _p);
    if (_mod(x * x) != xSquared) {
      x = _mod(x * _sqrtMinusOne);
    }
    if (_mod(x * x) != xSquared || (x == BigInt.zero && sign == 1)) {
      return null;
    }
    if ((x.isOdd ? 1 : 0) != sign) {
      x = _p - x;
    }
    return _EdwardsPoint.fromAffine(x, y);
  }

  static BigInt _littleEndian(List<int> bytes) {
    var value = BigInt.zero;
    for (var index = bytes.length - 1; index >= 0; index -= 1) {
      value = (value << 8) | BigInt.from(bytes[index]);
    }
    return value;
  }
}

class _EdwardsPoint {
  const _EdwardsPoint(this.x, this.y, this.z, this.t);

  factory _EdwardsPoint.fromAffine(BigInt x, BigInt y) {
    return _EdwardsPoint(x, y, BigInt.one, _mod(x * y));
  }

  static final _EdwardsPoint identity = _EdwardsPoint(
    BigInt.zero,
    BigInt.one,
    BigInt.one,
    BigInt.zero,
  );

  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;

  bool get isIdentity => _mod(x) == BigInt.zero && _mod(y - z) == BigInt.zero;

  _EdwardsPoint add(_EdwardsPoint other) {
    final a = _mod((y - x) * (other.y - other.x));
    final b = _mod((y + x) * (other.y + other.x));
    final c = _mod(BigInt.two * Ed25519Verifier._d * t * other.t);
    final d = _mod(BigInt.two * z * other.z);
    final e = _mod(b - a);
    final f = _mod(d - c);
    final g = _mod(d + c);
    final h = _mod(b + a);
    return _EdwardsPoint(_mod(e * f), _mod(g * h), _mod(f * g), _mod(e * h));
  }

  _EdwardsPoint doublePoint() {
    final a = _mod(x * x);
    final b = _mod(y * y);
    final c = _mod(BigInt.two * z * z);
    final d = _mod(-a);
    final e = _mod((x + y) * (x + y) - a - b);
    final g = _mod(d + b);
    final f = _mod(g - c);
    final h = _mod(d - b);
    return _EdwardsPoint(_mod(e * f), _mod(g * h), _mod(f * g), _mod(e * h));
  }

  _EdwardsPoint multiply(BigInt scalar) {
    var result = identity;
    var addend = this;
    var remaining = scalar;
    while (remaining > BigInt.zero) {
      if (remaining.isOdd) {
        result = result.add(addend);
      }
      addend = addend.doublePoint();
      remaining >>= 1;
    }
    return result;
  }

  bool equals(_EdwardsPoint other) {
    return _mod(x * other.z - other.x * z) == BigInt.zero &&
        _mod(y * other.z - other.y * z) == BigInt.zero;
  }
}

BigInt _mod(BigInt value) {
  final result = value % Ed25519Verifier._p;
  return result.isNegative ? result + Ed25519Verifier._p : result;
}

List<int> _decodeBase64Url(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(value)) {
    throw const ModelCatalogTrustException(
      'catalog_signature_encoding_invalid',
    );
  }
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    throw const ModelCatalogTrustException(
      'catalog_signature_encoding_invalid',
    );
  }
}

List<int> _decodeHex(String value) {
  return <int>[
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}
