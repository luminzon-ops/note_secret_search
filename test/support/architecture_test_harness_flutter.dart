import 'package:flutter_test/flutter_test.dart';

void architectureTest(String description, void Function() body) {
  test(description, body);
}

void expectArchitectureEquals(Object? actual, Object? expected) {
  expect(actual, equals(expected));
}
