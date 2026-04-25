import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_management_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_detail_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_editor_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_list_page.dart';
import 'package:note_secret_search/features/search/presentation/search_page.dart';
import 'package:note_secret_search/features/search/presentation/search_settings_page.dart';
import 'package:note_secret_search/features/auth_security/presentation/pin_unlock_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_detail_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_editor_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_list_page.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';
import 'package:note_secret_search/features/settings/presentation/security_settings_page.dart';
import 'package:note_secret_search/features/settings/presentation/settings_page.dart';
import 'package:note_secret_search/shared/widgets/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/vault',
    routes: [
      GoRoute(
        path: '/unlock/pin',
        builder: (context, state) => const PinUnlockPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/vault',
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
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/search',
              name: 'search',
              builder: (context, state) => const SearchPage(),
              routes: [
                GoRoute(
                  path: 'settings',
                  builder: (context, state) => const SearchSettingsPage(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notes',
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
                      builder: (context, state) => NoteEditorPage(
                        noteId: state.pathParameters['id']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/models',
              name: 'models',
              builder: (context, state) => const ModelManagementPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsPage(),
              routes: [
                GoRoute(
                  path: 'security',
                  builder: (context, state) => const SecuritySettingsPage(),
                  routes: [
                    GoRoute(
                      path: 'pin',
                      builder: (context, state) => const PinSetupPage(),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
