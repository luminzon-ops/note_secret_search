import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

enum ChatStoredMessageRole { user, assistant, system }

enum ChatStoredMessageStatus { loading, completed, failed }

class ChatSession {
  const ChatSession({
    required this.id,
    required this.mode,
    required this.title,
    required this.allowPrivateContext,
    this.lastModelId,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final ChatMode mode;
  final String title;
  final bool allowPrivateContext;
  final String? lastModelId;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession copyWith({
    String? id,
    ChatMode? mode,
    String? title,
    bool? allowPrivateContext,
    String? lastModelId,
    bool clearLastModelId = false,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      title: title ?? this.title,
      allowPrivateContext: allowPrivateContext ?? this.allowPrivateContext,
      lastModelId: clearLastModelId ? null : (lastModelId ?? this.lastModelId),
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ChatStoredMessage {
  const ChatStoredMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.status,
    this.usedPrivateContext = false,
    this.autoRetrievedContextSummary,
    this.manualContextItemIds = const <String>[],
    this.relatedSourceIds = const <String>[],
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final ChatStoredMessageRole role;
  final String content;
  final ChatStoredMessageStatus status;
  final bool usedPrivateContext;
  final String? autoRetrievedContextSummary;
  final List<String> manualContextItemIds;
  final List<String> relatedSourceIds;
  final DateTime createdAt;

  ChatStoredMessage copyWith({
    String? id,
    String? sessionId,
    ChatStoredMessageRole? role,
    String? content,
    ChatStoredMessageStatus? status,
    bool? usedPrivateContext,
    String? autoRetrievedContextSummary,
    bool clearAutoRetrievedContextSummary = false,
    List<String>? manualContextItemIds,
    List<String>? relatedSourceIds,
    DateTime? createdAt,
  }) {
    return ChatStoredMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      status: status ?? this.status,
      usedPrivateContext: usedPrivateContext ?? this.usedPrivateContext,
      autoRetrievedContextSummary: clearAutoRetrievedContextSummary
          ? null
          : (autoRetrievedContextSummary ?? this.autoRetrievedContextSummary),
      manualContextItemIds: manualContextItemIds ?? this.manualContextItemIds,
      relatedSourceIds: relatedSourceIds ?? this.relatedSourceIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
