// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../models/flow_models.dart';

/// Tracks when an embedded flow execution expires, and starts the flow again once it has and the app is resumed.
/// A flow that expires while the app is in the background starts again when the user comes back to it.
class FlowExpiry {
  FlowExpiry({required this.restart, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Starts the flow again.
  final VoidCallback restart;

  final DateTime Function() _now;
  DateTime? _deadline;
  bool _isExpired = false;
  bool _isActive = true;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  /// Follows the app's lifecycle, so the flow starts again only while the app is resumed.
  void listen() {
    _lifecycle ??= AppLifecycleListener(onStateChange: (state) => setActive(state == AppLifecycleState.resumed));
  }

  /// Tracks the expiry of a step, counted from when its response arrived. A flow that ended, or a step without an
  /// expiry, stops the tracking.
  void track(EmbeddedFlowResponse response) {
    stop();
    final expiresIn = response.expiresIn;
    if (expiresIn == null || response.flowStatus != FlowStatus.promptOnly) return;
    final duration = Duration(seconds: expiresIn < 0 ? 0 : expiresIn);
    _deadline = _now().add(duration);
    _timer = Timer(duration, expire);
  }

  /// Marks the flow as expired, e.g. when the server refused a step as expired.
  void expire() {
    stop();
    _isExpired = true;
    _restartIfActive();
  }

  /// Tells whether the app is resumed. Coming back checks the deadline again, since the timer may not have run.
  void setActive(bool active) {
    _isActive = active;
    final deadline = _deadline;
    if (deadline != null && !_now().isBefore(deadline)) {
      expire();
    } else {
      _restartIfActive();
    }
  }

  /// Stops tracking the current flow.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
    _isExpired = false;
  }

  /// Stops tracking, and stops following the app's lifecycle.
  void dispose() {
    stop();
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _restartIfActive() {
    if (!_isExpired || !_isActive) return;
    _isExpired = false;
    restart();
  }
}
