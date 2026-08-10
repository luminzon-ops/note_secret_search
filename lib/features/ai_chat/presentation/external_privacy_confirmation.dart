import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';

Future<bool> confirmExternalProviderSend({
  required BuildContext context,
  required WidgetRef ref,
  required bool includesPrivateContext,
}) async {
  final externalStatus = await ref.read(externalProviderStatusProvider.future);
  if (!externalStatus.available || externalStatus.config == null) {
    return false;
  }

  final config = externalStatus.config!;
  final confirmationController = ref.read(
    externalPrivacyConfirmationControllerProvider,
  );
  final acknowledged = await confirmationController.hasAcknowledged(
    config,
    includesPrivateContext: includesPrivateContext,
  );
  if (acknowledged) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }

  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认使用外部模型'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('提供商：${_providerTypeLabel(config.providerType)}'),
              const SizedBox(height: 8),
              Text(
                'Endpoint：${normalizeExternalProviderEndpoint(config.baseUrl)}',
              ),
              const SizedBox(height: 8),
              Text('模型：${config.modelName.trim()}'),
              const SizedBox(height: 8),
              Text('包含私密上下文：${includesPrivateContext ? '是' : '否'}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续发送'),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed) {
    return false;
  }

  await confirmationController.markAcknowledged(
    config,
    includesPrivateContext: includesPrivateContext,
  );
  return true;
}

String _providerTypeLabel(ExternalProviderType type) {
  return switch (type) {
    ExternalProviderType.openAiCompatible => 'OpenAI 兼容接口',
    ExternalProviderType.ollama => 'Ollama',
  };
}
