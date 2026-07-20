import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_policy.dart';

void main() {
  test('context policy uses typed dedupe and caps the result at five', () {
    final result = normalizeChatContextItems(<ChatContextItem>[
      _item('same', ChatContextItemType.secret),
      _item('same', ChatContextItemType.note),
      _item('same', ChatContextItemType.secret),
      _item('2', ChatContextItemType.secret),
      _item('3', ChatContextItemType.secret),
      _item('4', ChatContextItemType.secret),
      _item('5', ChatContextItemType.secret),
    ]);

    expect(result, hasLength(5));
    expect(
      result.map((item) => (item.type, item.id)),
      const <(ChatContextItemType, String)>[
        (ChatContextItemType.secret, 'same'),
        (ChatContextItemType.note, 'same'),
        (ChatContextItemType.secret, '2'),
        (ChatContextItemType.secret, '3'),
        (ChatContextItemType.secret, '4'),
      ],
    );
  });
}

ChatContextItem _item(String id, ChatContextItemType type) {
  return ChatContextItem(
    id: id,
    type: type,
    title: id,
    preview: id,
    summary: id,
  );
}
