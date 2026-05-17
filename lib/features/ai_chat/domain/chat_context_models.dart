import 'package:note_secret_search/features/search/domain/search_result_item.dart';

enum ChatMode { privateQa, freeChat }

enum ChatContextSource { none, autoRetrieved, manuallySelected, mixed }

enum ChatContextItemType { secret, note }

class ChatContextItem {
  const ChatContextItem({
    required this.id,
    required this.type,
    required this.title,
    required this.preview,
    required this.summary,
    this.semanticHitField,
  });

  final String id;
  final ChatContextItemType type;
  final String title;
  final String preview;
  final String summary;
  final SemanticHitField? semanticHitField;
}

class AiChatRequest {
  const AiChatRequest({
    required this.mode,
    required this.userInput,
    this.allowPrivateContext = false,
    this.manualItems = const <ChatContextItem>[],
  });

  final ChatMode mode;
  final String userInput;
  final bool allowPrivateContext;
  final List<ChatContextItem> manualItems;
}

class AiChatResponse {
  const AiChatResponse({
    required this.text,
    required this.contextSummary,
    required this.usedPrivateContext,
    required this.sourceType,
    required this.contextItems,
  });

  final String text;
  final List<String> contextSummary;
  final bool usedPrivateContext;
  final ChatContextSource sourceType;
  final List<ChatContextItem> contextItems;
}
