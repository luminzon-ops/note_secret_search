import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';

class ChatRuntimeBanner extends StatelessWidget {
  const ChatRuntimeBanner({required this.readiness, required this.externalStatus, super.key});

  final LocalLlmReadiness readiness;
  final ExternalProviderStatus externalStatus;

  @override
  Widget build(BuildContext context) {
    final localRuntimeDegraded = readiness.runtimeState?.status == LlmRuntimeStatus.degraded;

    if (readiness.ready) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline),
              const SizedBox(width: 12),
              Expanded(child: Text(readiness.reason)),
            ],
          ),
        ),
      );
    }

    if (localRuntimeDegraded) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Text(readiness.reason)),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.push('/models'),
                child: const Text('前往模型管理'),
              ),
            ],
          ),
        ),
      );
    }

    if (externalStatus.available) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.cloud_done_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(externalStatus.reason)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(readiness.reason)),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.push('/models'),
              child: const Text('前往模型管理'),
            ),
          ],
        ),
      ),
    );
  }
}
