part of 'model_management_page_test.dart';

Future<void> scrollUntilFound(
  WidgetTester tester,
  Finder finder, {
  double delta = 320,
  int maxScrolls = 30,
}) async {
  await tester.scrollUntilVisible(finder, delta, maxScrolls: maxScrolls);
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
}

Finder chipWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Chip &&
        widget.label is Text &&
        (widget.label as Text).data == label,
    description: 'Chip with label $label',
  );
}
