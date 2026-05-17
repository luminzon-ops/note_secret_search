import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_runtime_banner.dart';

void main() {
  testWidgets('unavailable runtime CTA is not nested inside a ListTile', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatRuntimeBanner(
            readiness: LocalLlmReadiness(
              ready: false,
              reason: '尚未选择本地 LLM 模型。',
              activeModel: null,
              runtimeState: null,
            ),
            externalStatus: ExternalProviderStatus(
              available: false,
              reason: '尚未启用外部模型提供方。',
              config: null,
            ),
          ),
        ),
      ),
    );

    final ctaFinder = find.widgetWithText(TextButton, '前往模型管理');

    expect(ctaFinder, findsOneWidget);
    expect(find.ancestor(of: ctaFinder, matching: find.byType(ListTile)), findsNothing);
  });

  testWidgets('degraded local runtime warning takes precedence over external-ready banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatRuntimeBanner(
            readiness: LocalLlmReadiness(
              ready: false,
              reason: '本地 LLM 模型探测失败，需要重新下载或修复。',
              activeModel: null,
              runtimeState: LlmRuntimeState(
                ready: false,
                reason: '本地 LLM 模型探测失败，需要重新下载或修复。',
                status: LlmRuntimeStatus.degraded,
              ),
            ),
            externalStatus: ExternalProviderStatus(
              available: true,
              reason: '外部模型已可用：OpenAI 兼容服务',
              config: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('本地 LLM 模型探测失败，需要重新下载或修复。'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '前往模型管理'), findsOneWidget);
    expect(find.text('外部模型已可用：OpenAI 兼容服务'), findsNothing);
  });

  testWidgets('ready local runtime shows local-ready banner instead of CTA', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatRuntimeBanner(
            readiness: LocalLlmReadiness(
              ready: true,
              reason: '本地 LLM 模型已就绪：Qwen GGUF',
              activeModel: null,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: '本地 LLM 模型已就绪：Qwen GGUF',
                status: LlmRuntimeStatus.ready,
              ),
            ),
            externalStatus: ExternalProviderStatus(
              available: false,
              reason: '尚未启用外部模型提供方。',
              config: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('本地 LLM 模型已就绪：Qwen GGUF'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.widgetWithText(TextButton, '前往模型管理'), findsNothing);
  });

  testWidgets('external-ready banner shows provider status when local runtime is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatRuntimeBanner(
            readiness: LocalLlmReadiness(
              ready: false,
              reason: '尚未选择本地 LLM 模型。',
              activeModel: null,
              runtimeState: null,
            ),
            externalStatus: ExternalProviderStatus(
              available: true,
              reason: '外部模型已可用：OpenAI 兼容服务',
              config: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('外部模型已可用：OpenAI 兼容服务'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.widgetWithText(TextButton, '前往模型管理'), findsNothing);
  });
}
