part of 'model_management_page_test.dart';

Future<void> scrollUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxScrolls = 30,
}) async {
  await reveal(tester, finder, maxScrolls: maxScrolls);
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
