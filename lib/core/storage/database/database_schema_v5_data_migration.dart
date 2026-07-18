import 'dart:convert';

import 'package:sqflite_sqlcipher/sqlite_api.dart';

class DatabaseSchemaV5DataMigrationException implements Exception {
  const DatabaseSchemaV5DataMigrationException();
}

abstract final class DatabaseSchemaV5DataMigration {
  static Future<void> normalize(
    DatabaseExecutor database, {
    required int Function() nowMilliseconds,
  }) async {
    await _validateBusinessOwners(database);
    await _normalizeDefaultVault(database, nowMilliseconds: nowMilliseconds);
    await _normalizeModelRegistry(database);
    await _normalizeEnabledProviders(database);
    await _mergeDuplicateCategories(database);
    await _clearInvalidCategories(database);
    await _mergeDuplicateTags(database);
    await _clearInvalidItemTags(database);
    await database.delete(
      'tags',
      where: '''
      NOT EXISTS (
        SELECT 1 FROM item_tags
        WHERE item_tags.tag_id = tags.id
      )
      ''',
    );
    await database.delete(
      'categories',
      where: '''
      NOT EXISTS (
        SELECT 1 FROM vaults
        WHERE vaults.id = categories.vault_id
      )
      ''',
    );
    await database.delete('embedding_chunks');
  }

  static Future<void> _validateBusinessOwners(DatabaseExecutor database) async {
    if (await _hasRows(database, '''
          SELECT 1
          FROM secret_items item
          WHERE NOT EXISTS (
            SELECT 1 FROM vaults WHERE vaults.id = item.vault_id
          )
          LIMIT 1
          ''') ||
        await _hasRows(database, '''
          SELECT 1
          FROM note_items item
          WHERE NOT EXISTS (
            SELECT 1 FROM vaults WHERE vaults.id = item.vault_id
          )
          LIMIT 1
          ''') ||
        await _hasRows(database, '''
          SELECT 1
          FROM chat_messages message
          WHERE NOT EXISTS (
            SELECT 1 FROM chat_sessions
            WHERE chat_sessions.id = message.session_id
          )
          LIMIT 1
          ''')) {
      throw const DatabaseSchemaV5DataMigrationException();
    }
  }

  static Future<void> _normalizeDefaultVault(
    DatabaseExecutor database, {
    required int Function() nowMilliseconds,
  }) async {
    final vaults = await database.query(
      'vaults',
      columns: const <String>['id', 'is_default'],
      orderBy: 'is_default DESC, created_at ASC, id ASC',
    );
    if (vaults.isEmpty) {
      final now = nowMilliseconds();
      await database.insert('vaults', <String, Object?>{
        'id': 'default',
        'name': '默认保险库',
        'description': '首版默认保险库',
        'is_default': 1,
        'encryption_version': 1,
        'created_at': now,
        'updated_at': now,
      });
      return;
    }

    final defaults = vaults
        .where((row) => row['is_default'] == 1)
        .toList(growable: false);
    final winner = defaults.isEmpty ? vaults.first : defaults.first;
    await database.update('vaults', const <String, Object?>{'is_default': 0});
    await database.update(
      'vaults',
      const <String, Object?>{'is_default': 1},
      where: 'id = ?',
      whereArgs: <Object>[winner['id']!],
    );
  }

  static Future<void> _normalizeModelRegistry(DatabaseExecutor database) async {
    final models = await database.query(
      'model_registry',
      columns: const <String>['id', 'local_path', 'artifact_paths_json'],
    );
    for (final model in models) {
      final raw = model['artifact_paths_json'] as String?;
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      final normalized = _normalizeArtifactJson(
        raw,
        localPath: model['local_path'] as String?,
      );
      await database.update(
        'model_registry',
        <String, Object?>{'artifact_paths_json': normalized},
        where: 'id = ?',
        whereArgs: <Object>[model['id']!],
      );
    }
    await database.rawUpdate('''
      UPDATE model_registry
      SET integrity_status = CASE
        WHEN integrity_status = 'verified' THEN 'valid'
        WHEN integrity_status IN ('unknown', 'valid', 'corrupted')
          THEN integrity_status
        ELSE 'unknown'
      END
      ''');
  }

