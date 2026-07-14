part of 'sensitive_state_invalidator_provider_test.dart';

void registerSensitiveStateInvalidatorWidgetTests() {
  testWidgets(
    'secret editor detail cache is purged and cannot reload while locked',
    (tester) async {
      final secretRepository = _SecretRepository();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          secretRepositoryProvider.overrideWithValue(secretRepository),
        ],
      );
      addTearDown(container.dispose);

      Future<void> pumpEditor() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: secret_editor.SecretEditorPage(
                secretId: 'secret-sensitive',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpEditor();

      expect(secretRepository.reads, 1);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller
            ?.text,
        'Sensitive secret',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      container.read(sensitiveStateInvalidatorProvider).clearForLock();
      final readsAfterLock = secretRepository.reads;

      await pumpEditor();

      expect(container.read(sensitiveStateAccessAllowedProvider), isFalse);
      expect(secretRepository.reads, readsAfterLock);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller
            ?.text,
        isEmpty,
      );
    },
  );
}
