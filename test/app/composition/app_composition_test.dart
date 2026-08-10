import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/composition/app_composition.dart';
import 'package:note_secret_search/features/ai_models/application/local_llm_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app composition supplies content and AI dependency tokens', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai.active_llm_model_id': 'llm-1',
    });
    final container = ProviderContainer(overrides: appCompositionOverrides);
    addTearDown(container.dispose);

    expect(() => container.read(noteRepositoryProvider), returnsNormally);
    final selectionStore = container.read(localLlmSelectionStoreProvider);
    expect(await selectionStore.loadActiveModelId(), 'llm-1');
  });
}
