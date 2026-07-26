import 'dart:io';

void architectureTest(String description, void Function() body) {
  body();
  stdout.writeln('PASS: $description');
}

void expectArchitectureEquals(Object? actual, Object? expected) {
  if (!_deepEquals(actual, expected)) {
    throw StateError('Expected:\n$expected\nActual:\n$actual');
  }
}

bool _deepEquals(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    return left.length == right.length &&
        Iterable<int>.generate(
          left.length,
        ).every((index) => _deepEquals(left[index], right[index]));
  }
  return left == right;
}
