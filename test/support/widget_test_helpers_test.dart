import 'dart:async';

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
      textScaler: const TextScaler.linear(1.3),
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
    final ready = ValueNotifier<bool>(false);
    addTearDown(ready.dispose);

    await pumpRouteAtViewport(
      tester,
      viewport: const Size(360, 640),
      route: ValueListenableBuilder<bool>(
        valueListenable: ready,
        builder: (context, isReady, child) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: isReady ? const Text('ready') : const SizedBox.shrink(),
          );
        },
      ),
    );
    Future<void>.microtask(() {
      ready.value = true;
    });

    await pumpUntilFound(tester, find.text('ready'), maxPumps: 3);

    Object? failure;
    try {
      await pumpUntilFound(tester, find.text('missing'), maxPumps: 2);
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<TestFailure>());
  });

  testWidgets('pumpUntilFound can require a hit-testable match', (
    tester,
  ) async {
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);

    await pumpRouteAtViewport(
      tester,
      viewport: const Size(360, 640),
      route: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, isVisible, child) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Offstage(offstage: !isVisible, child: const Text('target')),
          );
        },
      ),
    );
    final target = find.text('target', skipOffstage: false);
    expect(target, findsOneWidget);
    Future<void>.microtask(() {
      visible.value = true;
    });

    await pumpUntilFound(tester, target, hitTestable: true, maxPumps: 3);
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
    final completer = Completer<int>();
    final provider = FutureProvider<int>((ref) async {
      return completer.future;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpRouteAtViewport(
      tester,
      viewport: const Size(360, 640),
      route: const SizedBox.shrink(),
    );

    Future<void>.microtask(() {
      completer.complete(7);
    });

    final settled = await pumpUntilProviderSettled(
      tester,
      container,
      provider,
      maxPumps: 3,
    );

    expect(settled, const AsyncData<int>(7));
  });

  testWidgets('pumpUntilProviderSettled honors custom settled predicates', (
    tester,
  ) async {
    final completer = Completer<int>();
    final provider = FutureProvider<int>((ref) async {
      return completer.future;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpRouteAtViewport(
      tester,
      viewport: const Size(360, 640),
      route: const SizedBox.shrink(),
    );
    Future<void>.microtask(() {
      completer.complete(7);
    });

    final settled = await pumpUntilProviderSettled(
      tester,
      container,
      provider,
      where: (value) => value.hasValue && value.requireValue.isOdd,
      maxPumps: 3,
    );

    expect(settled.requireValue, 7);
  });
}
