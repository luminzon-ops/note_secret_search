part of 'model_catalog_trust.dart';

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
