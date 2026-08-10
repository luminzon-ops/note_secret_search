import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_detail_page.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_editor_page.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

import '../../../support/content_mutation_fakes.dart';
import '../../../support/content_mutation_harness.dart';

void main() {
  testWidgets('saving a secret persists, auto-indexes when enabled, and pops', (
    tester,
  ) async {
    final repository = RecordingSecretRepository();
    final indexRecorder = ContentMutationSearchIndexRecorder();
    await _pumpEditor(
      tester,
      repository: repository,
      indexRecorder: indexRecorder,
      defaultVault: characterizationVault(),
      activeEmbeddingModel: characterizationEmbeddingModel,
      autoIndexEnabled: true,
    );

    await _enterRequiredFields(tester);
    await revealAndTap(
      tester,
      saveContentMutationButton,
      scrollable: contentMutationScrollable,
    );
    await tester.pumpAndSettle();

    expect(repository.savedItems, hasLength(1));
    expect(repository.savedItems.single.vaultId, 'vault-1');
    expect(repository.savedItems.single.title, 'Characterized secret');
    expect(indexRecorder.indexPendingCalls, 1);
    expect(find.byKey(contentMutationHostKey), findsOneWidget);
  });

  testWidgets(
    'saving a secret without a default vault leaves the editor open',
    (tester) async {
      final repository = RecordingSecretRepository();
      final indexRecorder = ContentMutationSearchIndexRecorder();
      await _pumpEditor(
        tester,
        repository: repository,
        indexRecorder: indexRecorder,
        defaultVault: null,
        activeEmbeddingModel: characterizationEmbeddingModel,
        autoIndexEnabled: true,
      );

      await _enterRequiredFields(tester);
      await revealAndTap(
        tester,
        saveContentMutationButton,
        scrollable: contentMutationScrollable,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.savedItems, isEmpty);
      expect(indexRecorder.indexPendingCalls, 0);
      expect(find.text('新增密码'), findsOneWidget);
      expect(find.byKey(contentMutationHostKey), findsNothing);
    },
  );

  testWidgets('saving a secret skips auto-index without an active model', (
    tester,
  ) async {
    await _expectSaveSkipsIndex(
      tester,
      activeEmbeddingModel: null,
      autoIndexEnabled: true,
    );
  });

  testWidgets('saving a secret skips auto-index when auto-index is disabled', (
    tester,
  ) async {
    await _expectSaveSkipsIndex(
      tester,
      activeEmbeddingModel: characterizationEmbeddingModel,
      autoIndexEnabled: false,
    );
  });

  testWidgets(
    'deleting a secret soft-deletes, auto-indexes when enabled, and pops',
    (tester) async {
      final secret = characterizationSecret();
      final repository = RecordingSecretRepository(item: secret);
      final indexRecorder = ContentMutationSearchIndexRecorder();
      await _pumpDetail(
        tester,
        repository: repository,
        indexRecorder: indexRecorder,
        activeEmbeddingModel: characterizationEmbeddingModel,
        autoIndexEnabled: true,
      );

      await tester.tap(deleteContentMutationButton);
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>[secret.id]);
      expect(indexRecorder.indexPendingCalls, 1);
      expect(find.byKey(contentMutationHostKey), findsOneWidget);
    },
  );

  testWidgets('deleting a secret skips auto-index without an active model', (
    tester,
  ) async {
    await _expectDeleteSkipsIndex(
      tester,
      activeEmbeddingModel: null,
      autoIndexEnabled: true,
    );
  });

  testWidgets(
    'deleting a secret skips auto-index when auto-index is disabled',
    (tester) async {
      await _expectDeleteSkipsIndex(
        tester,
        activeEmbeddingModel: characterizationEmbeddingModel,
        autoIndexEnabled: false,
      );
    },
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RecordingSecretRepository repository,
  required ContentMutationSearchIndexRecorder indexRecorder,
  required Vault? defaultVault,
  required ModelRegistryEntry? activeEmbeddingModel,
  required bool autoIndexEnabled,
}) {
  return pumpContentMutationPage(
    tester,
    page: const SecretEditorPage(),
    overrides: <Override>[
      secretRepositoryProvider.overrideWithValue(repository),
      ...contentMutationOverrides(
        defaultVault: defaultVault,
        activeEmbeddingModel: activeEmbeddingModel,
        autoIndexEnabled: autoIndexEnabled,
        indexRecorder: indexRecorder,
      ),
    ],
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required RecordingSecretRepository repository,
  required ContentMutationSearchIndexRecorder indexRecorder,
  required ModelRegistryEntry? activeEmbeddingModel,
  required bool autoIndexEnabled,
}) {
  final secret = repository.item!;
  return pumpContentMutationPage(
    tester,
    page: SecretDetailPage(secretId: secret.id),
    overrides: <Override>[
      secretRepositoryProvider.overrideWithValue(repository),
      secretDetailProvider(secret.id).overrideWith((ref) async => secret),
      ...contentMutationOverrides(
        defaultVault: characterizationVault(),
        activeEmbeddingModel: activeEmbeddingModel,
        autoIndexEnabled: autoIndexEnabled,
        indexRecorder: indexRecorder,
      ),
    ],
  );
}

Future<void> _enterRequiredFields(WidgetTester tester) async {
  final title = formFieldWithLabel('标题 *');
  await reveal(tester, title, scrollable: contentMutationScrollable);
  await tester.enterText(title, 'Characterized secret');
  await dismissContentMutationInput(tester);
}

Future<void> _expectSaveSkipsIndex(
  WidgetTester tester, {
  required ModelRegistryEntry? activeEmbeddingModel,
  required bool autoIndexEnabled,
}) async {
  final repository = RecordingSecretRepository();
  final indexRecorder = ContentMutationSearchIndexRecorder();
  await _pumpEditor(
    tester,
    repository: repository,
    indexRecorder: indexRecorder,
    defaultVault: characterizationVault(),
    activeEmbeddingModel: activeEmbeddingModel,
    autoIndexEnabled: autoIndexEnabled,
  );

  await _enterRequiredFields(tester);
  await revealAndTap(
    tester,
    saveContentMutationButton,
    scrollable: contentMutationScrollable,
  );
  await tester.pumpAndSettle();

  expect(repository.savedItems, hasLength(1));
  expect(indexRecorder.indexPendingCalls, 0);
  expect(find.byKey(contentMutationHostKey), findsOneWidget);
}

Future<void> _expectDeleteSkipsIndex(
  WidgetTester tester, {
  required ModelRegistryEntry? activeEmbeddingModel,
  required bool autoIndexEnabled,
}) async {
  final secret = characterizationSecret();
  final repository = RecordingSecretRepository(item: secret);
  final indexRecorder = ContentMutationSearchIndexRecorder();
  await _pumpDetail(
    tester,
    repository: repository,
    indexRecorder: indexRecorder,
    activeEmbeddingModel: activeEmbeddingModel,
    autoIndexEnabled: autoIndexEnabled,
  );

  await tester.tap(deleteContentMutationButton);
  await tester.pumpAndSettle();

  expect(repository.deletedIds, <String>[secret.id]);
  expect(indexRecorder.indexPendingCalls, 0);
  expect(find.byKey(contentMutationHostKey), findsOneWidget);
}
