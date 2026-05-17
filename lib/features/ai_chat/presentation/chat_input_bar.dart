import 'package:flutter/material.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    required this.onSend,
    this.enabled = true,
    this.sending = false,
    this.hintText = '输入你的问题或消息',
    super.key,
  });

  final Future<void> Function(String value) onSend;
  final bool enabled;
  final bool sending;
  final String hintText;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty || !widget.enabled) {
      return;
    }
    _controller.clear();
    await widget.onSend(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: widget.enabled ? _submit : null,
            child: Text(widget.sending ? '发送中' : '发送'),
          ),
        ],
      ),
    );
  }
}
