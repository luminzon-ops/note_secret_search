import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'historical_database_schema.dart';

export 'historical_database_schema.dart'
    show LegacyFixtureVersion, legacyMigrationSourceVersions;

class LegacyDatabaseFixture {
  LegacyDatabaseFixture({
    required this.directory,
    required this.sourcePath,
    required this.pendingPath,
    required this.version,
    required this.expectedPlaintext,
  });

  final Directory directory;
  final String sourcePath;
  final String pendingPath;
  final LegacyFixtureVersion version;
  final Map<String, String?> expectedPlaintext;

  Future<void> dispose() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<LegacyDatabaseFixture> createLegacyDatabaseFixture(
  LegacyFixtureVersion version,
) async {
  sqfliteFfiInit();
  final directory = await Directory.systemTemp.createTemp(
    'note_secret_search_legacy_fixture_',
  );
  final sourcePath = p.join(directory.path, 'note_secret_search.db');
  final pendingPath = p.join(directory.path, 'pending.db');
  if (version == LegacyFixtureVersion.phase2MigratedV4) {
    await _createPhase2MigratedDatabase(directory, sourcePath);
  } else {
    await _createHistoricalDatabaseFile(sourcePath, version);
  }

  return LegacyDatabaseFixture(
    directory: directory,
    sourcePath: sourcePath,
    pendingPath: pendingPath,
    version: version,
    expectedPlaintext: _expectedPlaintext,
  );
}

Future<void> _createHistoricalDatabaseFile(
  String path,
  LegacyFixtureVersion version,
) async {
  final database = await databaseFactoryFfi.openDatabase(path);
  try {
    await createHistoricalDatabaseSchema(database, version);
    await _insertLegacyRows(database, version);
    await database.execute('PRAGMA user_version = ${version.schemaVersion}');
  } finally {
    await database.close();
  }
}

Future<void> _createPhase2MigratedDatabase(
  Directory directory,
  String targetPath,
) async {
  final legacyPath = p.join(directory.path, 'phase2_source_v3.db');
  await _createHistoricalDatabaseFile(legacyPath, LegacyFixtureVersion.freshV3);
  final keys = DatabaseSessionKeys(
    databaseKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
    fieldKey: Uint8List.fromList(
      List<int>.generate(32, (index) => 0x80 + index),
    ),
  );
  final keyStore = DatabaseSessionKeyStore()..replace(keys);
  try {
    final migrator = LegacyDatabaseMigrator(
      databaseFactory: const _FixtureMigrationDatabaseFactory(),
      cryptoService: AesGcmFieldCrypto(sessionKeyStore: keyStore),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_013),
    );
    await migrator.migrate(
      sourcePath: legacyPath,
      pendingPath: targetPath,
      legacyPassword: 'legacy-password',
      databasePassword: 'database-password',
      keyId: '123e4567-e89b-42d3-a456-426614174000',
    );
  } finally {
    keyStore.clear();
  }
}

const _expectedPlaintext = <String, String?>{
  'secret-1.username_ciphertext': 'alice',
  'secret-1.password_ciphertext': 'correct horse battery staple',
  'secret-1.website_url_ciphertext': 'https://example.test/login',
  'secret-1.note_ciphertext': 'primary secret note',
  'secret-deleted.username_ciphertext': null,
  'secret-deleted.password_ciphertext': 'deleted password',
  'secret-deleted.website_url_ciphertext': '',
  'secret-deleted.note_ciphertext': null,
  'note-1.content_ciphertext': '完整的旧版笔记正文',
  'note-1.summary_ciphertext': '旧版摘要',
  'note-deleted.content_ciphertext': 'soft deleted note',
  'note-deleted.summary_ciphertext': null,
  'provider-1.encrypted_config':
      '{"endpoint":"https://api.example.test","apiKey":"provider-secret"}',
  'sync-1.encrypted_config':
      '{"server":"https://sync.example.test","token":"sync-secret"}',
  'search.scope.value_ciphertext': 'secret,note',
};

