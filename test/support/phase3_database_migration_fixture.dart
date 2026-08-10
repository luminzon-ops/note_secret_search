import 'dart:typed_data';

import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'historical_database_schema.dart';
import 'legacy_database_fixture.dart';

class Phase3DatabaseMigrationFixture {
  Phase3DatabaseMigrationFixture({
    required LegacyDatabaseFixture legacyFixture,
    required DatabaseSessionKeyStore keyStore,
    required this.crypto,
  }) : _legacyFixture = legacyFixture,
       _keyStore = keyStore;

  final LegacyDatabaseFixture _legacyFixture;
  final DatabaseSessionKeyStore _keyStore;
  final AesGcmFieldCrypto crypto;

  String get databasePath => _legacyFixture.pendingPath;

  String get sourcePath => _legacyFixture.sourcePath;

  LegacyFixtureVersion get sourceVersion => _legacyFixture.version;

  Future<void> dispose() async {
    _keyStore.clear();
    await _legacyFixture.dispose();
  }
}

Future<Phase3DatabaseMigrationFixture> createPhase3DatabaseMigrationFixture(
  LegacyFixtureVersion version,
) async {
  if (!legacyMigrationSourceVersions.contains(version)) {
    throw ArgumentError.value(
      version,
      'version',
      'Phase 3 end-to-end fixtures must start from schema v1-v3.',
    );
  }
  final legacyFixture = await createLegacyDatabaseFixture(version);
  final keys = DatabaseSessionKeys(
    databaseKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
    fieldKey: Uint8List.fromList(
      List<int>.generate(32, (index) => 0x80 + index),
    ),
  );
  final keyStore = DatabaseSessionKeyStore()..replace(keys);
  final crypto = AesGcmFieldCrypto(sessionKeyStore: keyStore);
  try {
    final migrator = LegacyDatabaseMigrator(
      databaseFactory: const _Phase3MigrationDatabaseFactory(),
      cryptoService: crypto,
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_013),
    );
    final result = await migrator.migrate(
      sourcePath: legacyFixture.sourcePath,
      pendingPath: legacyFixture.pendingPath,
      legacyPassword: 'legacy-password',
      databasePassword: 'database-password',
      keyId: '123e4567-e89b-42d3-a456-426614174000',
    );
    if (result.sourceSchemaVersion != version.schemaVersion ||
        result.targetSchemaVersion != 4 ||
        result.quickCheck != 'ok') {
      throw StateError('Phase 2 fixture migration did not reach valid v4.');
    }
    return Phase3DatabaseMigrationFixture(
      legacyFixture: legacyFixture,
      keyStore: keyStore,
      crypto: crypto,
    );
  } catch (_) {
    keyStore.clear();
    await legacyFixture.dispose();
    rethrow;
  }
}

class _Phase3MigrationDatabaseFactory implements MigrationDatabaseFactory {
  const _Phase3MigrationDatabaseFactory();

  @override
  Future<Database> openLegacyForCheckpoint({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: false, singleInstance: false),
    );
  }

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        singleInstance: false,
      ),
    );
  }
}
