import 'dart:io';

import '../support/architecture_test_harness_vm.dart'
    if (dart.library.ui) '../support/architecture_test_harness_flutter.dart';
import '../support/dart_import_graph.dart';

void main() {
  architectureTest(
    'current lib import graph has exactly the three Phase 8 SCCs',
    () {
      final graph = DartImportGraph.scan(
        packageRoot: Directory.current,
        packageName: 'note_secret_search',
      );

      expectArchitectureEquals(graph.cyclicStronglyConnectedComponents(), const [
        [
          'lib/app/di/bootstrap_provider.dart',
          'lib/features/settings/application/security_settings_providers.dart',
        ],
        [
          'lib/features/ai_chat/application/llm_runtime_providers.dart',
          'lib/features/ai_models/application/model_download_providers.dart',
        ],
        [
          'lib/features/ai_models/application/model_selection_providers.dart',
          'lib/features/search/application/search_index_settings_providers.dart',
          'lib/features/search/application/search_providers.dart',
        ],
      ]);
    },
  );
}
