import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/di/sensitive_state_invalidator_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/app/theme/app_theme.dart';
import 'package:note_secret_search/core/error/app_error_view.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lifecycle_guard.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';

class NoteSecretSearchApp extends ConsumerStatefulWidget {
  const NoteSecretSearchApp({super.key});

  @override
  ConsumerState<NoteSecretSearchApp> createState() =>
      _NoteSecretSearchAppState();
}

class _NoteSecretSearchAppState extends ConsumerState<NoteSecretSearchApp> {
  late final ProviderSubscription<LockSessionState> _lockSubscription;
  late final StreamSubscription<DatabaseLifecycleState> _databaseSubscription;
  var _initialSensitiveStateReady = false;

  @override
  void initState() {
    super.initState();
    final invalidator = ref.read(sensitiveStateInvalidatorProvider);
    final initialSession = ref.read(lockSessionControllerProvider);
    final database = ref.read(appDatabaseProvider);
    if (initialSession.isUnlocked &&
        database.state.status == DatabaseLifecycleStatus.open) {
      invalidator.allowSensitiveStateAccess();
      _initialSensitiveStateReady = true;
    } else {
      scheduleMicrotask(() {
        if (!mounted) {
          return;
        }
        final session = ref.read(lockSessionControllerProvider);
        final databaseState = ref.read(appDatabaseProvider).state;
        if (!session.isUnlocked ||
            databaseState.status != DatabaseLifecycleStatus.open) {
          invalidator.clearForLock();
        }
        if (mounted) {
          setState(() => _initialSensitiveStateReady = true);
        }
      });
    }

    _lockSubscription = ref.listenManual(lockSessionControllerProvider, (
      previous,
      next,
    ) {
      if (next.isUnlocked &&
          ref.read(appDatabaseProvider).state.status ==
              DatabaseLifecycleStatus.open) {
        invalidator.allowSensitiveStateAccess();
        return;
      }
      if (previous?.isUnlocked == true ||
          previous?.lockEpoch != next.lockEpoch) {
        invalidator.clearForLock();
      }
    });
    _databaseSubscription = database.states.listen((state) {
      if (!mounted) {
        return;
      }
      final session = ref.read(lockSessionControllerProvider);
      if (state.status == DatabaseLifecycleStatus.open && session.isUnlocked) {
        invalidator.allowSensitiveStateAccess();
        return;
      }
      if (state.status != DatabaseLifecycleStatus.open) {
        invalidator.clearForLock();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_databaseSubscription.cancel());
    _lockSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialSensitiveStateReady) {
      return const SizedBox.shrink();
    }

    final bootstrapState = ref.watch(appBootstrapProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Note Secret Search',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      builder: (context, child) {
        return bootstrapState.when(
          data: (_) => AppLifecycleGuard(
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, stackTrace) =>
              AppErrorView(title: '应用初始化失败', message: error.toString()),
        );
      },
    );
  }
}
