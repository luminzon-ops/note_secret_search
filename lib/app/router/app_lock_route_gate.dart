import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/router/lock_route_guard.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';
import 'package:note_secret_search/shared/navigation/app_destination.dart';

class AppLockRouteGate extends ConsumerWidget {
  const AppLockRouteGate({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postUnlockNavigation = ref.read(postUnlockNavigationProvider);
    return ValueListenableBuilder<RouteInformation>(
      valueListenable: router.routeInformationProvider,
      builder: (context, routeInformation, _) => AppLockGate(
        pinUnlockRouteActive:
            routeInformation.uri.path == AppDestination.pinUnlock,
        onPinUnlockRequested: () async {
          router.go(AppDestination.pinUnlock);
          return null;
        },
        onPinResetRequired: postUnlockNavigation.requirePinReset,
        child: child,
      ),
    );
  }
}
