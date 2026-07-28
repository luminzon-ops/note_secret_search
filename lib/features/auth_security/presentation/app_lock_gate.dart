import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({
    required this.child,
    this.pinUnlockRouteActive = false,
    this.onPinUnlockRequested,
    this.onPinResetRequired,
    super.key,
  });

  final Widget child;
  final bool pinUnlockRouteActive;
  final Future<bool?> Function()? onPinUnlockRequested;
  final VoidCallback? onPinResetRequired;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  var _hydrationStarted = false;
  final Set<int> _scheduledRevealEpochs = <int>{};
  int? _revealedLockEpoch;
  NativeSecurityState? _securityState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrationStarted) {
      return;
    }
    _hydrationStarted = true;
    Future<void>(_refreshSecurityState);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(lockSessionControllerProvider);
    final pinState = ref.watch(pinStateControllerProvider);
    final databaseState =
        ref.watch(appDatabaseLifecycleProvider).valueOrNull ??
        const DatabaseLifecycleState.locked();
    final pinUnlockAllowed =
        widget.pinUnlockRouteActive &&
        session.pinEnabled &&
        pinState.enabled &&
        pinState.hasPinMaterial;
    if (session.isUnlocked &&
        databaseState.status == DatabaseLifecycleStatus.open) {
      return widget.child;
    }
    _scheduleSafeSurfaceReveal(session.lockEpoch);
    if (pinUnlockAllowed) {
      return widget.child;
    }

    return AppLockScreen(
      securityState: _securityState,
      databaseState: databaseState,
      onProvisioned: () => _refreshSecurityState(clearCachedState: true),
      onMigrationCompleted: (securityState) async {
        if (mounted) {
          setState(() => _securityState = securityState);
        }
      },
      onUnlocked: () {},
      onPinUnlockRequested: widget.onPinUnlockRequested,
      onPinResetRequired: widget.onPinResetRequired,
    );
  }

  Future<void> _refreshSecurityState({bool clearCachedState = false}) async {
    if (clearCachedState && mounted) {
      setState(() => _securityState = null);
    }
    SecurityOrchestrator? orchestrator;
    try {
      final resolvedOrchestrator = ref.read(securityOrchestratorProvider);
      orchestrator = resolvedOrchestrator;
      final securityState = await resolvedOrchestrator.refreshSecurityState();
      if (mounted) {
        setState(() => _securityState = securityState);
      }
    } catch (_) {
      orchestrator?.enablePinFallback(false);
    }
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
  const AppLockScreen({
    required this.onUnlocked,
    this.securityState,
    this.databaseState,
    this.onProvisioned,
    this.onMigrationCompleted,
    this.onPinUnlockRequested,
    this.onPinResetRequired,
    super.key,
  });

  final VoidCallback onUnlocked;
  final NativeSecurityState? securityState;
  final DatabaseLifecycleState? databaseState;
  final Future<void> Function()? onProvisioned;
  final Future<void> Function(NativeSecurityState securityState)?
  onMigrationCompleted;
  final Future<bool?> Function()? onPinUnlockRequested;
  final VoidCallback? onPinResetRequired;

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
    final securityStatus =
        widget.securityState?.status ?? NativeSecurityStatus.locked;
    final pinResetRequired = widget.securityState?.pinResetRequired ?? false;
    final provisioning = securityStatus == NativeSecurityStatus.unprovisioned;
    final legacyMigration =
        securityStatus == NativeSecurityStatus.legacyMigrationRequired;
    final databaseOpening =
        widget.databaseState?.status == DatabaseLifecycleStatus.opening;
    final databaseError =
        widget.databaseState?.status == DatabaseLifecycleStatus.error;
    final blocked =
        securityStatus == NativeSecurityStatus.recoveryRequired ||
        databaseOpening ||
        databaseError;
    final title = databaseOpening
        ? '正在打开安全数据库'
        : databaseError
        ? '安全数据库暂不可用'
        : switch (securityStatus) {
            NativeSecurityStatus.unprovisioned => '启用安全存储',
            NativeSecurityStatus.legacyMigrationRequired => '需要升级安全存储',
            NativeSecurityStatus.recoveryRequired => '需要恢复安全存储',
            NativeSecurityStatus.locked => '应用已锁定',
          };
    final description = databaseOpening
        ? '正在验证并准备本地加密数据。'
        : databaseError
        ? '数据库保持关闭，请重新锁定后再次尝试。'
        : switch (securityStatus) {
            NativeSecurityStatus.unprovisioned => '使用系统锁屏凭据创建受保护的本地密钥。',
            NativeSecurityStatus.legacyMigrationRequired =>
              '检测到旧版安全数据，完成升级前不会打开数据库。',
            NativeSecurityStatus.recoveryRequired => '安全密钥暂不可用，数据库将保持关闭并等待恢复。',
            NativeSecurityStatus.locked =>
              pinResetRequired
                  ? '应用 PIN 已损坏，请使用系统认证解锁并立即重新设置。'
                  : '默认使用系统生物识别解锁。应用 PIN 可在解锁后的安全设置中启用。',
          };

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
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: (_busy || blocked)
                      ? null
                      : provisioning
                      ? _provisionWithSystemAuth
                      : legacyMigration
                      ? _migrateLegacySecurity
                      : _unlockWithBiometrics,
                  icon: Icon(
                    legacyMigration ? Icons.upgrade : Icons.fingerprint,
                  ),
                  label: Text(
                    _busy
                        ? '验证中...'
                        : provisioning
                        ? '使用系统凭据启用'
                        : legacyMigration
                        ? '验证并升级安全存储'
                        : blocked
                        ? '安全存储不可用'
                        : '使用生物识别解锁',
                  ),
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
                if (!blocked &&
                    !provisioning &&
                    !pinResetRequired &&
                    session.pinEnabled &&
                    pinState.enabled &&
                    pinState.hasPinMaterial) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: (_busy || inCoolDown) ? null : _openPinUnlock,
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
      if (widget.securityState?.pinResetRequired == true) {
        widget.onPinResetRequired?.call();
      }
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
    } on DatabaseLifecycleException {
      if (mounted) {
        setState(() {
          _authenticationError = '安全数据库暂不可用，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _provisionWithSystemAuth() async {
    setState(() {
      _busy = true;
      _authenticationError = null;
    });
    try {
      final unlocked = await ref
          .read(securityOrchestratorProvider)
          .provisionWithSystemAuth();
      if (unlocked && mounted) {
        await widget.onProvisioned?.call();
        if (mounted) {
          widget.onUnlocked();
        }
      }
    } on NativeSecurityException catch (error) {
      if (mounted) {
        setState(() {
          _authenticationError = switch (error.code) {
            'AUTH_CANCELLED' => '身份验证已取消',
            'DEVICE_CREDENTIAL_NOT_SET' => '请先在系统设置中启用安全锁屏',
            _ => '安全存储启用失败，请重试',
          };
        });
      }
    } on DatabaseLifecycleException {
      if (mounted) {
        setState(() {
          _authenticationError = '安全数据库暂不可用，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _migrateLegacySecurity() async {
    setState(() {
      _busy = true;
      _authenticationError = null;
    });
    try {
      final securityState = await ref
          .read(securityOrchestratorProvider)
          .migrateLegacySecurity();
      if (mounted) {
        await widget.onMigrationCompleted?.call(securityState);
      }
    } on NativeSecurityException catch (error) {
      if (mounted) {
        setState(() {
          _authenticationError = switch (error.code) {
            'AUTH_CANCELLED' => '身份验证已取消',
            'DEVICE_CREDENTIAL_NOT_SET' => '请先在系统设置中启用安全锁屏',
            'MIGRATION_STORAGE_INSUFFICIENT' => '存储空间不足，暂时无法升级安全存储',
            _ => '安全存储升级失败，请重试',
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _authenticationError = '安全存储升级失败，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openPinUnlock() async {
    final unlocked = await widget.onPinUnlockRequested?.call();
    if (unlocked == true && mounted) {
      widget.onUnlocked();
    }
  }
}