Future<void> _insertLegacyRows(
  Database database,
  LegacyFixtureVersion version,
) async {
  const createdAt = 1_700_000_000_000;
  await database.insert('vaults', <String, Object?>{
    'id': 'vault-1',
    'name': 'Primary',
    'description': 'legacy vault',
    'is_default': 1,
    'encryption_version': 1,
    'created_at': createdAt,
    'updated_at': createdAt + 1,
  });
  await database.insert('categories', <String, Object?>{
    'id': 'category-1',
    'vault_id': 'vault-1',
    'name': 'Logins',
    'sort_order': 2,
  });
  await database.insert('tags', <String, Object?>{
    'id': 'tag-1',
    'vault_id': 'vault-1',
    'name': 'work',
    'created_at': createdAt,
  });
  await database.insert('secret_items', <String, Object?>{
    'id': 'secret-1',
    'vault_id': 'vault-1',
    'title': 'Primary account',
    'username_ciphertext': _legacyBytes('alice'),
    'password_ciphertext': _legacyBytes('correct horse battery staple'),
    'website_url_ciphertext': _legacyBytes('https://example.test/login'),
    'note_ciphertext': _legacyBytes('primary secret note'),
    'category_id': 'category-1',
    'favorite': 1,
    'created_at': createdAt,
    'updated_at': createdAt + 2,
    'last_accessed_at': createdAt + 3,
    'deleted_at': null,
  });
  await database.insert('secret_items', <String, Object?>{
    'id': 'secret-deleted',
    'vault_id': 'vault-1',
    'title': 'Deleted account',
    'username_ciphertext': null,
    'password_ciphertext': _legacyBytes('deleted password'),
    'website_url_ciphertext': _legacyBytes(''),
    'note_ciphertext': null,
    'category_id': null,
    'favorite': 0,
    'created_at': createdAt,
    'updated_at': createdAt + 4,
    'last_accessed_at': null,
    'deleted_at': createdAt + 5,
  });
  await database.insert('note_items', <String, Object?>{
    'id': 'note-1',
    'vault_id': 'vault-1',
    'title': 'Legacy note',
    'content_ciphertext': _legacyBytes('完整的旧版笔记正文'),
    'summary_ciphertext': _legacyBytes('旧版摘要'),
    'category_id': 'category-1',
    'favorite': 1,
    'created_at': createdAt,
    'updated_at': createdAt + 6,
    'deleted_at': null,
  });
  await database.insert('note_items', <String, Object?>{
    'id': 'note-deleted',
    'vault_id': 'vault-1',
    'title': 'Deleted note',
    'content_ciphertext': _legacyBytes('soft deleted note'),
    'summary_ciphertext': null,
    'category_id': null,
    'favorite': 0,
    'created_at': createdAt,
    'updated_at': createdAt + 7,
    'deleted_at': createdAt + 8,
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'secret-1',
    'item_type': 'secret',
    'tag_id': 'tag-1',
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'note-1',
    'item_type': 'note',
    'tag_id': 'tag-1',
  });
  await database.insert('embedding_chunks', <String, Object?>{
    'id': 'embedding-1',
    'source_id': 'secret-1',
    'source_type': 'secret',
    'chunk_index': 0,
    'plaintext_hash': 'legacy-hash',
    'model_id': 'embedding-model',
    'vector_blob': Uint8List.fromList(const <int>[1, 2, 3, 4]),
    'token_count': 4,
    'created_at': createdAt,
    'updated_at': createdAt,
  });
  await _insertModelRegistry(database, version, createdAt);
  await database.insert('model_catalog_entries', <String, Object?>{
    'id': 'catalog-1',
    'type': 'embedding',
    'tier': 'small',
    'display_name': 'Legacy catalog row',
    'description': 'discard me',
    'quantization': null,
    'size_bytes': 10,
    'min_ram_mb': 128,
    'recommended_tier': 'small',
    'speed_hint': null,
    'quality_hint': null,
    'license': null,
    'release_date': null,
    'source_list_json': '[]',
    'checksum': 'sha256:legacy',
    'signature': null,
    'updated_at': createdAt,
  });
  await database.insert('download_tasks', <String, Object?>{
    'id': 'download-1',
    'model_id': 'model-1',
    'source_id': 'source-1',
    'status': version.schemaVersion == 4 ? 'downloading' : 'running',
    'total_bytes': 10,
    'downloaded_bytes': 5,
    'average_speed': 2.5,
    'error_message': null,
    'resumable': 1,
    'created_at': createdAt,
    'updated_at': createdAt,
  });
  await database.insert('provider_configs', <String, Object?>{
    'id': 'provider-1',
    'provider_type': 'openAiCompatible',
    'name': 'Legacy provider',
    'encrypted_config': _legacyBytes(
      '{"endpoint":"https://api.example.test","apiKey":"provider-secret"}',
    ),
    'enabled': 1,
    'created_at': createdAt,
    'updated_at': createdAt + 9,
  });
  await database.insert('sync_accounts', <String, Object?>{
    'id': 'sync-1',
    'provider_type': 'webdav',
    'encrypted_config': _legacyBytes(
      '{"server":"https://sync.example.test","token":"sync-secret"}',
    ),
    'last_sync_at': createdAt + 10,
    'status': 'ready',
    'created_at': createdAt,
    'updated_at': createdAt + 11,
  });
  await database.insert('app_settings', <String, Object?>{
    'key': 'search.scope',
    'value_ciphertext': _legacyBytes('secret,note'),
  });
  if (version != LegacyFixtureVersion.v1) {
    await database.insert('chat_sessions', <String, Object?>{
      'id': 'chat-1',
      'mode': 'freeChat',
      'title': 'Legacy chat',
      'allow_private_context': 0,
      'last_model_id': 'model-1',
      'archived': 0,
      'created_at': createdAt,
      'updated_at': createdAt + 12,
    });
    await database.insert('chat_messages', <String, Object?>{
      'id': 'message-1',
      'session_id': 'chat-1',
      'role': 'user',
      'content': 'hello',
      'status': 'completed',
      'used_private_context': 0,
      'auto_retrieved_context_summary': null,
      'manual_context_item_ids_json': '[]',
      'related_source_ids_json': '[]',
      'created_at': createdAt,
    });
  }
}

Future<void> _insertModelRegistry(
  Database database,
  LegacyFixtureVersion version,
  int createdAt,
) async {
  final row = <String, Object?>{
    'id': 'model-1',
    'type': 'embedding',
    'provider': 'local',
    'name': 'Legacy model',
    'version': '1',
    'size_bytes': 1024,
    'quantization': 'f16',
    'min_ram_mb': 256,
    'recommended_tier': 'small',
    'local_path': '/models/legacy.onnx',
    'checksum': 'sha256:model',
    'enabled': 1,
    'installed_at': createdAt,
  };
  if (version.schemaVersion >= 3) {
    row['artifact_paths_json'] = version == LegacyFixtureVersion.freshV4
        ? '[{"role":"model","local_path":"/models/legacy.onnx"}]'
        : '["/models/legacy.onnx"]';
  }
  if (version == LegacyFixtureVersion.freshV3 ||
      version == LegacyFixtureVersion.freshV4) {
    row['integrity_status'] = 'verified';
  }
  await database.insert('model_registry', row);
}

Uint8List _legacyBytes(String value) {
  return Uint8List.fromList(utf8.encode(value));
}

class _FixtureMigrationDatabaseFactory implements MigrationDatabaseFactory {
  const _FixtureMigrationDatabaseFactory();

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