  static String _normalizeArtifactJson(
    String raw, {
    required String? localPath,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const DatabaseSchemaV5DataMigrationException();
    }
    if (decoded is! List<Object?>) {
      throw const DatabaseSchemaV5DataMigrationException();
    }
    if (decoded.every((entry) => entry is String)) {
      final paths = decoded.cast<String>();
      if (paths.any((path) => path.trim().isEmpty)) {
        throw const DatabaseSchemaV5DataMigrationException();
      }
      final primaryIndex = _primaryArtifactIndex(paths, localPath);
      var assignedMmproj = false;
      final artifacts = <Map<String, Object?>>[];
      for (var index = 0; index < paths.length; index += 1) {
        final entry = paths[index];
        final lowerPath = entry.toLowerCase();
        final role = index == primaryIndex
            ? 'model'
            : lowerPath.contains('mmproj') && !assignedMmproj
            ? 'mmproj'
            : 'artifact_$index';
        assignedMmproj = assignedMmproj || role == 'mmproj';
        artifacts.add(<String, Object?>{'role': role, 'local_path': entry});
      }
      return jsonEncode(artifacts);
    }
    if (!decoded.every((entry) => entry is Map<String, dynamic>)) {
      throw const DatabaseSchemaV5DataMigrationException();
    }
    for (final entry in decoded.cast<Map<String, dynamic>>()) {
      final role = entry['role'];
      final localPath = entry['local_path'];
      final sourceId = entry['source_id'];
      final checksum = entry['checksum'];
      final sizeBytes = entry['size_bytes'];
      if (role is! String ||
          role.trim().isEmpty ||
          localPath is! String ||
          localPath.trim().isEmpty ||
          (sourceId != null && sourceId is! String) ||
          (checksum != null && checksum is! String) ||
          (sizeBytes != null && sizeBytes is! num)) {
        throw const DatabaseSchemaV5DataMigrationException();
      }
    }
    return jsonEncode(decoded);
  }

  static int _primaryArtifactIndex(List<String> paths, String? localPath) {
    if (localPath != null && localPath.isNotEmpty) {
      final matchingIndex = paths.indexOf(localPath);
      if (matchingIndex >= 0) {
        return matchingIndex;
      }
    }
    final nonProjector = paths.indexWhere(
      (path) => !path.toLowerCase().contains('mmproj'),
    );
    return nonProjector >= 0 ? nonProjector : 0;
  }

  static Future<void> _normalizeEnabledProviders(
    DatabaseExecutor database,
  ) async {
    final duplicateTypes = await database.rawQuery('''
      SELECT provider_type
      FROM provider_configs
      WHERE enabled = 1
      GROUP BY provider_type
      HAVING COUNT(*) > 1
      ''');
    for (final group in duplicateTypes) {
      final providers = await database.query(
        'provider_configs',
        columns: const <String>['id'],
        where: 'provider_type = ? AND enabled = 1',
        whereArgs: <Object>[group['provider_type']!],
        orderBy: 'updated_at DESC, id ASC',
      );
      final winnerId = providers.first['id']!;
      await database.update(
        'provider_configs',
        const <String, Object?>{'enabled': 0},
        where: 'provider_type = ? AND enabled = 1 AND id != ?',
        whereArgs: <Object>[group['provider_type']!, winnerId],
      );
    }
  }

