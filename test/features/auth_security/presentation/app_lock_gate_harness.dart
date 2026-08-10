part of 'app_lock_gate_test.dart';

GoRouter _createTestRouter({
  required LockSessionController sessionController,
  required PinStateController pinStateController,
}) {
  Widget placeholder(String label) {
    return Scaffold(body: Center(child: Text(label)));
  }

  final routeGuard = LockRouteGuard(navigation: PostUnlockNavigation());
  final refreshNotifier = _TestRouterRefreshNotifier(
    sessionController: sessionController,
    pinStateController: pinStateController,
  );
  addTearDown(refreshNotifier.dispose);
  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/vault',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => routeGuard.redirect(
      session: sessionController.state,
      pinState: pinStateController.state,
      uri: state.uri,
    ),
    routes: [
      GoRoute(
        path: '/unlock/pin',
        builder: (context, state) => PinUnlockPage(onUnlocked: router.refresh),
      ),
      GoRoute(
        path: '/vault',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('保险库')),
          body: const Text('vault home'),
        ),
      ),
      for (final path in const <String>[
        '/vault/secret/new',
        '/vault/secret/:id',
        '/vault/secret/:id/edit',
        '/search',
        '/search/settings',
        '/notes',
        '/notes/item/new',
        '/notes/item/:id',
        '/notes/item/:id/edit',
        '/ai/chat',
        '/models',
        '/settings',
        '/settings/security',
        '/settings/ai/providers',
      ])
        GoRoute(path: path, builder: (context, state) => placeholder(path)),
      GoRoute(
        path: '/settings/security/pin',
        builder: (context, state) => const PinSetupPage(),
      ),
    ],
  );
  return router;
}

class _TestRouterRefreshNotifier extends ChangeNotifier {
  _TestRouterRefreshNotifier({
    required LockSessionController sessionController,
    required PinStateController pinStateController,
  }) {
    _removeSessionListener = sessionController.addListener(
      (_) => notifyListeners(),
      fireImmediately: false,
    );
    _removePinStateListener = pinStateController.addListener(
      (_) => notifyListeners(),
      fireImmediately: false,
    );
  }

  late final VoidCallback _removeSessionListener;
  late final VoidCallback _removePinStateListener;

  @override
  void dispose() {
    _removeSessionListener();
    _removePinStateListener();
    super.dispose();
  }
}
