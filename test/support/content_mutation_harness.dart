import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'widget_test_helpers.dart' show reveal, revealAndTap;

const contentMutationHostKey = ValueKey<String>('content-mutation-host');
const openContentMutationPageKey = ValueKey<String>(
  'open-content-mutation-page',
);

Future<void> pumpContentMutationPage(
  WidgetTester tester, {
  required Widget page,
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Mutation host', key: contentMutationHostKey),
                FilledButton(
                  key: openContentMutationPageKey,
                  onPressed: () => context.push('/mutation'),
                  child: const Text('Open mutation page'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(path: '/mutation', builder: (context, state) => page),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(openContentMutationPageKey));
  await tester.pumpAndSettle();
}

Finder formFieldWithLabel(String label) {
  return find.widgetWithText(TextFormField, label);
}

Finder get saveContentMutationButton {
  return find.widgetWithText(FilledButton, '保存');
}

Finder get contentMutationScrollable => find.byType(ListView);

Finder get deleteContentMutationButton {
  return find.widgetWithIcon(IconButton, Icons.delete_outline);
}

Future<void> dismissContentMutationInput(WidgetTester tester) async {
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}
