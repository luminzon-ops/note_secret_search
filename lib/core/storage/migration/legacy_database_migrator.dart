import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

typedef _FieldIdentity = ({String table, String rowId, String column});

abstract interface class MigrationDatabaseFactory {
  Future<Database> openLegacy({required String path, required String password});

  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  });
}

class LegacyDatabaseMigrationResult {
  const LegacyDatabaseMigrationResult({
    required this.sourceSchemaVersion,
    required this.targetSchemaVersion,
    required this.quickCheck,
    required this.preservedRowCounts,
  });

  final int sourceSchemaVersion;
  final int targetSchemaVersion;
  final String quickCheck;
  final Map<String, int> preservedRowCounts;
}

enum LegacyDatabaseMigrationFailure { unsupportedSourceVersion }

class LegacyDatabaseMigrationException implements Exception {
  const LegacyDatabaseMigrationException(this.failure);

  final LegacyDatabaseMigrationFailure failure;

  @override
  String toString() => 'LegacyDatabaseMigrationException(${failure.name})';
}

class LegacyDatabaseMigrator {
  LegacyDatabaseMigrator({
    required MigrationDatabaseFactory databaseFactory,
    required CryptoService cryptoService,
    DateTime Function()? now,
    MigrationLegacyUtf8Decoder legacyDecoder =
        const MigrationLegacyUtf8Decoder(),
  }) : _databaseFactory = databaseFactory,
       _cryptoService = cryptoService,
       _now = now ?? DateTime.now,
       _legacyDecoder = legacyDecoder;

  static const targetSchemaVersion = 4;

  static const _preservedTables = <String>[
    DatabaseSchema.vaults,
    DatabaseSchema.categories,
    DatabaseSchema.tags,
    DatabaseSchema.secretItems,
    DatabaseSchema.noteItems,
    DatabaseSchema.itemTags,
    DatabaseSchema.modelRegistry,
    DatabaseSchema.providerConfigs,
    DatabaseSchema.syncAccounts,
    DatabaseSchema.appSettings,
    DatabaseSchema.chatSessions,
    DatabaseSchema.chatMessages,
  ];

  final MigrationDatabaseFactory _databaseFactory;
  final CryptoService _cryptoService;
  final DateTime Function() _now;
  final MigrationLegacyUtf8Decoder _legacyDecoder;

