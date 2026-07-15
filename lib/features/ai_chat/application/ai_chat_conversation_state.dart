part of 'ai_chat_providers.dart';

class AiChatConversationState {
  const AiChatConversationState({
    required this.mode,
    this.messages = const <ChatMessage>[],
    this.sending = false,
    this.backendPreference = ChatBackendPreference.local,
    this.allowPrivateContext = false,
    this.manualItems = const <ChatContextItem>[],
    this.currentSessionId,
    this.errorMessage,
    this.suppressSessionRestore = false,
  });

  final ChatMode mode;
  final List<ChatMessage> messages;
  final bool sending;
  final ChatBackendPreference backendPreference;
  final bool allowPrivateContext;
  final List<ChatContextItem> manualItems;
  final String? currentSessionId;
  final String? errorMessage;
  final bool suppressSessionRestore;

  AiChatConversationState copyWith({
    ChatMode? mode,
    List<ChatMessage>? messages,
    bool? sending,
    ChatBackendPreference? backendPreference,
    bool? allowPrivateContext,
    List<ChatContextItem>? manualItems,
    String? currentSessionId,
    bool clearCurrentSessionId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? suppressSessionRestore,
  }) {
    return AiChatConversationState(
      mode: mode ?? this.mode,
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      backendPreference: backendPreference ?? this.backendPreference,
      allowPrivateContext: allowPrivateContext ?? this.allowPrivateContext,
      manualItems: manualItems ?? this.manualItems,
      currentSessionId: clearCurrentSessionId
          ? null
          : (currentSessionId ?? this.currentSessionId),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      suppressSessionRestore:
          suppressSessionRestore ?? this.suppressSessionRestore,
    );
  }
}
