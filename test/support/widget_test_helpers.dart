import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpRouteAtViewport(
  WidgetTester tester, {
  required Widget route,
  required Size viewport,
  double devicePixelRatio = 1,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  if (viewport.width <= 0 || viewport.height <= 0) {
    throw ArgumentError.value(viewport, 'viewport', 'must be positive');
  }
  if (devicePixelRatio <= 0) {
    throw ArgumentError.value(
      devicePixelRatio,
      'devicePixelRatio',
      'must be positive',
    );
  }

  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    viewport.width * devicePixelRatio,
    viewport.height * devicePixelRatio,
  );
  tester.platformDispatcher.textScaleFactorTestValue = textScaler.scale(1);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(route);
  await tester.pump();
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder target, {
  bool hitTestable = false,
  int maxPumps = 60,
}) async {
  _validateBound(maxPumps, 'maxPumps');

  for (var pumpCount = 0; pumpCount <= maxPumps; pumpCount += 1) {
    final candidate = hitTestable ? target.hitTestable() : target;
    if (candidate.evaluate().isNotEmpty) {
      return;
    }
    if (pumpCount < maxPumps) {
      await _pumpOneFrame(tester);
    }
  }

  throw TestFailure('Finder did not match within $maxPumps pumps: $target');
}

Future<AsyncValue<T>> pumpUntilProviderSettled<T>(
  WidgetTester tester,
  ProviderContainer container,
  ProviderListenable<AsyncValue<T>> provider, {
  bool Function(AsyncValue<T> value)? where,
  int maxPumps = 60,
}) async {
  _validateBound(maxPumps, 'maxPumps');

  final subscription = container.listen<AsyncValue<T>>(
    provider,
    (_, __) {},
    fireImmediately: true,
  );
  try {
    for (var pumpCount = 0; pumpCount <= maxPumps; pumpCount += 1) {
      final value = subscription.read();
      final settled = where?.call(value) ?? !value.isLoading;
      if (settled) {
        return value;
      }
      if (pumpCount < maxPumps) {
        await _pumpOneFrame(tester);
      }
    }

    throw TestFailure(
      'Provider did not settle within $maxPumps pumps: '
      '${subscription.read()}',
    );
  } finally {
    subscription.close();
  }
}

Future<void> reveal(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  int maxScrolls = 24,
  double viewportFraction = 0.65,
}) async {
  _validateBound(maxScrolls, 'maxScrolls');
  if (viewportFraction <= 0 || viewportFraction > 1) {
    throw ArgumentError.value(
      viewportFraction,
      'viewportFraction',
      'must be greater than 0 and at most 1',
    );
  }

  Finder? resolvedScrollable;
  var scanningForward = true;

  for (var scrollCount = 0; scrollCount <= maxScrolls; scrollCount += 1) {
    final visibleTarget = target.hitTestable();
    final visibleCount = visibleTarget.evaluate().length;
    if (visibleCount == 1) {
      return;
    }
    if (visibleCount > 1) {
      throw TestFailure('Target must be unique when visible: $target');
    }

    final targetCount = target.evaluate().length;
    if (targetCount > 1) {
      throw TestFailure('Target must be unique: $target');
    }
    if (targetCount == 1) {
      await tester.ensureVisible(target);
      await tester.pump();
      if (target.hitTestable().evaluate().length == 1) {
        return;
      }
    }

    if (scrollCount == maxScrolls) {
      break;
    }

    resolvedScrollable ??= _resolveScrollable(scrollable);
    final state = tester.state<ScrollableState>(resolvedScrollable);
    final position = state.position;
    final canScanForward = position.extentAfter > 0.5;
    final canScanBackward = position.extentBefore > 0.5;

    if (scanningForward && !canScanForward) {
      scanningForward = false;
    }
    if (!scanningForward && !canScanBackward) {
      break;
    }

    final forward = scanningForward;
    final distance = position.viewportDimension * viewportFraction;
    await tester.drag(
      resolvedScrollable,
      _dragOffset(position.axisDirection, distance, forward: forward),
    );
    await tester.pump();
  }

  throw TestFailure(
    'Target was not revealed within $maxScrolls viewport-relative scrolls: '
    '$target',
  );
}

Future<void> revealAndTap(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  int maxScrolls = 24,
  double viewportFraction = 0.65,
}) async {
  await reveal(
    tester,
    target,
    scrollable: scrollable,
    maxScrolls: maxScrolls,
    viewportFraction: viewportFraction,
  );

  final visibleTarget = target.hitTestable();
  if (visibleTarget.evaluate().length != 1) {
    throw TestFailure('Target must resolve to one tappable widget: $target');
  }
  await tester.tap(visibleTarget);
  await tester.pump();
}

Finder _resolveScrollable(Finder? scope) {
  if (scope == null) {
    return _requireUniqueScrollable(find.byType(Scrollable).hitTestable());
  }

  final scopeMatches = scope.evaluate().toList(growable: false);
  if (scopeMatches.length != 1) {
    throw TestFailure(
      'Scrollable scope must match exactly one widget; '
      'matched ${scopeMatches.length}: $scope',
    );
  }
  if (scopeMatches.single.widget is Scrollable) {
    return _requireUniqueScrollable(scope.hitTestable());
  }

  final scopeElement = scopeMatches.single;
  final candidates = find
      .descendant(of: scope, matching: find.byType(Scrollable))
      .hitTestable()
      .evaluate()
      .toList(growable: false);
  if (candidates.isEmpty) {
    throw TestFailure('No hit-testable Scrollable found inside scope: $scope');
  }

  var nearestDistance = 1 << 30;
  final nearest = <Element>[];
  for (final candidate in candidates) {
    final distance = _ancestorDistance(candidate, scopeElement);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest
        ..clear()
        ..add(candidate);
    } else if (distance == nearestDistance) {
      nearest.add(candidate);
    }
  }
  if (nearest.length != 1) {
    throw TestFailure(
      'Expected one nearest Scrollable inside scope, matched '
      '${nearest.length}: $scope',
    );
  }

  final targetElement = nearest.single;
  return find.byElementPredicate(
    (element) => identical(element, targetElement),
    description: 'nearest Scrollable inside $scope',
  );
}

Finder _requireUniqueScrollable(Finder finder) {
  final count = finder.evaluate().length;
  if (count != 1) {
    throw TestFailure(
      'Expected one hit-testable Scrollable, matched $count. '
      'Pass a semantic scrollable scope when the route has nested scrolling.',
    );
  }
  return finder;
}

int _ancestorDistance(Element candidate, Element ancestor) {
  var distance = 0;
  var found = false;
  candidate.visitAncestorElements((element) {
    distance += 1;
    if (identical(element, ancestor)) {
      found = true;
      return false;
    }
    return true;
  });
  if (!found) {
    throw TestFailure('Scrollable candidate is outside its requested scope.');
  }
  return distance;
}

Offset _dragOffset(
  AxisDirection direction,
  double distance, {
  required bool forward,
}) {
  final signedDistance = forward ? distance : -distance;
  return switch (direction) {
    AxisDirection.down => Offset(0, -signedDistance),
    AxisDirection.up => Offset(0, signedDistance),
    AxisDirection.right => Offset(-signedDistance, 0),
    AxisDirection.left => Offset(signedDistance, 0),
  };
}

Future<void> _pumpOneFrame(WidgetTester tester) => tester.pump();

void _validateBound(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}
