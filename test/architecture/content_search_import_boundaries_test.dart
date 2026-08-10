import 'dart:io';

import '../support/architecture_test_harness_vm.dart'
    if (dart.library.ui) '../support/architecture_test_harness_flutter.dart';
import '../support/dart_import_graph.dart';

void main() {
  final graph = DartImportGraph.scan(
    packageRoot: Directory.current,
    packageName: 'note_secret_search',
  );

  architectureTest('content and search import graph is acyclic', () {
    final scopedCycles = graph
        .cyclicStronglyConnectedComponents()
        .where((component) => component.any(_isContentSearchSource))
        .toList(growable: false);

    expectArchitectureEquals(scopedCycles, const <List<String>>[]);
  });

  architectureTest(
    'content and search feature layers do not import app composition',
    () {
      expectArchitectureEquals(
        _matchingEdges(
          graph,
          source: (path) =>
              _isContentSearchSource(path) &&
              (path.contains('/application/') ||
                  path.contains('/presentation/')),
          target: (path) => path.startsWith('lib/app/'),
        ),
        const <String>[],
      );
    },
  );

  architectureTest(
    'content and search application layers use dependency tokens',
    () {
      expectArchitectureEquals(
        _matchingEdges(
          graph,
          source: (path) =>
              _isContentSearchSource(path) && path.contains('/application/'),
          target: (path) => path.contains('/infrastructure/'),
        ),
        const <String>[],
      );
    },
  );
}

bool _isContentSearchSource(String path) {
  return path.startsWith('lib/features/notes/') ||
      path.startsWith('lib/features/secrets/') ||
      path.startsWith('lib/features/vault/') ||
      path.startsWith('lib/features/search/') ||
      path ==
          'lib/features/ai_models/application/model_selection_providers.dart' ||
      path ==
          'lib/features/ai_models/application/'
              'model_selection_sensitive_providers.dart' ||
      path ==
          'lib/features/ai_models/domain/active_model_selection_store.dart' ||
      path ==
          'lib/features/ai_models/infrastructure/'
              'shared_preferences_active_model_selection_store.dart' ||
      path == 'lib/app/composition/content_search_composition.dart';
}

List<String> _matchingEdges(
  DartImportGraph graph, {
  required bool Function(String path) source,
  required bool Function(String path) target,
}) {
  final matches = <String>[];
  for (final sourcePath in graph.files.where(source)) {
    for (final targetPath in graph.importsFrom(sourcePath).where(target)) {
      matches.add('$sourcePath -> $targetPath');
    }
  }
  matches.sort();
  return matches;
}
