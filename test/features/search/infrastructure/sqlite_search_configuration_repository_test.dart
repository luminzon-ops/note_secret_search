import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_search_configuration_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'migration conservatively merges legacy scope and index settings',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'search.scope.include_secret_note': true,
        'search.index.include_secret_notes': false,
        'search.scope.include_note_body': true,
        'search.index.include_note_body': false,
        'search.scope.include_password_field': true,
        'search.index.max_chunk_length': 400,
      });
      final preferences = await SharedPreferences.getInstance();
      String? encryptedValue;
      final repository = SqliteSearchConfigurationRepository(
        preferences: preferences,
        loadAppSetting: (_) async => encryptedValue,
        saveAppSetting: ({required key, required value}) async {
          expect(key, searchConfigurationSettingKey);
          encryptedValue = value;
        },
      );

      final migrated = await repository.load();

      expect(migrated.includeSecretNote, isFalse);
      expect(migrated.includeNoteBody, isFalse);
      expect(migrated.includePasswordField, isTrue);
      expect(migrated.maxChunkLength, 400);
      expect(migrated.configurationEpoch, 1);
      expect(
        SearchConfiguration.fromJson(
          (jsonDecode(encryptedValue!) as Map).cast<String, Object?>(),
        ).toJson(),
        migrated.toJson(),
      );
      expect(
        preferences.getKeys(),
        isNot(contains('search.scope.include_secret_note')),
      );
      expect(
        preferences.getKeys(),
        isNot(contains('search.index.include_secret_notes')),
      );
    },
  );

  test(
    'save increments epoch only when the index projection changes',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      String? encryptedValue = jsonEncode(
        SearchConfiguration.defaults().toJson(),
      );
      final repository = SqliteSearchConfigurationRepository(
        preferences: preferences,
        loadAppSetting: (_) async => encryptedValue,
        saveAppSetting: ({required key, required value}) async {
          encryptedValue = value;
        },
      );

      final passwordOnly = await repository.save(
        SearchConfiguration.defaults().copyWith(includePasswordField: true),
      );
      final projectionChange = await repository.save(
        passwordOnly.copyWith(includeTags: false),
      );

      expect(passwordOnly.configurationEpoch, 1);
      expect(projectionChange.configurationEpoch, 2);
    },
  );
}
