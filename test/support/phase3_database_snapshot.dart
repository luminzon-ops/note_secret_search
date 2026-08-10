import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Map<String, String?>> capturePhase3ProtectedBytes(
  Database database,
) async {
  final values = <String, String?>{};
  for (final table in _protectedFields.entries) {
    final idColumn = table.key == 'app_settings' ? 'key' : 'id';
    final rows = await database.query(
      table.key,
      columns: <String>[idColumn, ...table.value.keys],
      orderBy: '$idColumn ASC',
    );
    for (final row in rows) {
      for (final column in table.value.keys) {
        final bytes = row[column] as List<int>?;
        values['${table.key}.${row[idColumn]}.$column'] = bytes == null
            ? null
            : base64Encode(bytes);
      }
    }
  }
  return values;
}

Future<String> phase3CanonicalDataDigest(
  Database database,
  CryptoService crypto,
) async {
  final inventory = <Object?>[];
  for (final table in _canonicalTableOrder) {
    final rows = await database.query(table, orderBy: _tableOrderBy[table]);
    final canonicalRows = <Object?>[];
    for (final row in rows) {
      final rowId = _rowId(table, row);
      final columns = row.keys.toList()..sort();
      canonicalRows.add(<Object?>[
        for (final column in columns)
          <Object?>[
            column,
            _canonicalValue(
              table,
              column,
              row[column],
              rowId: rowId,
              crypto: crypto,
            ),
          ],
      ]);
    }
    inventory.add(<Object?>[table, canonicalRows]);
  }
  return sha256.convert(utf8.encode(jsonEncode(inventory))).toString();
}

Future<int> phase3PragmaInt(Database database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single as int;
}

Future<Set<String>> phase3ObjectNames(Database database, String type) async {
  final rows = await database.rawQuery(
    'SELECT name FROM sqlite_master '
    'WHERE type = ? AND name NOT LIKE ?',
    <Object>[type, 'sqlite_%'],
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<List<String>> phase3QueryPlanDetails(
  Database database,
  String sql,
  List<Object?> arguments,
) async {
  final rows = await database.rawQuery('EXPLAIN QUERY PLAN $sql', arguments);
  return rows.map((row) => row['detail']! as String).toList(growable: false);
}

Object _canonicalValue(
  String table,
  String column,
  Object? value, {
  required String rowId,
  required CryptoService crypto,
}) {
  final protectedField = _protectedFields[table]?[column];
  if (protectedField != null) {
    if (value == null) {
      return const <Object?>['null'];
    }
    final plaintext = crypto.decryptField(
      value as List<int>,
      field: protectedField,
      rowId: rowId,
    );
    return <Object?>[
      'protected_sha256',
      sha256.convert(utf8.encode(plaintext)).toString(),
    ];
  }
  final normalized = table == 'model_registry'
      ? _normalizedModelValue(column, value)
      : value;
  return switch (normalized) {
    null => const <Object?>['null'],
    int value => <Object?>['integer', value.toString()],
    double value => <Object?>['real', value.toString()],
    String value => <Object?>['text', value],
    List<int> value => <Object?>['blob', base64Encode(value)],
    _ => throw StateError('Unsupported SQLite value in Phase 3 snapshot.'),
  };
}

Object? _normalizedModelValue(String column, Object? value) {
  if (column == 'integrity_status') {
    return switch (value) {
      'verified' => 'valid',
      'unknown' || 'valid' || 'corrupted' => value,
      _ => 'unknown',
    };
  }
  if (column != 'artifact_paths_json' || value == null) {
    return value;
  }
  final decoded = jsonDecode(value as String);
  if (decoded is List<Object?> && decoded.every((entry) => entry is String)) {
    return jsonEncode(<Object?>[
      for (var index = 0; index < decoded.length; index += 1)
        <String, Object?>{
          'role': index == 0 ? 'model' : 'artifact_$index',
          'local_path': decoded[index],
        },
    ]);
  }
  return jsonEncode(decoded);
}

String _rowId(String table, Map<String, Object?> row) {
  if (table == 'app_settings') {
    return row['key']! as String;
  }
  if (table == 'security_metadata') {
    return row['key_id']! as String;
  }
  if (table == 'item_tags') {
    return '${row['item_type']}:${row['item_id']}:${row['tag_id']}';
  }
  return row['id']! as String;
}

const _protectedFields = <String, Map<String, EncryptedDatabaseField>>{
  'secret_items': <String, EncryptedDatabaseField>{
    'username_ciphertext': EncryptedDatabaseField.secretUsername,
    'password_ciphertext': EncryptedDatabaseField.secretPassword,
    'website_url_ciphertext': EncryptedDatabaseField.secretWebsiteUrl,
    'note_ciphertext': EncryptedDatabaseField.secretNote,
  },
  'note_items': <String, EncryptedDatabaseField>{
    'content_ciphertext': EncryptedDatabaseField.noteContent,
    'summary_ciphertext': EncryptedDatabaseField.noteSummary,
  },
  'provider_configs': <String, EncryptedDatabaseField>{
    'encrypted_config': EncryptedDatabaseField.providerConfig,
  },
  'sync_accounts': <String, EncryptedDatabaseField>{
    'encrypted_config': EncryptedDatabaseField.syncAccountConfig,
  },
  'app_settings': <String, EncryptedDatabaseField>{
    'value_ciphertext': EncryptedDatabaseField.appSettingValue,
  },
};

const _canonicalTableOrder = <String>[
  'vaults',
  'categories',
  'tags',
  'secret_items',
  'note_items',
  'item_tags',
  'embedding_chunks',
  'model_registry',
  'model_catalog_entries',
  'download_tasks',
  'provider_configs',
  'sync_accounts',
  'app_settings',
  'chat_sessions',
  'chat_messages',
  'security_metadata',
];

const _tableOrderBy = <String, String>{
  'vaults': 'id ASC',
  'categories': 'id ASC',
  'tags': 'id ASC',
  'secret_items': 'id ASC',
  'note_items': 'id ASC',
  'item_tags': 'item_type ASC, item_id ASC, tag_id ASC',
  'embedding_chunks': 'id ASC',
  'model_registry': 'id ASC',
  'model_catalog_entries': 'id ASC',
  'download_tasks': 'id ASC',
  'provider_configs': 'id ASC',
  'sync_accounts': 'id ASC',
  'app_settings': 'key ASC',
  'chat_sessions': 'id ASC',
  'chat_messages': 'id ASC',
  'security_metadata': 'key_id ASC',
};
