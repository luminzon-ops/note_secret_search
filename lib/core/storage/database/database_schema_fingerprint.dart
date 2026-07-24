import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

abstract final class DatabaseSchemaFingerprint {
  static Future<String> compute(DatabaseExecutor database) async {
    final inventory = <Object?>[];
    final tables = await database.rawQuery('''
      SELECT name, sql FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name
      ''');
    for (final tableRow in tables) {
      final table = tableRow['name']! as String;
      final columns = await database.rawQuery(
        'PRAGMA table_info(${_quoteIdentifier(table)})',
      );
      final canonicalColumns =
          columns
              .map(
                (row) => <Object?>[
                  row['name'],
                  row['type'].toString().toUpperCase(),
                  row['notnull'],
                  row['dflt_value']?.toString(),
                  row['pk'],
                ],
              )
              .toList()
            ..sort(
              (left, right) =>
                  (left[0]! as String).compareTo(right[0]! as String),
            );
      final foreignKeys = await database.rawQuery(
        'PRAGMA foreign_key_list(${_quoteIdentifier(table)})',
      );
      final canonicalForeignKeys =
          foreignKeys
              .map(
                (row) => <Object?>[
                  row['id'],
                  row['seq'],
                  row['table'],
                  row['from'],
                  row['to'],
                  row['on_update'],
                  row['on_delete'],
                  row['match'],
                ],
              )
              .toList()
            ..sort(_compareCanonicalRows);
      inventory.add(<Object?>[
        'table',
        table,
        canonicalColumns,
        canonicalForeignKeys,
        _normalizeSql(tableRow['sql']?.toString()),
      ]);
    }

    final objects = await database.rawQuery('''
      SELECT type, name, tbl_name, sql FROM sqlite_master
      WHERE type IN ('index', 'trigger') AND name NOT LIKE 'sqlite_%'
      ORDER BY type, name
      ''');
    for (final row in objects) {
      final type = row['type']! as String;
      final name = row['name']! as String;
      final columns = type == 'index'
          ? (await database.rawQuery(
              'PRAGMA index_info(${_quoteIdentifier(name)})',
            )).map((column) => column['name']).toList(growable: false)
          : const <Object?>[];
      inventory.add(<Object?>[
        type,
        name,
        row['tbl_name'],
        columns,
        _normalizeSql(row['sql']?.toString()),
      ]);
    }
    return sha256.convert(utf8.encode(jsonEncode(inventory))).toString();
  }
}

int _compareCanonicalRows(List<Object?> left, List<Object?> right) {
  return jsonEncode(left).compareTo(jsonEncode(right));
}

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

String? _normalizeSql(String? value) {
  return value?.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
