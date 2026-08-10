import 'dart:io';

import '../support/architecture_test_harness_vm.dart'
    if (dart.library.ui) '../support/architecture_test_harness_flutter.dart';
import '../support/dart_import_graph.dart';

void main() {
  final graph = DartImportGraph.scan(
    packageRoot: Directory.current,
    packageName: 'note_secret_search',
  );

  architectureTest('lib import graph is acyclic', () {
    expectArchitectureEquals(
      graph.cyclicStronglyConnectedComponents(),
      const <List<String>>[],
    );
  });

  architectureTest('features and core do not import the app layer', () {
    expectArchitectureEquals(
      _matchingEdges(
        graph,
        source: (path) =>
            path.startsWith('lib/features/') || path.startsWith('lib/core/'),
        target: (path) => path.startsWith('lib/app/'),
      ),
      const <String>[],
    );
  });

  architectureTest('core does not import feature modules', () {
    expectArchitectureEquals(
      _matchingEdges(
        graph,
        source: (path) => path.startsWith('lib/core/'),
        target: (path) => path.startsWith('lib/features/'),
      ),
      const <String>[],
    );
  });

  architectureTest(
    'feature application modules do not import concrete infrastructure',
    () {
      expectArchitectureEquals(
        _matchingEdges(
          graph,
          source: (path) =>
              path.startsWith('lib/features/') &&
              path.contains('/application/'),
          target: (path) => path.contains('/infrastructure/'),
        ),
        const <String>[],
      );
    },
  );
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
