import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';

class SecurityStatusCard extends ConsumerWidget {
  const SecurityStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(lockSessionControllerProvider);
    final pinState = ref.watch(pinStateControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安全状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(session.isUnlocked ? '当前会话已解锁' : '当前会话已锁定'),
            const SizedBox(height: 4),
            Text(session.pinEnabled ? '已启用应用 PIN 备用入口' : '尚未启用应用 PIN'),
            const SizedBox(height: 4),
            Text(pinState.hasPinMaterial ? 'PIN 材料已准备' : 'PIN 材料未初始化'),
          ],
        ),
      ),
    );
  }
}
