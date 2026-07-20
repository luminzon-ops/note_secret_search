import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'v6 production queries use target indexes without temporary sorting',
    () async {
      final database = await _openFreshV6();
      addTearDown(database.close);

      for (final queryCase in _queryPlanCases) {
        final details = await _queryPlanDetails(
          database,
          queryCase.sql,
          queryCase.arguments,
        );
        expect(
          details,
          contains(contains(queryCase.indexName)),
          reason: queryCase.indexName,
        );
        expect(
          details,
          isNot(contains(contains('USE TEMP B-TREE'))),
          reason: queryCase.indexName,
        );
      }
    },
  );
}

Future<Database> _openFreshV6() async {
  final directory = await Directory.systemTemp.createTemp(
    'note_secret_search_query_plan_v6_',
  );
  addTearDown(() => directory.delete(recursive: true));
  final manager = DatabaseSchemaManager();
  return databaseFactoryFfi.openDatabase(
    '${directory.path}${Platform.pathSeparator}database.db',
    options: OpenDatabaseOptions(
      version: manager.version,
      onConfigure: manager.configure,
      onCreate: manager.create,
      onUpgrade: manager.upgrade,
      onDowngrade: manager.downgrade,
      singleInstance: false,
    ),
  );
}

Future<List<String>> _queryPlanDetails(
  Database database,
  String sql,
  List<Object?> arguments,
) async {
  final rows = await database.rawQuery('EXPLAIN QUERY PLAN $sql', arguments);
  return rows.map((row) => row['detail']! as String).toList(growable: false);
}

class _QueryPlanCase {
  const _QueryPlanCase({
    required this.sql,
    required this.arguments,
    required this.indexName,
  });

  final String sql;
  final List<Object?> arguments;
  final String indexName;
}

const _queryPlanCases = <_QueryPlanCase>[
  _QueryPlanCase(
    sql: '''
      SELECT * FROM secret_items
      WHERE vault_id = ? AND deleted_at IS NULL
      ORDER BY favorite DESC, updated_at DESC, id ASC
      ''',
    arguments: <Object?>['default'],
    indexName: 'idx_secret_items_active_vault_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM note_items
      WHERE vault_id = ? AND deleted_at IS NULL
      ORDER BY favorite DESC, updated_at DESC, id ASC
      ''',
    arguments: <Object?>['default'],
    indexName: 'idx_note_items_active_vault_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT item_id, item_type FROM item_tags
      WHERE tag_id = ?
      ORDER BY item_type ASC, item_id ASC
      ''',
    arguments: <Object?>['tag'],
    indexName: 'idx_item_tags_tag_item',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM embedding_index_sets
      WHERE vault_id = ? AND model_id = ? AND source_type = ?
      ORDER BY source_id ASC
      ''',
    arguments: <Object?>['default', 'model', 'secret'],
    indexName: 'idx_embedding_index_sets_scope',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM embedding_chunks
      WHERE index_set_id = ?
      ORDER BY source_field ASC, field_chunk_index ASC
      ''',
    arguments: <Object?>['set'],
    indexName: 'idx_embedding_chunks_set_field',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM download_tasks
      WHERE model_id = ?
      ORDER BY updated_at DESC, id ASC
      LIMIT 1
      ''',
    arguments: <Object?>['model'],
    indexName: 'idx_download_tasks_model_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM download_tasks
      WHERE model_id = ? AND source_id = ?
      ORDER BY updated_at DESC, id ASC
      LIMIT 1
      ''',
    arguments: <Object?>['model', 'source'],
    indexName: 'idx_download_tasks_model_source_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM download_tasks
      ORDER BY updated_at DESC, id ASC
      ''',
    arguments: <Object?>[],
    indexName: 'idx_download_tasks_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM model_registry
      ORDER BY installed_at DESC, id ASC
      ''',
    arguments: <Object?>[],
    indexName: 'idx_model_registry_installed',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM provider_configs
      ORDER BY updated_at DESC, id ASC
      ''',
    arguments: <Object?>[],
    indexName: 'idx_provider_configs_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM provider_configs
      WHERE enabled = ?
      ORDER BY updated_at DESC, id ASC
      LIMIT 1
      ''',
    arguments: <Object?>[1],
    indexName: 'idx_provider_configs_enabled_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM chat_sessions
      ORDER BY updated_at DESC, id ASC
      ''',
    arguments: <Object?>[],
    indexName: 'idx_chat_sessions_updated',
  ),
  _QueryPlanCase(
    sql: '''
      SELECT * FROM chat_messages
      WHERE session_id = ?
      ORDER BY created_at ASC, id ASC
      ''',
    arguments: <Object?>['session'],
    indexName: 'idx_chat_messages_session_created',
  ),
];
