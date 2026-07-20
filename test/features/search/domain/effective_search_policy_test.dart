import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';

void main() {
  test('default policy covers every field and operation explicitly', () {
    final policy = EffectiveSearchPolicy(SearchConfiguration.defaults());

    for (final field in SearchSourceField.values) {
      for (final operation in SearchOperation.values) {
        final expected = field == SearchSourceField.secretPassword
            ? policy.configuration.includePasswordField &&
                  operation == SearchOperation.keyword
            : true;
        expect(
          policy.allows(field, operation),
          expected,
          reason: '${field.wireName}/${operation.name}',
        );
      }
    }
  });

  test('field switches apply consistently across all search operations', () {
    final configuration = SearchConfiguration.defaults().copyWith(
      includeTitle: false,
      includeUsername: false,
      includeUrl: false,
      includeSecretNote: false,
      includeTags: false,
      includeNoteBody: false,
      includePasswordField: false,
    );
    final policy = EffectiveSearchPolicy(configuration);

    for (final field in SearchSourceField.values) {
      for (final operation in SearchOperation.values) {
        expect(
          policy.allows(field, operation),
          isFalse,
          reason: '${field.wireName}/${operation.name}',
        );
      }
    }
  });

  test('local embedding switch leaves keyword search independent', () {
    final policy = EffectiveSearchPolicy(
      SearchConfiguration.defaults().copyWith(allowLocalEmbedding: false),
    );

    for (final field in SearchSourceField.values) {
      final keywordAllowed =
          field != SearchSourceField.secretPassword ||
          policy.configuration.includePasswordField;
      expect(policy.allows(field, SearchOperation.keyword), keywordAllowed);
      expect(policy.allows(field, SearchOperation.indexing), isFalse);
      expect(policy.allows(field, SearchOperation.semanticSearch), isFalse);
      expect(policy.allows(field, SearchOperation.aiAutoContext), isFalse);
    }
  });

  test('note summary and body share one policy switch', () {
    final policy = EffectiveSearchPolicy(
      SearchConfiguration.defaults().copyWith(includeNoteBody: false),
    );

    for (final operation in SearchOperation.values) {
      expect(policy.allows(SearchSourceField.noteSummary, operation), isFalse);
      expect(policy.allows(SearchSourceField.noteBody, operation), isFalse);
    }
  });

  test('saved update increments epoch only for index projection changes', () {
    final current = SearchConfiguration.defaults();

    expect(
      current
          .forSavedUpdate(current.copyWith(includeTags: false))
          .configurationEpoch,
      current.configurationEpoch + 1,
    );
    expect(
      current
          .forSavedUpdate(current.copyWith(maxChunkLength: 400))
          .configurationEpoch,
      current.configurationEpoch + 1,
    );
    expect(
      current
          .forSavedUpdate(current.copyWith(includePasswordField: true))
          .configurationEpoch,
      current.configurationEpoch,
    );
    expect(
      current
          .forSavedUpdate(current.copyWith(autoIndexEnabled: false))
          .configurationEpoch,
      current.configurationEpoch,
    );
    expect(
      current
          .forSavedUpdate(current.copyWith(allowExternalProviderAccess: true))
          .configurationEpoch,
      current.configurationEpoch,
    );
  });

  test(
    'configuration codec rejects unsupported versions and chunk lengths',
    () {
      expect(
        () => SearchConfiguration.fromJson(<String, Object?>{
          ...SearchConfiguration.defaults().toJson(),
          'formatVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => SearchConfiguration.fromJson(<String, Object?>{
          ...SearchConfiguration.defaults().toJson(),
          'maxChunkLength': 999,
        }),
        throwsFormatException,
      );
    },
  );
}
