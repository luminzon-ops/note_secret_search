import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int searchIndexFingerprintVersion = 1;
const String sourceFingerprintDomain = 'note-secret-search/source/v1';
const String chunkFingerprintDomain = 'note-secret-search/chunk/v1';

class SearchIndexCanonicalWriter {
  SearchIndexCanonicalWriter();

  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void string(String value) {
    final encoded = utf8.encode(value);
    uint32(encoded.length);
    _bytes.add(encoded);
  }

  void uint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, 'value', 'Must fit in uint32.');
    }
    _bytes.add(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  void uint64(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'Must be non-negative.');
    }
    final data = ByteData(8)..setUint64(0, value, Endian.big);
    _bytes.add(data.buffer.asUint8List());
  }

  void bytes(List<int> value) {
    uint32(value.length);
    _bytes.add(value);
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

String canonicalText(String value) {
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}

List<String> canonicalTags(Iterable<String> tags) {
  final byKey = <String, String>{};
  for (final tag in tags) {
    final normalized = canonicalText(tag);
    if (normalized.isEmpty) {
      continue;
    }
    byKey.putIfAbsent(_asciiNoCase(normalized), () => normalized);
  }
  final values = byKey.values.toList(growable: false)
    ..sort((left, right) {
      final keyCompare = _asciiNoCase(left).compareTo(_asciiNoCase(right));
      return keyCompare == 0 ? left.compareTo(right) : keyCompare;
    });
  return values;
}

String _asciiNoCase(String value) {
  final codeUnits = List<int>.of(value.codeUnits);
  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    if (codeUnit >= 0x41 && codeUnit <= 0x5a) {
      codeUnits[index] = codeUnit + 0x20;
    }
  }
  return String.fromCharCodes(codeUnits);
}

Uint8List hmacSha256(Uint8List key, List<int> input) {
  return Uint8List.fromList(Hmac(sha256, key).convert(input).bytes);
}

String hexDigest(List<int> bytes) {
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String keyedFingerprint({
  required Uint8List key,
  required String domain,
  required void Function(SearchIndexCanonicalWriter writer) write,
}) {
  return hexDigest(
    keyedFingerprintBytes(key: key, domain: domain, write: write),
  );
}

Uint8List keyedFingerprintBytes({
  required Uint8List key,
  required String domain,
  required void Function(SearchIndexCanonicalWriter writer) write,
}) {
  final writer = SearchIndexCanonicalWriter()..string(domain);
  write(writer);
  return hmacSha256(key, writer.takeBytes());
}

String sourceFingerprint({
  required Uint8List key,
  required String sourceType,
  required String sourceId,
  required String vaultId,
  required Iterable<({String id, String value})> fields,
}) {
  return keyedFingerprint(
    key: key,
    domain: sourceFingerprintDomain,
    write: (writer) {
      writer.string(sourceType);
      writer.string(sourceId);
      writer.string(vaultId);
      for (final field in fields) {
        writer.string(field.id);
        writer.string(canonicalText(field.value));
      }
    },
  );
}

String chunkFingerprint({
  required Uint8List key,
  required String sourceType,
  required String sourceId,
  required String sourceField,
  required int fieldChunkIndex,
  required String text,
}) {
  return keyedFingerprint(
    key: key,
    domain: chunkFingerprintDomain,
    write: (writer) {
      writer.string(sourceType);
      writer.string(sourceId);
      writer.string(sourceField);
      writer.uint32(fieldChunkIndex);
      writer.string(canonicalText(text));
    },
  );
}

Uint8List structuredSourceFingerprintBytes({
  required Uint8List key,
  required String sourceType,
  required String sourceId,
  required String vaultId,
  required Iterable<({String id, Iterable<String> values})> fields,
}) {
  final fieldList = fields.toList(growable: false);
  return keyedFingerprintBytes(
    key: key,
    domain: sourceFingerprintDomain,
    write: (writer) {
      writer.string(sourceType);
      writer.string(sourceId);
      writer.string(vaultId);
      writer.uint32(fieldList.length);
      for (final field in fieldList) {
        final values = field.values.toList(growable: false);
        writer.string(field.id);
        writer.uint32(values.length);
        for (final value in values) {
          writer.string(canonicalText(value));
        }
      }
    },
  );
}

Uint8List chunkFingerprintBytes({
  required Uint8List key,
  required String sourceType,
  required String sourceId,
  required String sourceField,
  required int fieldChunkIndex,
  required String text,
}) {
  return keyedFingerprintBytes(
    key: key,
    domain: chunkFingerprintDomain,
    write: (writer) {
      writer.string(sourceType);
      writer.string(sourceId);
      writer.string(sourceField);
      writer.uint32(fieldChunkIndex);
      writer.string(canonicalText(text));
    },
  );
}
