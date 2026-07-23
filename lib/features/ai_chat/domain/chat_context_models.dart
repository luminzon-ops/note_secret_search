import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';

enum ChatMode { privateQa, freeChat }

enum ChatBackendPreference { local, external }

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
    this.requestId,
    this.backendPreference = ChatBackendPreference.local,
    this.allowPrivateContext = false,
    this.manualItems = const <ChatContextItem>[],
  });

  final ChatMode mode;
  final String userInput;
  final String? requestId;
  final ChatBackendPreference backendPreference;
  final bool allowPrivateContext;
  final List<ChatContextItem> manualItems;
}

class AiChatResponse {
  const AiChatResponse({
    required this.text,
    required this.usage,
    required this.contextSummary,
    required this.usedPrivateContext,
    required this.sourceType,
    required this.contextItems,
  });

  final String text;
  final ChatBackendUsage usage;
  final List<String> contextSummary;
  final bool usedPrivateContext;
  final ChatContextSource sourceType;
  final List<ChatContextItem> contextItems;
}
