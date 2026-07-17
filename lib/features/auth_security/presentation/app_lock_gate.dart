import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  var _hydrationStarted = false;
  var _vaultRedirectScheduled = false;
  final Set<int> _scheduledRevealEpochs = <int>{};
  int? _revealedLockEpoch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrationStarted) {
      return;
    }
    _hydrationStarted = true;
    Future<void>(() async {
      final orchestrator = ref.read(securityOrchestratorProvider);
      try {
        await orchestrator.refreshSecurityState();
      } catch (_) {
        orchestrator.enablePinFallback(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(lockSessionControllerProvider);
    final pinState = ref.watch(pinStateControllerProvider);
    final router = ref.watch(appRouterProvider);

    return ValueListenableBuilder<RouteInformation>(
      valueListenable: router.routeInformationProvider,
      builder: (context, routeInformation, _) {
        final location = routeInformation.uri.path;
        final pinUnlockAllowed =
            location == '/unlock/pin' &&
            session.pinEnabled &&
            pinState.enabled &&
            pinState.hasPinMaterial;
        if (session.isUnlocked) {
          return widget.child;
        }
        _scheduleSafeSurfaceReveal(session.lockEpoch);
        if (pinUnlockAllowed) {
          return widget.child;
        }
        if (location != '/vault') {
          _scheduleVaultRedirect(router);
        }

        return AppLockScreen(
          onUnlocked: () => ref.read(appRouterProvider).go('/vault'),
        );
      },
    );
  }

  void _scheduleVaultRedirect(GoRouter router) {
    if (_vaultRedirectScheduled) {
      return;
    }
    _vaultRedirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vaultRedirectScheduled = false;
      if (!mounted ||
          router.routeInformationProvider.value.uri.path == '/vault') {
        return;
      }
      router.go('/vault');
    });
  }

  void _scheduleSafeSurfaceReveal(int lockEpoch) {
    if (_revealedLockEpoch == lockEpoch ||
        !_scheduledRevealEpochs.add(lockEpoch)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final lifecycleState = WidgetsBinding.instance.lifecycleState;
        final session = ref.read(lockSessionControllerProvider);
        if (!mounted ||
            session.isUnlocked ||
            session.lockEpoch != lockEpoch ||
            (lifecycleState != null &&
                lifecycleState != AppLifecycleState.resumed)) {
          return;
        }
        await ref
            .read(screenshotProtectionGatewayProvider)
            .updateRecentTaskProtection(obscured: false);
        if (mounted) {
          final latestSession = ref.read(lockSessionControllerProvider);
          final latestLifecycleState = WidgetsBinding.instance.lifecycleState;
          final revealStillValid =
              !latestSession.isUnlocked &&
              latestSession.lockEpoch == lockEpoch &&
              (latestLifecycleState == null ||
                  latestLifecycleState == AppLifecycleState.resumed);
          if (!revealStillValid) {
            final appNotForeground =
                latestLifecycleState != null &&
                latestLifecycleState != AppLifecycleState.resumed;
            if (!latestSession.isUnlocked || appNotForeground) {
              await ref
                  .read(screenshotProtectionGatewayProvider)
                  .updateRecentTaskProtection(obscured: true);
            }
            return;
          }
          _revealedLockEpoch = lockEpoch;
        }
      } catch (_) {
        return;
      } finally {
        _scheduledRevealEpochs.remove(lockEpoch);
      }
    });
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
  String? _authenticationError;

  @override
  Widget build(BuildContext context) {
    final pinState = ref.watch(pinStateControllerProvider);
    final session = ref.watch(lockSessionControllerProvider);
    final coolDownUntil = pinState.coolDownUntil;
    final inCoolDown =
        coolDownUntil != null && coolDownUntil.isAfter(DateTime.now());

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
                Icon(
                  Icons.lock,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '应用已锁定',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  '默认使用系统生物识别解锁。应用 PIN 可在解锁后的安全设置中启用。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _unlockWithBiometrics,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_busy ? '验证中...' : '使用生物识别解锁'),
                ),
                if (_authenticationError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _authenticationError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (session.pinEnabled &&
                    pinState.enabled &&
                    pinState.hasPinMaterial) ...[
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
    setState(() {
      _busy = true;
      _authenticationError = null;
    });
    try {
      final unlocked = await ref
          .read(securityOrchestratorProvider)
          .unlockWithBiometrics();
      if (unlocked && mounted) {
        widget.onUnlocked();
      }
    } on NativeSecurityException catch (error) {
      if (mounted) {
        setState(() {
          _authenticationError = switch (error.code) {
            'AUTH_CANCELLED' => '身份验证已取消',
            'AUTH_LOCKOUT' => '系统认证暂时锁定，请稍后重试',
            'DEVICE_CREDENTIAL_NOT_SET' => '请先在系统设置中启用安全锁屏',
            'SECURITY_NOT_PROVISIONED' ||
            'MIGRATION_REQUIRED' ||
            'RECOVERY_REQUIRED' => '安全存储暂不可用',
            _ => '身份验证失败，请重试',
          };
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openPinUnlock() async {
    final unlocked = await ref
        .read(appRouterProvider)
        .push<bool>('/unlock/pin');
    if (unlocked == true && mounted) {
      widget.onUnlocked();
    }
  }
}
