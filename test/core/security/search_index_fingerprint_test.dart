import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/search_index_fingerprint.dart';

void main() {
  test('canonical text and tags are stable across line endings and casing', () {
    expect(canonicalText('  one\r\ntwo\r  '), 'one\ntwo');
    expect(
      canonicalTags(const <String>[
        ' Work ',
        'work',
        'Personal',
        '',
        'PERSONAL',
        'Ä',
        'ä',
      ]),
      const <String>['Personal', 'Work', 'Ä', 'ä'],
    );
  });

  test(
    'source and chunk fingerprints are keyed, domain separated, and stable',
    () {
      final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
      final source = sourceFingerprint(
        key: key,
        sourceType: 'secret',
        sourceId: 'source-1',
        vaultId: 'vault-1',
        fields: const <({String id, String value})>[
          (id: 'secret.title', value: 'Title'),
          (id: 'secret.tags', value: 'Work'),
        ],
      );
      final sameSource = sourceFingerprint(
        key: key,
        sourceType: 'secret',
        sourceId: 'source-1',
        vaultId: 'vault-1',
        fields: const <({String id, String value})>[
          (id: 'secret.title', value: 'Title'),
          (id: 'secret.tags', value: 'Work'),
        ],
      );
      final chunk = chunkFingerprint(
        key: key,
        sourceType: 'secret',
        sourceId: 'source-1',
        sourceField: 'secret.title',
        fieldChunkIndex: 0,
        text: 'Title',
      );

      expect(source, sameSource);
      expect(
        source,
        '00d45c3e4c54733c0caf27936b9378eb77be4d8f9815cc2c5554d351be61e20b',
      );
      expect(source, hasLength(64));
      expect(chunk, hasLength(64));
      expect(
        chunk,
        '1bf875a3eacf63b787589e98ae8c34524d51821938cb83e3c1df496759306704',
      );
      expect(chunk, isNot(source));
      expect(source, matches(RegExp(r'^[0-9a-f]{64}$')));
    },
  );

  test('fingerprint writer rejects negative unsigned values', () {
    expect(() => SearchIndexCanonicalWriter()..uint32(-1), throwsArgumentError);
  });
}
