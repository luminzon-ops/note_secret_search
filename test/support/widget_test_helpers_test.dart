import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_helpers.dart';

void main() {
  testWidgets('pumpRouteAtViewport applies logical size, DPR, and text scale', (
    tester,
  ) async {
    late Size logicalSize;
    late double devicePixelRatio;
    late double scaledFontSize;

    await pumpRouteAtViewport(
      tester,
      viewport: const Size(393, 852),
      devicePixelRatio: 2,
      textScaler: TextScaler.linear(1.3),
      route: MaterialApp(
        home: Builder(
          builder: (context) {
            logicalSize = MediaQuery.sizeOf(context);
            devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            scaledFontSize = MediaQuery.textScalerOf(context).scale(10);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(logicalSize, const Size(393, 852));
    expect(devicePixelRatio, 2);
    expect(scaledFontSize, closeTo(13, 0.001));
  });

  testWidgets('pumpUntilFound waits for a finder predicate with a hard bound', (
    tester,
  ) async {
    await pumpRouteAtViewport(
      tester,
      viewport: const Size(360, 640),
      route: MaterialApp(
        home: FutureBuilder<void>(
          future: Future<void>.delayed(const Duration(milliseconds: 32)),
          builder: (context, snapshot) {
            return snapshot.connectionState == ConnectionState.done
                ? const Text('ready', textDirection: TextDirection.ltr)
                : const SizedBox.shrink();
          },
        ),
      ),
    );

    await pumpUntilFound(tester, find.text('ready'), maxPumps: 3);

    Object? failure;
    try {
      await pumpUntilFound(tester, find.text('missing'), maxPumps: 2);
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<TestFailure>());
  });

  testWidgets(
    'revealAndTap scrolls by viewport fraction to a semantic target',
    (tester) async {
      var tapped = false;
      const scrollRegionKey = ValueKey('scroll-region');
      const targetKey = ValueKey('item-49');

      await pumpRouteAtViewport(
        tester,
        viewport: const Size(360, 640),
        route: MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              key: scrollRegionKey,
              itemCount: 50,
              itemExtent: 56,
              itemBuilder: (context, index) {
                return ListTile(
                  key: ValueKey('item-$index'),
                  title: Text('Item $index'),
                  onTap: index == 49 ? () => tapped = true : null,
                );
              },
            ),
          ),
        ),
      );

      await revealAndTap(
        tester,
        find.byKey(targetKey),
        scrollable: find.byKey(scrollRegionKey),
        maxScrolls: 12,
      );

      expect(tapped, isTrue);
    },
  );

  testWidgets('pumpUntilProviderSettled waits for a terminal AsyncValue', (
    tester,
  ) async {
    final provider = FutureProvider<int>((ref) async {
      await Future<void>.delayed(const Duration(milliseconds: 32));
      return 7;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpRouteAtViewport(
      tester,
      viewport: const Size(360, 640),
      route: const SizedBox.shrink(),
    );

    final settled = await pumpUntilProviderSettled(
      tester,
      container,
      provider,
      maxPumps: 3,
    );

    expect(settled, const AsyncData<int>(7));
  });
}
