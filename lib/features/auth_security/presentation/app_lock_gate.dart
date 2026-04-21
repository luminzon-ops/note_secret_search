import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';

class AppLockGate extends ConsumerWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(lockSessionControllerProvider);
    if (session.isUnlocked) {
      return child;
    }

    return AppLockScreen(onUnlocked: () => context.go('/vault'));
  }
}

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({required this.onUnlocked, super.key});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final pinState = ref.watch(pinStateControllerProvider);
    final session = ref.watch(lockSessionControllerProvider);
    final coolDownUntil = pinState.coolDownUntil;
    final inCoolDown = coolDownUntil != null && coolDownUntil.isAfter(DateTime.now());

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  '应用已锁定',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  '默认使用系统生物识别解锁，可选应用 PIN 作为备用入口。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _unlockWithBiometrics,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_busy ? '验证中...' : '使用生物识别解锁'),
                ),
                if (session.pinEnabled && pinState.hasPinMaterial) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: inCoolDown ? null : _openPinUnlock,
                    icon: const Icon(Icons.pin_outlined),
                    label: const Text('使用应用 PIN 解锁'),
                  ),
                ],
                if (pinState.failedAttempts > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    inCoolDown
                        ? 'PIN 已进入冷却，稍后再试。'
                        : 'PIN 连续失败 ${pinState.failedAttempts} 次。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() => _busy = true);
    try {
      final unlocked = await ref.read(securityOrchestratorProvider).unlockWithBiometrics();
      if (unlocked && mounted) {
        widget.onUnlocked();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openPinUnlock() async {
    final unlocked = await context.push<bool>('/unlock/pin');
    if (unlocked == true && mounted) {
      widget.onUnlocked();
    }
  }
}
