import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_catalog_trust.dart';

void main() {
  test('Ed25519 verifier accepts the RFC 8032 empty-message vector', () {
    final publicKey = _hex(
      'd75a980182b10ab7d54bfed3c964073a'
      '0ee172f3daa62325af021a68f707511a',
    );
    final signature = _hex(
      'e5564300c360ac729086e2cc806e828a'
      '84877f1eb8e5d974d873e06522490155'
      '5fb8821590a33bacc61e39701cf9b46b'
      'd25bf5f0595bbe24655141438e7a100b',
    );

    expect(
      Ed25519Verifier.verify(
        publicKey: publicKey,
        message: const <int>[],
        signature: signature,
      ),
      isTrue,
    );
  });

  test('canonicalizer is stable across object key order and whitespace', () {
    final first = <String, Object?>{
      'payload': <String, Object?>{'b': 2, 'a': '中文'},
      'catalog_version': 7,
      'key_id': 'phase7-v1',
    };
    final second = <String, Object?>{
      'key_id': 'phase7-v1',
      'catalog_version': 7,
      'payload': <String, Object?>{'a': '中文', 'b': 2},
    };

    expect(
      ModelCatalogCanonicalizer.encode(first),
      ModelCatalogCanonicalizer.encode(second),
    );
  });

  test('strict parser rejects duplicate object keys', () {
    expect(
      () => StrictJsonParser.parse('{"a":1,"a":2}'),
      throwsA(isA<ModelCatalogTrustException>()),
    );
  });

  test('catalog verifier rejects a tampered payload and an unknown key', () {
    final verifier = ModelCatalogVerifier(
      publicKeys: <String, List<int>>{
        'phase7-v1': _hex(
          'd75a980182b10ab7d54bfed3c964073a'
          '0ee172f3daa62325af021a68f707511a',
        ),
      },
    );
    final envelope = <String, Object?>{
      'schema_version': 1,
      'catalog_version': 1,
      'key_id': 'phase7-v1',
      'signature_algorithm': 'Ed25519',
      'payload': <String, Object?>{'models': <Object?>[]},
      'signature': base64Url.encode(List<int>.filled(64, 0)),
    };

    expect(
      () => verifier.verifyEnvelope(envelope),
      throwsA(isA<ModelCatalogTrustException>()),
    );
    expect(
      () => verifier.verifyEnvelope(<String, Object?>{
        ...envelope,
        'key_id': 'unknown',
      }),
      throwsA(isA<ModelCatalogTrustException>()),
    );
  });

  test('manifest parser binds source views to the signed artifact digest', () {
    final entry = ModelCatalogEntry.fromManifestJson(
      <String, Object?>{
        'id': 'embed-1',
        'type': 'embedding',
        'tier': 'minimum',
        'display_name': 'Embedding',
        'description': 'Test embedding',
        'size_bytes': 4,
        'min_ram_mb': 512,
        'recommended_tier': 'tier_1',
        'release_id': 'release-1',
        'tokenizer': null,
        'runtime': null,
        'artifacts': <Object?>[
          <String, Object?>{
            'artifact_id': 'model',
            'release_id': 'release-1',
            'role': 'model',
            'required': true,
            'relative_path': 'model.onnx',
            'size_bytes': 4,
            'sha256': 'sha256:${'a' * 64}',
            'origin': 'download',
            'supported_abis': <Object?>[],
            'runtime_constraints': <String, Object?>{},
            'sources': <Object?>[
              <String, Object?>{
                'source_id': 'primary',
                'label': 'Primary',
                'url': 'https://example.com/model.onnx',
                'priority': 1,
              },
            ],
          },
        ],
      },
      catalogVersion: 3,
      catalogDigest: 'digest',
    );

    expect(entry.releaseId, 'release-1');
    expect(entry.artifacts.single.id, 'model');
    expect(entry.sources.single.artifactId, 'model');
    expect(entry.sources.single.checksum, 'sha256:${'a' * 64}');
    expect(entry.catalogVersion, 3);
  });

  test(
    'manifest parser rejects duplicate artifact identity and weak checksum',
    () {
      final base = <String, Object?>{
        'id': 'embed-1',
        'type': 'embedding',
        'tier': 'minimum',
        'display_name': 'Embedding',
        'description': 'Test embedding',
        'size_bytes': 4,
        'min_ram_mb': 512,
        'recommended_tier': 'tier_1',
        'release_id': 'release-1',
        'tokenizer': null,
        'runtime': null,
        'artifacts': <Object?>[
          <String, Object?>{
            'artifact_id': 'model',
            'release_id': 'release-1',
            'role': 'model',
            'required': true,
            'relative_path': 'model.onnx',
            'size_bytes': 4,
            'sha256': 'sha256:short',
            'origin': 'download',
            'supported_abis': <Object?>[],
            'runtime_constraints': <String, Object?>{},
            'sources': <Object?>[
              <String, Object?>{
                'source_id': 'primary',
                'label': 'Primary',
                'url': 'https://example.com/model.onnx',
                'priority': 1,
              },
            ],
          },
          <String, Object?>{
            'artifact_id': 'model',
            'release_id': 'release-1',
            'role': 'sidecar',
            'required': true,
            'relative_path': 'model.onnx',
            'size_bytes': 4,
            'sha256': 'sha256:${'b' * 64}',
            'origin': 'download',
            'supported_abis': <Object?>[],
            'runtime_constraints': <String, Object?>{},
            'sources': <Object?>[
              <String, Object?>{
                'source_id': 'sidecar',
                'label': 'Sidecar',
                'url': 'https://example.com/sidecar',
                'priority': 1,
              },
            ],
          },
        ],
      };

      expect(
        () => ModelCatalogEntry.fromManifestJson(
          base,
          catalogVersion: 1,
          catalogDigest: 'digest',
        ),
        throwsA(isA<ModelCatalogFormatException>()),
      );
    },
  );
}

List<int> _hex(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), '');
  return <int>[
    for (var index = 0; index < normalized.length; index += 2)
      int.parse(normalized.substring(index, index + 2), radix: 16),
  ];
}
