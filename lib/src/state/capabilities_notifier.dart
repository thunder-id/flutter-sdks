// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/management/capabilities.dart';
import '../models/user.dart';

/// The signed-in user's management capabilities, shared by every widget under one
/// `ThunderIDProvider` (spec "Management capabilities"). Reach it through
/// `ThunderIDProvider.of(context).capabilities`; the provider owns and disposes it.
///
/// Capabilities decide what is offered, not what is allowed: they are not an authorization
/// decision. The server authorizes every management request, and the SDK never skips or blocks
/// one because of them.
///
/// Nothing is read until [load]. Then at most one read is current at a time: a read started for
/// an older user or token is discarded when it finishes. The answer is kept until the user's
/// `sub`, their `ouId` claim, or their granted permissions change, and read again then. Signing
/// out clears it.
class CapabilitiesNotifier extends ChangeNotifier {
  final Future<Capabilities> Function() _read;
  final Future<List<String>> Function() _grantedPermissions;

  User? _user;
  bool _used = false;
  bool _started = false;
  int _generation = 0;
  String? _readKey;
  bool _disposed = false;

  Capabilities? _capabilities;
  Object? _error;
  bool _isLoading = false;

  /// [read] reads the capabilities, normally `management.getCapabilities()`.
  /// [grantedPermissions] returns the permissions the access token carries; a failure counts as
  /// none.
  CapabilitiesNotifier({
    required Future<Capabilities> Function() read,
    required Future<List<String>> Function() grantedPermissions,
    User? user,
  })  : _read = read,
        _grantedPermissions = grantedPermissions,
        _user = user;

  /// What the server reported, or `null` while loading, after a failure, or before [load].
  Capabilities? get capabilities => _capabilities;

  bool get isLoading => _isLoading;

  /// Why the last read failed, kept apart from a denial: [can] answers false, and [retry] reads
  /// again.
  Object? get error => _error;

  /// Whether the user may perform [action] (`view` when omitted) on [resource]. False while
  /// loading, after a failed read, and for anything the server did not report.
  bool can(String resource, [String action = 'view']) => _capabilities?.can(resource, action) ?? false;

  /// What a management component may offer for one record; see [RecordAccess.from].
  RecordAccess recordAccess(String resource, {bool? isReadOnly, bool? isOwnedByOU}) =>
      RecordAccess.from(resource, isReadOnly: isReadOnly, isOwnedByOU: isOwnedByOU, can: can);

  /// Starts the first read, if there is a signed-in user and none has started. Safe to call on
  /// every build: it never notifies synchronously.
  void load() {
    _used = true;
    if (_user != null && !_started) _fetch(notify: false);
  }

  /// Reads again, e.g. after a failure. Does nothing while a read runs or when signed out.
  void retry() {
    if (_user != null && !_isLoading) _fetch();
  }

  /// Tells the notifier who is signed in. Called by `ThunderIDProvider` whenever its user
  /// changes; `null` means signed out and clears everything.
  void setUser(User? user) {
    _user = user;
    if (user == null) {
      _generation++;
      _readKey = null;
      _started = false;
      if (_capabilities != null || _error != null || _isLoading) {
        _set(null, null, false);
      }
      return;
    }
    if (!_used) return;
    if (!_started) {
      _fetch();
      return;
    }
    unawaited(_refresh());
  }

  Future<String> _keyFor(User user) async {
    List<String> permissions;
    try {
      permissions = [...await _grantedPermissions()]..sort();
    } catch (_) {
      permissions = const [];
    }
    return jsonEncode([user.claims['sub'], user.claims['ouId'], permissions]);
  }

  Future<void> _refresh() async {
    final current = _generation;
    final user = _user;
    if (user == null) return;
    final key = await _keyFor(user);
    if (current != _generation || _user == null || (key == _readKey && _error == null)) return;
    _fetch(key: key);
  }

  void _fetch({String? key, bool notify = true}) {
    final current = ++_generation;
    final user = _user!;
    _started = true;
    _readKey = key;
    _capabilities = null;
    _error = null;
    _isLoading = true;
    if (notify) notifyListeners();
    unawaited(() async {
      try {
        final readKey = key ?? await _keyFor(user);
        if (current == _generation) _readKey = readKey;
        final capabilities = await _read();
        if (current == _generation) _set(capabilities, null, false);
      } catch (error) {
        if (current == _generation) _set(null, error, false);
      }
    }());
  }

  void _set(Capabilities? capabilities, Object? error, bool isLoading) {
    if (_disposed) return;
    _capabilities = capabilities;
    _error = error;
    _isLoading = isLoading;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
