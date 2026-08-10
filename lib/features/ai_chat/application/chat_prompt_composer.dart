import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

enum ChatPromptTarget { local, external }

class ChatPromptException implements Exception {
  const ChatPromptException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}

class ChatHistoryTurn {
  const ChatHistoryTurn({
    required this.userText,
    required this.assistantText,
    required this.usedPrivateContext,
    this.usage,
  });

  final String userText;
  final String assistantText;
  final bool usedPrivateContext;
  final ChatBackendUsage? usage;
}

class ChatPromptComposition {
  const ChatPromptComposition({
    required this.prompt,
    required this.includedManualItems,
    required this.includedHistoryTurns,
    required this.includedAutoItems,
  });

  final String prompt;
  final int includedManualItems;
  final int includedHistoryTurns;
  final int includedAutoItems;
}

class ChatPromptComposer {
  const ChatPromptComposer();

  static const int localPromptBudget = 1200;
  static const int externalPromptBudget = 4000;
  static const int maxHistoryTurns = 6;

  ChatPromptComposition compose({
    required ChatMode mode,
    required String question,
    required ChatPromptTarget target,
    List<ProjectedChatContextItem> manualItems =
        const <ProjectedChatContextItem>[],
    List<ChatHistoryTurn> history = const <ChatHistoryTurn>[],
    List<ChatContextItem> autoItems = const <ChatContextItem>[],
    String? externalProviderFingerprint,
    bool includesPrivateContext = false,
  }) {
    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty) {
      throw const ChatPromptException(
        code: 'INVALID_ARGUMENT',
        message: '请输入问题或消息。',
      );
    }

    final budget = target == ChatPromptTarget.local
        ? localPromptBudget
        : externalPromptBudget;
    final questionBlock = '${_intro(mode)}\n\n用户问题：\n$normalizedQuestion';
    if (questionBlock.length > budget) {
      throw const ChatPromptException(
        code: 'PROMPT_TOO_LARGE',
        message: '当前问题超过模型输入上限，请缩短后重试。',
      );
    }

    final blocks = <String>[];
    var includedManualItems = 0;
    for (final item in manualItems) {
      final block = _manualBlock(item, includedManualItems + 1);
      if (block.isEmpty) {
        continue;
      }
      if (_fits([...blocks, block], questionBlock, budget)) {
        blocks.add(block);
        includedManualItems++;
      }
    }

    final eligibleHistory = _eligibleHistory(
      history,
      target: target,
      externalProviderFingerprint: externalProviderFingerprint,
      includesPrivateContext: includesPrivateContext,
    );
    final selectedHistory = <ChatHistoryTurn>[];
    for (final turn in eligibleHistory.reversed) {
      final tentative = <ChatHistoryTurn>[turn, ...selectedHistory];
      final block = _historyBlock(tentative);
      if (_fits([...blocks, block], questionBlock, budget)) {
        selectedHistory.insert(0, turn);
      }
    }
    if (selectedHistory.isNotEmpty) {
      blocks.add(_historyBlock(selectedHistory));
    }

    var includedAutoItems = 0;
    for (final item in autoItems) {
      final block = _autoBlock(item, includedAutoItems + 1);
      if (block.isEmpty) {
        continue;
      }
      if (_fits([...blocks, block], questionBlock, budget)) {
        blocks.add(block);
        includedAutoItems++;
      }
    }

    final prompt = [...blocks, questionBlock].join('\n\n');
    return ChatPromptComposition(
      prompt: prompt,
      includedManualItems: includedManualItems,
      includedHistoryTurns: selectedHistory.length,
      includedAutoItems: includedAutoItems,
    );
  }

  List<ChatHistoryTurn> _eligibleHistory(
    List<ChatHistoryTurn> history, {
    required ChatPromptTarget target,
    required String? externalProviderFingerprint,
    required bool includesPrivateContext,
  }) {
    final eligible = history
        .where((turn) {
          if (turn.userText.trim().isEmpty ||
              turn.assistantText.trim().isEmpty) {
            return false;
          }
          if (target == ChatPromptTarget.local) {
            return true;
          }
          if (externalProviderFingerprint == null ||
              externalProviderFingerprint.isEmpty ||
              turn.usage?.providerFingerprint != externalProviderFingerprint) {
            return false;
          }
          return includesPrivateContext || !turn.usedPrivateContext;
        })
        .toList(growable: false);
    if (eligible.length <= maxHistoryTurns) {
      return eligible;
    }
    return eligible.sublist(eligible.length - maxHistoryTurns);
  }

  String _manualBlock(ProjectedChatContextItem item, int index) {
    final lines = <String>[];
    if (item.title.trim().isNotEmpty) {
      lines.add('标题：${item.title.trim()}');
    }
    if (item.content.trim().isNotEmpty) {
      lines.add(item.content.trim());
    }
    if (lines.isEmpty) {
      return '';
    }
    return '手动上下文 $index：\n${lines.join('\n')}';
  }

  String _historyBlock(List<ChatHistoryTurn> turns) {
    final body = turns
        .map(
          (turn) =>
              '用户：${turn.userText.trim()}\n助手：${turn.assistantText.trim()}',
        )
        .join('\n\n');
    return '最近对话：\n$body';
  }

  String _autoBlock(ChatContextItem item, int index) {
    final summary = item.summary.trim();
    if (summary.isEmpty) {
      return '';
    }
    final title = item.title.trim();
    return title.isEmpty
        ? '自动上下文 $index：\n$summary'
        : '自动上下文 $index：${item.title.trim()}\n$summary';
  }

  bool _fits(List<String> blocks, String questionBlock, int budget) {
    return [...blocks, questionBlock].join('\n\n').length <= budget;
  }

  String _intro(ChatMode mode) {
    return switch (mode) {
      ChatMode.privateQa => '请仅依据获准的上下文回答；信息不足时明确说明。',
      ChatMode.freeChat => '请回答当前问题，并仅在有帮助时使用获准的上下文。',
    };
  }
}
