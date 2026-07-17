import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SyncAccountConfiguration {
  const SyncAccountConfiguration({
    required this.id,
    required this.providerType,
    required this.configJson,
    required this.lastSyncAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String providerType;
  final String configJson;
  final DateTime? lastSyncAt;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class SqliteProtectedConfigurationRepository {
  SqliteProtectedConfigurationRepository({
    required AppDatabase database,
    required CryptoService cryptoService,
  }) : _database = database,
       _cryptoService = cryptoService;

  final AppDatabase _database;
  final CryptoService _cryptoService;

  Future<void> saveSyncAccount(SyncAccountConfiguration account) async {
    _validateIdentifier(account.id, 'account.id');
    _validateIdentifier(account.providerType, 'account.providerType');
    _validateIdentifier(account.status, 'account.status');
    final encryptedConfig = _cryptoService.encryptField(
      account.configJson,
      field: EncryptedDatabaseField.syncAccountConfig,
      rowId: account.id,
    );
    if (encryptedConfig == null) {
      throw StateError('Sync account config could not be encrypted.');
    }

    await _database.run((db) async {
      await db.insert(DatabaseSchema.syncAccounts, <String, Object?>{
        'id': account.id,
        'provider_type': account.providerType,
        'encrypted_config': encryptedConfig,
        'last_sync_at': account.lastSyncAt?.millisecondsSinceEpoch,
        'status': account.status,
        'created_at': account.createdAt.millisecondsSinceEpoch,
        'updated_at': account.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<SyncAccountConfiguration?> loadSyncAccount(String id) async {
    _validateIdentifier(id, 'id');
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.syncAccounts,
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }

      final row = rows.single;
      return SyncAccountConfiguration(
        id: row['id']! as String,
        providerType: row['provider_type']! as String,
        configJson: _cryptoService.decryptField(
          row['encrypted_config'] as List<int>?,
          field: EncryptedDatabaseField.syncAccountConfig,
          rowId: row['id']! as String,
        ),
        lastSyncAt: _dateTimeOrNull(row['last_sync_at']),
        status: row['status']! as String,
        createdAt: _dateTime(row['created_at']),
        updatedAt: _dateTime(row['updated_at']),
      );
    });
  }

  Future<void> saveAppSetting({
    required String key,
    required String value,
  }) async {
    _validateIdentifier(key, 'key');
    final encryptedValue = _cryptoService.encryptField(
      value,
      field: EncryptedDatabaseField.appSettingValue,
      rowId: key,
    );
    if (encryptedValue == null) {
      throw StateError('App setting value could not be encrypted.');
    }

    await _database.run((db) async {
      await db.insert(DatabaseSchema.appSettings, <String, Object?>{
        'key': key,
        'value_ciphertext': encryptedValue,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<String?> loadAppSetting(String key) async {
    _validateIdentifier(key, 'key');
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.appSettings,
        where: 'key = ?',
        whereArgs: <Object>[key],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final row = rows.single;
      return _cryptoService.decryptField(
        row['value_ciphertext'] as List<int>?,
        field: EncryptedDatabaseField.appSettingValue,
        rowId: row['key']! as String,
      );
    });
  }

  DateTime _dateTime(Object? value) {
    if (value is! int) {
      throw const FormatException('Invalid protected configuration timestamp.');
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  DateTime? _dateTimeOrNull(Object? value) {
    return value == null ? null : _dateTime(value);
  }

  void _validateIdentifier(String value, String name) {
    if (value.isEmpty || value != value.trim()) {
      throw ArgumentError.value(
        value,
        name,
        'Must be non-empty and contain no surrounding whitespace.',
      );
    }
  }
}
