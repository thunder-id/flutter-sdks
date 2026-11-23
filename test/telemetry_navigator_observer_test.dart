// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry_navigator_observer.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';

class _Client extends ThunderIDClient {
  final List<String> pages = [];

  @override
  void trackPageView(String pattern) => pages.add(pattern);
}

MaterialPageRoute<void> _page(String name) =>
    MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: (_) => Text(name));

void main() {
  testWidgets('reports the page a removal reveals, and not a replacement below the current page', (tester) async {
    final client = _Client();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [TelemetryNavigatorObserver(client)],
        onGenerateRoute: (settings) => _page(settings.name ?? '/'),
      ),
    );
    final a = _page('/a');
    final b = _page('/b');
    unawaited(navigator.currentState!.push(a));
    await tester.pumpAndSettle();
    unawaited(navigator.currentState!.push(b));
    await tester.pumpAndSettle();

    final c = _page('/c');
    navigator.currentState!.replace(oldRoute: a, newRoute: c);
    await tester.pumpAndSettle();
    // `/b` is still the current page.
    expect(client.pages, ['/', '/a', '/b']);

    navigator.currentState!.removeRoute(b);
    await tester.pumpAndSettle();
    expect(client.pages, ['/', '/a', '/b', '/c']);
  });
}
