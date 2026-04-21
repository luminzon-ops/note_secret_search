import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';

class AppLifecycleGuard extends ConsumerStatefulWidget {
  const AppLifecycleGuard({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLifecycleGuard> createState() => _AppLifecycleGuardState();
}

class _AppLifecycleGuardState extends ConsumerState<AppLifecycleGuard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appLockLifecycleControllerProvider).start();
    });
  }

  @override
  void dispose() {
    ref.read(appLockLifecycleControllerProvider).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
