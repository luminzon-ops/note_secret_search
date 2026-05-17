import 'dart:convert';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteChatSessionRepository implements ChatSessionRepository {
  SqliteChatSessionRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    final db = await _database.database;
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
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.chatMessages,
      where: 'session_id = ?',
      whereArgs: <Object>[sessionId],
      orderBy: 'created_at ASC',
    );
    return rows.map(_mapMessage).toList(growable: false);
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final db = await _database.database;
    final rows = await db.query(DatabaseSchema.chatSessions, orderBy: 'updated_at DESC');
    return rows.map(_mapSession).toList(growable: false);
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    final db = await _database.database;
    await db.insert(
      DatabaseSchema.chatMessages,
      <String, Object?>{
        'id': message.id,
        'session_id': message.sessionId,
        'role': message.role.name,
        'content': message.content,
        'status': message.status.name,
        'used_private_context': message.usedPrivateContext ? 1 : 0,
        'auto_retrieved_context_summary': message.autoRetrievedContextSummary,
        'manual_context_item_ids_json': jsonEncode(message.manualContextItemIds),
        'related_source_ids_json': jsonEncode(message.relatedSourceIds),
        'created_at': message.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    final db = await _database.database;
    await db.insert(
      DatabaseSchema.chatSessions,
      <String, Object?>{
        'id': session.id,
        'mode': session.mode.name,
        'title': session.title,
        'allow_private_context': session.allowPrivateContext ? 1 : 0,
        'last_model_id': session.lastModelId,
        'archived': session.archived ? 1 : 0,
        'created_at': session.createdAt.millisecondsSinceEpoch,
        'updated_at': session.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      autoRetrievedContextSummary: row['auto_retrieved_context_summary'] as String?,
      manualContextItemIds: _decodeStringList(row['manual_context_item_ids_json'] as String?),
      relatedSourceIds: _decodeStringList(row['related_source_ids_json'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
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
