import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/auth_security/application/app_lock_lifecycle_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';

class AppLifecycleGuard extends ConsumerStatefulWidget {
  const AppLifecycleGuard({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLifecycleGuard> createState() => _AppLifecycleGuardState();
}

class _AppLifecycleGuardState extends ConsumerState<AppLifecycleGuard> {
  late final AppLockLifecycleController _lifecycleController;

  @override
  void initState() {
    super.initState();
    _lifecycleController = ref.read(appLockLifecycleControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lifecycleController.start();
    });
  }

  @override
  void dispose() {
    _lifecycleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
