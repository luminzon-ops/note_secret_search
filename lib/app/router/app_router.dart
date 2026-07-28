import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/router/lock_route_guard.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:note_secret_search/features/ai_providers/presentation/external_provider_settings_page.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_management_page.dart';
import 'package:note_secret_search/features/auth_security/presentation/pin_unlock_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_detail_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_editor_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_list_page.dart';
import 'package:note_secret_search/features/search/presentation/search_page.dart';
import 'package:note_secret_search/features/search/presentation/search_settings_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_detail_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_editor_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_list_page.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';
import 'package:note_secret_search/features/settings/presentation/security_settings_page.dart';
import 'package:note_secret_search/features/settings/presentation/settings_page.dart';
import 'package:note_secret_search/shared/navigation/app_destination.dart';
import 'package:note_secret_search/shared/widgets/app_shell.dart';

final _appRouterRefreshProvider = Provider<_AppRouterRefreshNotifier>((ref) {
  final notifier = _AppRouterRefreshNotifier();
  final postUnlockNavigation = ref.watch(postUnlockNavigationProvider);
  postUnlockNavigation.addListener(notifier.refresh);
  ref.listen(lockSessionControllerProvider, (_, __) => notifier.refresh());
  ref.listen(pinStateControllerProvider, (_, __) => notifier.refresh());
  ref.onDispose(() {
    postUnlockNavigation.removeListener(notifier.refresh);
    notifier.dispose();
  });
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final lockRouteGuard = LockRouteGuard(
    navigation: ref.watch(postUnlockNavigationProvider),
  );
  late final GoRouter router;
  router = GoRouter(
    initialLocation: AppDestination.vault,
    refreshListenable: ref.watch(_appRouterRefreshProvider),
    redirect: (context, state) {
      return lockRouteGuard.redirect(
        session: ref.read(lockSessionControllerProvider),
        pinState: ref.read(pinStateControllerProvider),
        uri: state.uri,
      );
    },
    routes: [
      GoRoute(
        path: AppDestination.pinUnlock,
        builder: (context, state) => PinUnlockPage(
          onUnlocked: router.refresh,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.vault,
                name: 'vault',
                builder: (context, state) => const SecretListPage(),
                routes: [
                  GoRoute(
                    path: 'secret/new',
                    builder: (context, state) => const SecretEditorPage(),
                  ),
                  GoRoute(
                    path: 'secret/:id',
                    builder: (context, state) => SecretDetailPage(
                      secretId: state.pathParameters['id']!,
                      searchQuery: state.uri.queryParameters['query'],
                      searchSource: state.uri.queryParameters['source'],
                      searchContext: state.uri.queryParameters['context'],
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => SecretEditorPage(
                          secretId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.search,
                name: 'search',
                builder: (context, state) => const SearchPage(),
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SearchSettingsPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.notes,
                name: 'notes',
                builder: (context, state) => const NoteListPage(),
                routes: [
                  GoRoute(
                    path: 'item/new',
                    builder: (context, state) => const NoteEditorPage(),
                  ),
                  GoRoute(
                    path: 'item/:id',
                    builder: (context, state) => NoteDetailPage(
                      noteId: state.pathParameters['id']!,
                      searchQuery: state.uri.queryParameters['query'],
                      searchSource: state.uri.queryParameters['source'],
                      searchContext: state.uri.queryParameters['context'],
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) =>
                            NoteEditorPage(noteId: state.pathParameters['id']!),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.aiChat,
                name: 'aiChat',
                builder: (context, state) => AiChatPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.models,
                name: 'models',
                builder: (context, state) => const ModelManagementPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.settings,
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'security',
                    builder: (context, state) => const SecuritySettingsPage(),
                    routes: [
                      GoRoute(
                        path: 'pin',
                        builder: (context, state) => PinSetupPage(
                          onPinSaved: ref
                              .read(postUnlockNavigationProvider)
                              .completePinReset,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'ai/providers',
                    builder: (context, state) =>
                        const ExternalProviderSettingsPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _AppRouterRefreshNotifier extends ChangeNotifier {
  void refresh() {
    notifyListeners();
  }
}
