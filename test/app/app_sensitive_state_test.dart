import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/app.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';

const _manualContext = ChatContextItem(
  id: 'manual-sensitive',
  type: ChatContextItemType.secret,
  title: 'Sensitive context',
  preview: 'private preview',
  summary: 'private summary',
);

void main() {
  testWidgets(
    'initial locked app clears sensitive state before first content build',
    (tester) async {
      final sessionController = LockSessionController();
      final fixture = _AppFixture(sessionController);
      addTearDown(fixture.dispose);

      fixture.container.read(searchQueryProvider.notifier).state =
          'initial locked plaintext';
      final chatController = fixture.container.read(
        freeChatControllerProvider.notifier,
      );
      chatController.setAllowPrivateContext(true);
      chatController.setManualItems(const [_manualContext]);
      expect(
        fixture.container.read(sensitiveStateAccessAllowedProvider),
        isTrue,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const NoteSecretSearchApp(),
        ),
      );

      expect(find.byType(MaterialApp), findsNothing);

      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(
        fixture.container.read(sensitiveStateAccessAllowedProvider),
        isFalse,
      );
      expect(fixture.container.read(searchQueryProvider), isEmpty);
      expect(chatController.state.allowPrivateContext, isFalse);
      expect(chatController.state.manualItems, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unlocked to locked transition clears populated sensitive state',
    (tester) async {
      final sessionController = LockSessionController()
        ..markUnlocked(UnlockMethod.biometric);
      final fixture = _AppFixture(sessionController);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const NoteSecretSearchApp(),
        ),
      );
      await tester.pump();

      fixture.container.read(searchQueryProvider.notifier).state =
          'transition plaintext';
      final chatController = fixture.container.read(
        freeChatControllerProvider.notifier,
      );
      chatController.setAllowPrivateContext(true);
      chatController.setManualItems(const [_manualContext]);

      expect(
        fixture.container.read(sensitiveStateAccessAllowedProvider),
        isTrue,
      );
      expect(fixture.container.read(searchQueryProvider), isNotEmpty);

      sessionController.lock();
      await tester.pump();

      expect(
        fixture.container.read(sensitiveStateAccessAllowedProvider),
        isFalse,
      );
      expect(fixture.container.read(searchQueryProvider), isEmpty);
      expect(chatController.state.allowPrivateContext, isFalse);
      expect(chatController.state.manualItems, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _AppFixture {
  _AppFixture(LockSessionController sessionController)
    : router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('fixture')),
          ),
        ],
      ),
      bootstrapBlocker = Completer<void>() {
    container = ProviderContainer(
      overrides: [
        lockSessionControllerProvider.overrideWith((ref) => sessionController),
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        appRouterProvider.overrideWithValue(router),
        appBootstrapProvider.overrideWith((ref) => bootstrapBlocker.future),
      ],
    );
  }

  final GoRouter router;
  final Completer<void> bootstrapBlocker;
  late final ProviderContainer container;

  void dispose() {
    if (!bootstrapBlocker.isCompleted) {
      bootstrapBlocker.complete();
    }
    container.dispose();
    router.dispose();
  }
}
