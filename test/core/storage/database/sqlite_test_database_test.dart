import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test('repository test database uses the production schema manager', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);

    final snapshot = await database.run<_SchemaSnapshot>((connection) async {
      return (
        version: await _pragmaInt(connection, 'user_version'),
        foreignKeys: await _pragmaInt(connection, 'foreign_keys'),
        ledger: await connection.query('schema_migrations'),
        defaultVaults: await connection.query(
          'vaults',
          columns: const <String>['id'],
          where: 'is_default = 1',
        ),
      );
    });

    expect(snapshot.version, DatabaseSchemaManager.latestVersion);
    expect(snapshot.foreignKeys, 1);
    expect(snapshot.ledger, hasLength(1));
    expect(snapshot.defaultVaults, const <Map<String, Object?>>[
      <String, Object?>{'id': 'default'},
    ]);
  });
}

typedef _SchemaSnapshot = ({
  int version,
  int foreignKeys,
  List<Map<String, Object?>> ledger,
  List<Map<String, Object?>> defaultVaults,
});

Future<int> _pragmaInt(Database database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single as int;
}
