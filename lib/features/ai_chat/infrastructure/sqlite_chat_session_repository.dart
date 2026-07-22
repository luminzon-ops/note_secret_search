import 'dart:convert';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteChatSessionRepository implements ChatSessionRepository {
  SqliteChatSessionRepository({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  @override
  Future<ChatSession?> getSession(String sessionId) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.chatSessions,
        where: 'id = ?',
        whereArgs: <Object>[sessionId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return _mapSession(rows.first);
    });
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.chatMessages,
        where: 'session_id = ?',
        whereArgs: <Object>[sessionId],
        orderBy: 'created_at ASC, id ASC',
      );
      return rows.map(_mapMessage).toList(growable: false);
    });
  }

  @override
  Future<List<ChatSession>> listSessions() {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.chatSessions,
        orderBy: 'updated_at DESC, id ASC',
      );
      return rows.map(_mapSession).toList(growable: false);
    });
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) {
    return _database.run((db) async {
      await db.insert(DatabaseSchema.chatMessages, <String, Object?>{
        'id': message.id,
        'session_id': message.sessionId,
        'role': message.role.name,
        'content': message.content,
        'status': message.status.name,
        'used_private_context': message.usedPrivateContext ? 1 : 0,
        'auto_retrieved_context_summary': message.autoRetrievedContextSummary,
        'manual_context_item_ids_json': jsonEncode(
          message.manualContextItemIds,
        ),
        'related_source_ids_json': jsonEncode(message.relatedSourceIds),
        'actual_backend': message.backendUsage?.actualBackend,
        'actual_model': message.backendUsage?.actualModel,
        'provider_fingerprint': message.backendUsage?.providerFingerprint,
        'created_at': message.createdAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> saveSession(ChatSession session) {
    return _database.run((db) async {
      await db.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.chatSessions} (
          id,
          mode,
          title,
          allow_private_context,
          last_model_id,
          archived,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          mode = excluded.mode,
          title = excluded.title,
          allow_private_context = excluded.allow_private_context,
          last_model_id = excluded.last_model_id,
          archived = excluded.archived,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          session.id,
          session.mode.name,
          session.title,
          session.allowPrivateContext ? 1 : 0,
          session.lastModelId,
          session.archived ? 1 : 0,
          session.createdAt.millisecondsSinceEpoch,
          session.updatedAt.millisecondsSinceEpoch,
        ],
      );
    });
  }

  ChatSession _mapSession(Map<String, Object?> row) {
    return ChatSession(
      id: row['id']! as String,
      mode: ChatMode.values.byName(row['mode']! as String),
      title: row['title']! as String,
      allowPrivateContext: (row['allow_private_context']! as int) == 1,
      lastModelId: row['last_model_id'] as String?,
      archived: (row['archived']! as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }

  ChatStoredMessage _mapMessage(Map<String, Object?> row) {
    return ChatStoredMessage(
      id: row['id']! as String,
      sessionId: row['session_id']! as String,
      role: ChatStoredMessageRole.values.byName(row['role']! as String),
      content: row['content']! as String,
      status: ChatStoredMessageStatus.values.byName(row['status']! as String),
      usedPrivateContext: (row['used_private_context']! as int) == 1,
      autoRetrievedContextSummary:
          row['auto_retrieved_context_summary'] as String?,
      manualContextItemIds: _decodeStringList(
        row['manual_context_item_ids_json'] as String?,
      ),
      relatedSourceIds: _decodeStringList(
        row['related_source_ids_json'] as String?,
      ),
      backendUsage: _mapBackendUsage(row),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  ChatBackendUsage? _mapBackendUsage(Map<String, Object?> row) {
    final actualBackend = row['actual_backend'] as String?;
    final actualModel = row['actual_model'] as String?;
    final providerFingerprint = row['provider_fingerprint'] as String?;
    if (actualBackend == null &&
        actualModel == null &&
        providerFingerprint == null) {
      return null;
    }
    if (actualBackend == null || actualModel == null) {
      throw const FormatException('chat_backend_usage_invalid');
    }
    return ChatBackendUsage(
      actualBackend: actualBackend,
      actualModel: actualModel,
      providerFingerprint: providerFingerprint,
    );
  }

  List<String> _decodeStringList(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return const <String>[];
    }
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      return const <String>[];
    }
    return decoded.map((item) => item.toString()).toList(growable: false);
  }
}
