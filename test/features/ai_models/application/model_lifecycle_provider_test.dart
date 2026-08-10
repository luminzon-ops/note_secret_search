import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/composition/ai_composition.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_lifecycle_store.dart';

import '../../../support/fake_app_database.dart';

void main() {
  test('lifecycle provider keeps SQLite as the transaction owner', () {
    final container = ProviderContainer(
      overrides: <Override>[
        ...aiCompositionOverrides,
        appDatabaseProvider.overrideWithValue(
          FakeAppDatabase(initialStatus: DatabaseLifecycleStatus.open),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(modelLifecycleStoreProvider),
      isA<SqliteModelLifecycleStore>(),
    );
  });
}
