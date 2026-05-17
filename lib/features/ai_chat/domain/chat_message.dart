import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

enum ChatMessageRole { user, assistant, system }

enum ChatMessageStatus { loading, completed, error }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.status = ChatMessageStatus.completed,
    this.usedPrivateContext = false,
    this.contextSummary = const <String>[],
    this.sourceType = ChatContextSource.none,
  });

  final String id;
  final ChatMessageRole role;
  final String text;
  final DateTime createdAt;
  final ChatMessageStatus status;
  final bool usedPrivateContext;
  final List<String> contextSummary;
  final ChatContextSource sourceType;

  ChatMessage copyWith({
    String? id,
    ChatMessageRole? role,
    String? text,
    DateTime? createdAt,
    ChatMessageStatus? status,
    bool? usedPrivateContext,
    List<String>? contextSummary,
    ChatContextSource? sourceType,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      usedPrivateContext: usedPrivateContext ?? this.usedPrivateContext,
      contextSummary: contextSummary ?? this.contextSummary,
      sourceType: sourceType ?? this.sourceType,
    );
  }
}
