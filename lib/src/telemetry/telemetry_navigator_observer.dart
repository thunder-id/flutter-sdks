// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../thunderid_client.dart';

/// Reports a screen view each time a page route becomes the current one, named from its route
/// pattern (spec "Telemetry"). Does nothing unless the client's telemetry is configured.
///
/// The pattern is the route's [RouteSettings.name] unless [routePattern] maps the route to one.
/// Give it a pattern such as `/applications/:id`, never a concrete path with an id in it: a named
/// route table already uses patterns, and with a router package [routePattern] can read the matched
/// route's path template. A route without a pattern, such as a dialog, is not reported.
///
/// ```dart
/// MaterialApp(navigatorObservers: [TelemetryNavigatorObserver(client)], ...)
/// ```
class TelemetryNavigatorObserver extends NavigatorObserver {
  final ThunderIDClient client;

  /// The route pattern of a route, or `null` to leave it out.
  final String? Function(Route<dynamic> route)? routePattern;

  /// The route on top of the navigator, as this observer last saw it.
  Route<dynamic>? _top;

  TelemetryNavigatorObserver(this.client, {this.routePattern});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _becameTop(route);

  /// A replacement is reported only when it replaces the current route; one below it is not shown.
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null && (_top == null || identical(oldRoute, _top))) _becameTop(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _revealed(route, previousRoute);

  /// Removing the current route reveals the one below it, as a pop does.
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _revealed(route, previousRoute);

  void _revealed(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_top != null && !identical(route, _top)) return;
    _top = previousRoute;
    if (previousRoute != null) _report(previousRoute);
  }

  void _becameTop(Route<dynamic> route) {
    _top = route;
    _report(route);
  }

  void _report(Route<dynamic> route) {
    if (route is! PageRoute) return;
    final pattern = routePattern != null ? routePattern!(route) : route.settings.name;
    if (pattern == null || pattern.isEmpty) return;
    client.trackPageView(pattern);
  }
}