  Future<LegacyDatabaseMigrationResult> migrate({
    required String sourcePath,
    required String pendingPath,
    required String legacyPassword,
    required String databasePassword,
    required String keyId,
  }) async {
    if (sourcePath == pendingPath) {
      throw ArgumentError('Source and pending database paths must differ.');
    }
    if (keyId.isEmpty || keyId != keyId.trim()) {
      throw ArgumentError.value(keyId, 'keyId');
    }

    final source = await _databaseFactory.openLegacy(
      path: sourcePath,
      password: legacyPassword,
    );
    Database? pending;
    var completed = false;
    var ownsPendingFileSet = false;
    try {
      final sourceVersion = await _readUserVersion(source);
      if (sourceVersion < 1 || sourceVersion >= targetSchemaVersion) {
        throw const LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailure.unsupportedSourceVersion,
        );
      }
      final sourceTables = await _readTableNames(source);
      ownsPendingFileSet = true;
      await _deletePendingFileSet(pendingPath);
      pending = await _databaseFactory.openPending(
        path: pendingPath,
        password: databasePassword,
        version: targetSchemaVersion,
        onCreate: _createTargetSchema,
      );

      final preservedCounts = <String, int>{};
      final expectedFieldDigests = <_FieldIdentity, Digest?>{};
      await pending.transaction((transaction) async {
        for (final table in _preservedTables) {
          final rows = sourceTables.contains(table)
              ? await source.query(table)
              : const <Map<String, Object?>>[];
          preservedCounts[table] = rows.length;
          for (final row in rows) {
            final transformed = _transformRow(table, row, expectedFieldDigests);
            await transaction.insert(table, transformed);
          }
        }
        await transaction.insert(DatabaseSchema.securityMetadata, {
          'key_id': keyId,
          'source_schema_version': sourceVersion,
          'field_envelope_version': 1,
          'migration_state': 'validated',
          'migrated_at': _now().millisecondsSinceEpoch,
        });
      });

      await _validatePreservedCounts(pending, preservedCounts);
      await _validateEncryptedFields(pending, expectedFieldDigests);
      final quickCheck = await _readQuickCheck(pending);
      if (quickCheck != 'ok') {
        throw StateError('Pending database integrity validation failed.');
      }

      final result = LegacyDatabaseMigrationResult(
        sourceSchemaVersion: sourceVersion,
        targetSchemaVersion: targetSchemaVersion,
        quickCheck: quickCheck,
        preservedRowCounts: Map.unmodifiable(preservedCounts),
      );
      completed = true;
      return result;
    } finally {
      try {
        await pending?.close();
      } finally {
        try {
          await source.close();
        } finally {
          if (ownsPendingFileSet && !completed) {
            await _deletePendingFileSet(pendingPath);
          }
        }
      }
    }
  }

  Future<void> _deletePendingFileSet(String pendingPath) async {
    for (final path in <String>[
      pendingPath,
      '$pendingPath-wal',
      '$pendingPath-shm',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }

  Future<void> _createTargetSchema(Database database, int version) async {
    final batch = database.batch();
    for (final statement in DatabaseSchema.createStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  Map<String, Object?> _transformRow(
    String table,
    Map<String, Object?> sourceRow,
    Map<_FieldIdentity, Digest?> expectedFieldDigests,
  ) {
    final row = Map<String, Object?>.from(sourceRow);
    switch (table) {
      case DatabaseSchema.secretItems:
        _transformFields(
          row,
          rowId: row['id']! as String,
          fields: const [
            EncryptedDatabaseField.secretUsername,
            EncryptedDatabaseField.secretPassword,
            EncryptedDatabaseField.secretWebsiteUrl,
            EncryptedDatabaseField.secretNote,
          ],
          expectedFieldDigests: expectedFieldDigests,
        );
      case DatabaseSchema.noteItems:
        _transformFields(
          row,
          rowId: row['id']! as String,
          fields: const [
            EncryptedDatabaseField.noteContent,
            EncryptedDatabaseField.noteSummary,
          ],
          expectedFieldDigests: expectedFieldDigests,
        );
      case DatabaseSchema.providerConfigs:
        _transformFields(
          row,
          rowId: row['id']! as String,
          fields: const [EncryptedDatabaseField.providerConfig],
          expectedFieldDigests: expectedFieldDigests,
        );
        _requireJsonObject(
          _cryptoService.decryptField(
            row[EncryptedDatabaseField.providerConfig.column] as List<int>,
            field: EncryptedDatabaseField.providerConfig,
            rowId: row['id']! as String,
          ),
        );
      case DatabaseSchema.syncAccounts:
        _transformFields(
          row,
          rowId: row['id']! as String,
          fields: const [EncryptedDatabaseField.syncAccountConfig],
          expectedFieldDigests: expectedFieldDigests,
        );
      case DatabaseSchema.appSettings:
        _transformFields(
          row,
          rowId: row['key']! as String,
          fields: const [EncryptedDatabaseField.appSettingValue],
          expectedFieldDigests: expectedFieldDigests,
        );
      case DatabaseSchema.modelRegistry:
        row.putIfAbsent('artifact_paths_json', () => null);
        row.putIfAbsent('integrity_status', () => 'unknown');
    }
    return row;
  }

  void _transformFields(
    Map<String, Object?> row, {
    required String rowId,
    required List<EncryptedDatabaseField> fields,
    required Map<_FieldIdentity, Digest?> expectedFieldDigests,
  }) {
    for (final field in fields) {
      final legacyValue = row[field.column] as List<int>?;
      final plaintext = legacyValue == null
          ? null
          : _legacyDecoder.decodeNullable(legacyValue);
      expectedFieldDigests[(
        table: field.table,
        rowId: rowId,
        column: field.column,
      )] = plaintext == null
          ? null
          : sha256.convert(utf8.encode(plaintext));
      row[field.column] = _cryptoService.encryptField(
        plaintext,
        field: field,
        rowId: rowId,
      );
    }
  }

  Future<void> _validatePreservedCounts(
    Database database,
    Map<String, int> expected,
  ) async {
    for (final entry in expected.entries) {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS row_count FROM ${entry.key}',
      );
      if (rows.single['row_count'] != entry.value) {
        throw StateError('Pending database row-count validation failed.');
      }
    }
  }

  Future<void> _validateEncryptedFields(
    Database database,
    Map<_FieldIdentity, Digest?> expectedFieldDigests,
  ) async {
    for (final tableFields in const <String, List<EncryptedDatabaseField>>{
      DatabaseSchema.secretItems: [
        EncryptedDatabaseField.secretUsername,
        EncryptedDatabaseField.secretPassword,
        EncryptedDatabaseField.secretWebsiteUrl,
        EncryptedDatabaseField.secretNote,
      ],
      DatabaseSchema.noteItems: [
        EncryptedDatabaseField.noteContent,
        EncryptedDatabaseField.noteSummary,
      ],
      DatabaseSchema.providerConfigs: [EncryptedDatabaseField.providerConfig],
      DatabaseSchema.syncAccounts: [EncryptedDatabaseField.syncAccountConfig],
      DatabaseSchema.appSettings: [EncryptedDatabaseField.appSettingValue],
    }.entries) {
      final idColumn = tableFields.key == DatabaseSchema.appSettings
          ? 'key'
          : 'id';
      for (final row in await database.query(tableFields.key)) {
        final rowId = row[idColumn]! as String;
        for (final field in tableFields.value) {
          final identity = (
            table: field.table,
            rowId: rowId,
            column: field.column,
          );
          if (!expectedFieldDigests.containsKey(identity)) {
            throw StateError('Pending database field inventory is incomplete.');
          }
          final expectedDigest = expectedFieldDigests[identity];
          final value = row[field.column] as List<int>?;
          if (value == null) {
            if (expectedDigest != null) {
              throw StateError('Pending database plaintext validation failed.');
            }
            continue;
          }
          final plaintext = _cryptoService.decryptField(
            value,
            field: field,
            rowId: rowId,
          );
          if (expectedDigest == null ||
              sha256.convert(utf8.encode(plaintext)) != expectedDigest) {
            throw StateError('Pending database plaintext validation failed.');
          }
        }
      }
    }
  }

  Future<int> _readUserVersion(Database database) async {
    final row = (await database.rawQuery('PRAGMA user_version')).single;
    return row.values.single as int;
  }

  Future<Set<String>> _readTableNames(Database database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((row) => row['name']! as String).toSet();
  }

  Future<String> _readQuickCheck(Database database) async {
    final row = (await database.rawQuery('PRAGMA quick_check')).single;
    return row.values.single.toString();
  }

  void _requireJsonObject(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Provider configuration must be an object.');
    }
  }
}
