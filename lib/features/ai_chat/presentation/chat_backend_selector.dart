import 'package:flutter/material.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

class ChatBackendSelector extends StatelessWidget {
  const ChatBackendSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ChatBackendPreference value;
  final ValueChanged<ChatBackendPreference>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChatBackendPreference>(
      segments: const [
        ButtonSegment(
          value: ChatBackendPreference.local,
          icon: Icon(Icons.smartphone_outlined),
          label: Text('本地'),
        ),
        ButtonSegment(
          value: ChatBackendPreference.external,
          icon: Icon(Icons.cloud_outlined),
          label: Text('外部'),
        ),
      ],
      selected: {value},
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(selection.single),
    );
  }
}
