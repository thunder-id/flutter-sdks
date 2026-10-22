// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../management/management_transport.dart';
import '../management/permissions.dart';

/// The permissions the signed-in user's access token carries, and a check against them: the
/// counterpart of the React SDK's `useGrantedPermissions`.
///
/// Reads the token once on creation (and on [reload]). A failure to read it leaves no
/// permissions rather than an error. The result only decides what to show; the server still
/// decides every request. Dispose it when done.
class GrantedPermissionsNotifier extends ChangeNotifier {
  final AccessTokenProvider _accessTokenProvider;
  List<String>? _granted;
  bool _disposed = false;

  /// Pass `signedIn: false` when there is no session; the notifier then grants nothing and does
  /// not read a token.
  GrantedPermissionsNotifier(this._accessTokenProvider, {bool signedIn = true}) {
    if (signedIn) {
      unawaited(reload());
    } else {
      _granted = const [];
    }
  }

  /// The granted permissions; empty while loading.
  List<String> get permissions => _granted ?? const [];

  bool get isLoading => _granted == null;

  /// Whether the token covers [required], with the server's hierarchy (see [hasPermission]).
  bool can(String required) => hasPermission(permissions, required);

  Future<void> reload() async {
    List<String> granted;
    try {
      granted = getTokenPermissions(await _accessTokenProvider());
    } catch (_) {
      granted = const [];
    }
    if (_disposed) return;
    _granted = granted;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
