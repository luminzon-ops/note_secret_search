import 'dart:io';

final class DartImportGraph {
  DartImportGraph._(this._importsByFile);

  factory DartImportGraph.scan({
    required Directory packageRoot,
    required String packageName,
  }) {
    final libDirectory = Directory(
      '${packageRoot.path}${Platform.pathSeparator}lib',
    );
    if (!libDirectory.existsSync()) {
      throw StateError('Missing lib directory: ${libDirectory.path}');
    }

    final sourceFiles =
        libDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    final nodes = <String>{
      for (final file in sourceFiles)
        _packageRelativePath(packageRoot: packageRoot, file: file),
    };
    final importsByFile = <String, Set<String>>{};

    for (final file in sourceFiles) {
      final sourcePath = _packageRelativePath(
        packageRoot: packageRoot,
        file: file,
      );
      final imports = <String>{};
      for (final uri in _parseImportUris(file.readAsStringSync())) {
        final target = _resolveInternalImport(
          sourcePath: sourcePath,
          importUri: uri,
          packageName: packageName,
        );
        if (target != null && nodes.contains(target)) {
          imports.add(target);
        }
      }
      importsByFile[sourcePath] = imports;
    }

    return DartImportGraph._(importsByFile);
  }

  final Map<String, Set<String>> _importsByFile;

  List<String> get files => _importsByFile.keys.toList(growable: false)..sort();

  Set<String> importsFrom(String sourcePath) {
    return Set<String>.unmodifiable(
      _importsByFile[sourcePath] ?? const <String>{},
    );
  }

  List<List<String>> cyclicStronglyConnectedComponents() {
    final components = _stronglyConnectedComponents().where((component) {
      if (component.length > 1) {
        return true;
      }
      final node = component.single;
      return _importsByFile[node]?.contains(node) ?? false;
    }).toList();

    for (final component in components) {
      component.sort();
    }
    components.sort((left, right) => left.first.compareTo(right.first));
    return components;
  }

  List<List<String>> _stronglyConnectedComponents() {
    var nextIndex = 0;
    final indexByNode = <String, int>{};
    final lowLinkByNode = <String, int>{};
    final stack = <String>[];
    final nodesOnStack = <String>{};
    final components = <List<String>>[];

    void connect(String node) {
      indexByNode[node] = nextIndex;
      lowLinkByNode[node] = nextIndex;
      nextIndex += 1;
      stack.add(node);
      nodesOnStack.add(node);

      final targets = _importsByFile[node]!.toList()..sort();
      for (final target in targets) {
        if (!indexByNode.containsKey(target)) {
          connect(target);
          lowLinkByNode[node] = _min(
            lowLinkByNode[node]!,
            lowLinkByNode[target]!,
          );
        } else if (nodesOnStack.contains(target)) {
          lowLinkByNode[node] = _min(
            lowLinkByNode[node]!,
            indexByNode[target]!,
          );
        }
      }

      if (lowLinkByNode[node] != indexByNode[node]) {
        return;
      }

      final component = <String>[];
      while (true) {
        final member = stack.removeLast();
        nodesOnStack.remove(member);
        component.add(member);
        if (member == node) {
          break;
        }
      }
      components.add(component);
    }

    final nodes = _importsByFile.keys.toList()..sort();
    for (final node in nodes) {
      if (!indexByNode.containsKey(node)) {
        connect(node);
      }
    }
    return components;
  }
}

String _packageRelativePath({
  required Directory packageRoot,
  required File file,
}) {
  final rootPath = packageRoot.absolute.path.replaceAll(r'\', '/');
  final filePath = file.absolute.path.replaceAll(r'\', '/');
  final rootPrefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  final matchesRoot = Platform.isWindows
      ? filePath.toLowerCase().startsWith(rootPrefix.toLowerCase())
      : filePath.startsWith(rootPrefix);
  if (!matchesRoot) {
    throw StateError('Source file is outside package root: ${file.path}');
  }
  return filePath.substring(rootPrefix.length);
}

Iterable<String> _parseImportUris(String source) sync* {
  final sourceWithoutComments = _stripComments(source);
  final directivePattern = RegExp(
    r'''^\s*import\b([\s\S]*?);''',
    multiLine: true,
  );
  final uriPattern = RegExp(r'''(?:r)?(['"])([^'"]+)\1''');

  for (final directive in directivePattern.allMatches(sourceWithoutComments)) {
    final body = directive.group(1)!;
    for (final uriMatch in uriPattern.allMatches(body)) {
      yield uriMatch.group(2)!;
    }
  }
}

String? _resolveInternalImport({
  required String sourcePath,
  required String importUri,
  required String packageName,
}) {
  final uri = Uri.parse(importUri);
  if (uri.scheme == 'package') {
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.first != packageName) {
      return null;
    }
    return _normalizePath(['lib', ...segments.skip(1)].join('/'));
  }

  if (uri.hasScheme || importUri.startsWith('/')) {
    return null;
  }
  return _normalizePath('${_directoryName(sourcePath)}/${uri.path}');
}

String _normalizePath(String value) {
  final segments = <String>[];
  for (final segment in value.replaceAll(r'\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isEmpty) {
        return value;
      }
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

String _directoryName(String value) {
  final separator = value.lastIndexOf('/');
  return separator == -1 ? '.' : value.substring(0, separator);
}

String _stripComments(String source) {
  final output = StringBuffer();
  var index = 0;
  var blockDepth = 0;

  while (index < source.length) {
    if (blockDepth > 0) {
      if (_startsWith(source, index, '/*')) {
        output.write('  ');
        blockDepth += 1;
        index += 2;
      } else if (_startsWith(source, index, '*/')) {
        output.write('  ');
        blockDepth -= 1;
        index += 2;
      } else {
        final character = source[index];
        output.write(character == '\n' ? '\n' : ' ');
        index += 1;
      }
      continue;
    }

    if (_startsWith(source, index, '//')) {
      output.write('  ');
      index += 2;
      while (index < source.length && source[index] != '\n') {
        output.write(' ');
        index += 1;
      }
      continue;
    }
    if (_startsWith(source, index, '/*')) {
      output.write('  ');
      blockDepth = 1;
      index += 2;
      continue;
    }

    final character = source[index];
    if (character == "'" || character == '"') {
      index = _copyStringLiteral(source, output, index);
      continue;
    }

    output.write(character);
    index += 1;
  }

  return output.toString();
}

int _copyStringLiteral(String source, StringBuffer output, int start) {
  final quote = source[start];
  final triple = _startsWith(source, start, quote * 3);
  final delimiter = triple ? quote * 3 : quote;
  var index = start;

  output.write(delimiter);
  index += delimiter.length;
  while (index < source.length) {
    if (_startsWith(source, index, delimiter)) {
      output.write(delimiter);
      return index + delimiter.length;
    }
    if (source[index] == r'\' && index + 1 < source.length) {
      output
        ..write(source[index])
        ..write(source[index + 1]);
      index += 2;
      continue;
    }
    output.write(source[index]);
    index += 1;
  }
  return index;
}

bool _startsWith(String source, int index, String value) {
  return index + value.length <= source.length &&
      source.startsWith(value, index);
}

int _min(int left, int right) => left < right ? left : right;
