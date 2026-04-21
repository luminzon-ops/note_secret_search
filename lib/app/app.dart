import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/app/theme/app_theme.dart';
import 'package:note_secret_search/core/error/app_error_view.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lifecycle_guard.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';

class NoteSecretSearchApp extends ConsumerWidget {
  const NoteSecretSearchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => AppErrorView(
            title: '应用初始化失败',
            message: error.toString(),
          ),
        );
      },
    );
  }
}
