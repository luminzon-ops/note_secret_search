import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

List<ChatContextItem> normalizeChatContextItems(
  Iterable<ChatContextItem> items, {
  int limit = 5,
}) {
  if (limit < 1) {
    throw ArgumentError.value(limit, 'limit', 'Must be positive.');
  }
  final result = <ChatContextItem>[];
  final seen = <String>{};
  for (final item in items) {
    final key = '${item.type.name}:${item.id}';
    if (seen.add(key)) {
      result.add(item);
      if (result.length == limit) {
        break;
      }
    }
  }
  return List<ChatContextItem>.unmodifiable(result);
}
