import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

part 'legacy_database_migrator_fakes.dart';
part 'legacy_database_migrator_rejection_cases.dart';
part 'legacy_database_migrator_success_cases.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  _registerLegacyDatabaseMigratorSuccessCases();
  _registerLegacyDatabaseMigratorRejectionCases();
}

Future<int> _count(Database database, String table) async {
  final row = (await database.rawQuery(
    'SELECT COUNT(*) AS count FROM $table',
  )).single;
  return row['count']! as int;
}

Future<void> _expectEncryptedFields(
  Database database,
  AesGcmFieldCrypto crypto,
  Map<String, String?> expected,
) async {
  final secretRows = await database.query('secret_items');
  for (final row in secretRows) {
    final id = row['id']! as String;
    for (final field in const <EncryptedDatabaseField>[
      EncryptedDatabaseField.secretUsername,
      EncryptedDatabaseField.secretPassword,
      EncryptedDatabaseField.secretWebsiteUrl,
      EncryptedDatabaseField.secretNote,
    ]) {
      final expectedValue = expected['$id.${field.column}'];
      final ciphertext = row[field.column] as List<int>?;
      if (expectedValue == null) {
        expect(ciphertext, isNull);
      } else {
        expect(ciphertext, isNot(equals(utf8.encode(expectedValue))));
        expect(
          crypto.decryptField(ciphertext, field: field, rowId: id),
          expectedValue,
        );
      }
    }
  }

  final noteRows = await database.query('note_items');
  for (final row in noteRows) {
    final id = row['id']! as String;
    for (final field in const <EncryptedDatabaseField>[
      EncryptedDatabaseField.noteContent,
      EncryptedDatabaseField.noteSummary,
    ]) {
      final expectedValue = expected['$id.${field.column}'];
      final ciphertext = row[field.column] as List<int>?;
      if (expectedValue == null) {
        expect(ciphertext, isNull);
      } else {
        expect(
          crypto.decryptField(ciphertext, field: field, rowId: id),
          expectedValue,
        );
      }
    }
  }

  final protectedRows =
      <({String table, String idColumn, EncryptedDatabaseField field})>[
        (
          table: 'provider_configs',
          idColumn: 'id',
          field: EncryptedDatabaseField.providerConfig,
        ),
        (
          table: 'sync_accounts',
          idColumn: 'id',
          field: EncryptedDatabaseField.syncAccountConfig,
        ),
        (
          table: 'app_settings',
          idColumn: 'key',
          field: EncryptedDatabaseField.appSettingValue,
        ),
      ];
  for (final protected in protectedRows) {
    for (final row in await database.query(protected.table)) {
      final id = row[protected.idColumn]! as String;
      expect(
        crypto.decryptField(
          row[protected.field.column] as List<int>,
          field: protected.field,
          rowId: id,
        ),
        expected['$id.${protected.field.column}'],
      );
    }
  }
}
