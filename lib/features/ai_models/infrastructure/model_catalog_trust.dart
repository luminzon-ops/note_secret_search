import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_trust.dart';

export 'package:note_secret_search/features/ai_models/domain/model_catalog_trust.dart';

part 'model_catalog_canonicalizer.dart';
part 'model_catalog_ed25519.dart';
part 'model_catalog_strict_json.dart';

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
