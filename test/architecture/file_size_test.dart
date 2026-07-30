import 'dart:io';

import '../support/architecture_test_harness_vm.dart'
    if (dart.library.ui) '../support/architecture_test_harness_flutter.dart';

void main() {
  architectureTest('non-generated Dart files stay at or below 500 lines', () {
    final oversized = <String>[];
    for (final rootName in const ['lib', 'test']) {
      final root = Directory(rootName);
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final relativePath = entity.path
            .replaceAll('\\', '/')
            .replaceFirst(
              '${Directory.current.path.replaceAll('\\', '/')}/',
              '',
            );
        if (_isGenerated(relativePath)) {
          continue;
        }
        final lineCount = entity.readAsLinesSync().length;
        if (lineCount > 500) {
          oversized.add('$relativePath ($lineCount lines)');
        }
      }
    }
    oversized.sort();
    expectArchitectureEquals(oversized, const <String>[]);
  });
}

bool _isGenerated(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.endsWith('.mocks.dart');
}