  static Future<void> _mergeDuplicateCategories(
    DatabaseExecutor database,
  ) async {
    final duplicateGroups = await database.rawQuery('''
      SELECT vault_id, name
      FROM categories
      GROUP BY vault_id, name COLLATE NOCASE
      HAVING COUNT(*) > 1
      ''');
    for (final group in duplicateGroups) {
      final categories = await database.query(
        'categories',
        columns: const <String>['id'],
        where: 'vault_id = ? AND name = ? COLLATE NOCASE',
        whereArgs: <Object>[group['vault_id']!, group['name']!],
        orderBy: 'sort_order ASC, id ASC',
      );
      final winnerId = categories.first['id']!;
      for (final loser in categories.skip(1)) {
        final loserId = loser['id']!;
        await database.update(
          'secret_items',
          <String, Object?>{'category_id': winnerId},
          where: 'category_id = ?',
          whereArgs: <Object>[loserId],
        );
        await database.update(
          'note_items',
          <String, Object?>{'category_id': winnerId},
          where: 'category_id = ?',
          whereArgs: <Object>[loserId],
        );
        await database.delete(
          'categories',
          where: 'id = ?',
          whereArgs: <Object>[loserId],
        );
      }
    }
  }

  static Future<void> _clearInvalidCategories(DatabaseExecutor database) async {
    for (final table in const <String>['secret_items', 'note_items']) {
      await database.rawUpdate('''
        UPDATE $table
        SET category_id = NULL
        WHERE category_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1
            FROM categories
            WHERE categories.id = $table.category_id
              AND categories.vault_id = $table.vault_id
          )
        ''');
    }
  }

  static Future<void> _mergeDuplicateTags(DatabaseExecutor database) async {
    final duplicateGroups = await database.rawQuery('''
      SELECT vault_id, name
      FROM tags
      GROUP BY vault_id, name COLLATE NOCASE
      HAVING COUNT(*) > 1
      ''');
    for (final group in duplicateGroups) {
      final tags = await database.query(
        'tags',
        columns: const <String>['id'],
        where: 'vault_id = ? AND name = ? COLLATE NOCASE',
        whereArgs: <Object>[group['vault_id']!, group['name']!],
        orderBy: 'created_at ASC, id ASC',
      );
      final winnerId = tags.first['id']!;
      for (final loser in tags.skip(1)) {
        final loserId = loser['id']!;
        await database.rawInsert(
          '''
          INSERT OR IGNORE INTO item_tags (item_id, item_type, tag_id)
          SELECT item_id, item_type, ?
          FROM item_tags
          WHERE tag_id = ?
          ''',
          <Object>[winnerId, loserId],
        );
        await database.delete(
          'item_tags',
          where: 'tag_id = ?',
          whereArgs: <Object>[loserId],
        );
        await database.delete(
          'tags',
          where: 'id = ?',
          whereArgs: <Object>[loserId],
        );
      }
    }
  }

  static Future<void> _clearInvalidItemTags(DatabaseExecutor database) {
    return database.rawDelete('''
      DELETE FROM item_tags
      WHERE item_type NOT IN ('secret', 'note')
        OR NOT EXISTS (
          SELECT 1 FROM tags WHERE tags.id = item_tags.tag_id
        )
        OR (
          item_type = 'secret'
          AND NOT EXISTS (
            SELECT 1
            FROM secret_items item
            INNER JOIN tags tag ON tag.id = item_tags.tag_id
            WHERE item.id = item_tags.item_id
              AND item.deleted_at IS NULL
              AND item.vault_id = tag.vault_id
          )
        )
        OR (
          item_type = 'note'
          AND NOT EXISTS (
            SELECT 1
            FROM note_items item
            INNER JOIN tags tag ON tag.id = item_tags.tag_id
            WHERE item.id = item_tags.item_id
              AND item.deleted_at IS NULL
              AND item.vault_id = tag.vault_id
          )
        )
      ''');
  }

  static Future<bool> _hasRows(DatabaseExecutor database, String query) async {
    return (await database.rawQuery(query)).isNotEmpty;
  }
}
