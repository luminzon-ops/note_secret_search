import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';

class SqlCipherLegacyMigrationPostSwapValidator
    implements LegacyMigrationPostSwapValidator {
  const SqlCipherLegacyMigrationPostSwapValidator({
    required MigrationDatabaseFactory databaseFactory,
  }) : _databaseFactory = databaseFactory;

  final MigrationDatabaseFactory _databaseFactory;

  @override
  Future<void> validate({
    required String activePath,
    required String databasePassword,
    required String keyId,
  }) async {
    final database = await _databaseFactory.openLegacy(
      path: activePath,
      password: databasePassword,
    );
    try {
      final integrity = (await database.rawQuery('PRAGMA quick_check')).single;
      if (integrity.values.single.toString() != 'ok') {
        throw StateError('migration_post_swap_integrity_failed');
      }
      final metadata = await database.query(
        'security_metadata',
        columns: const <String>['key_id', 'migration_state'],
      );
      if (metadata.length != 1 ||
          metadata.single['key_id'] != keyId ||
          metadata.single['migration_state'] != 'validated') {
        throw StateError('migration_post_swap_metadata_failed');
      }
    } finally {
      await database.close();
    }
  }
}
