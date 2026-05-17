import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';

Future<bool> confirmExternalPrivateContextSend({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final externalStatus = await ref.read(externalProviderStatusProvider.future);
  if (!externalStatus.available || externalStatus.config == null) {
    return true;
  }

  final config = externalStatus.config!;
  final confirmationController = ref.read(externalPrivacyConfirmationControllerProvider);
  final acknowledged = await confirmationController.hasAcknowledged(config.id);
  if (acknowledged) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('外发私密内容确认'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('你即将把私密内容发送到外部模型'),
              const SizedBox(height: 12),
              Text('目标服务：${config.displayName}'),
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

  await confirmationController.markAcknowledged(config.id);
  return true;
}
