// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Identifies a cached management read, e.g. `['users', {'limit': 20, 'offset': 0}]`.
typedef ResourceQueryKey = List<Object?>;

/// Tells live [ResourceQuery]s to reload after a mutation changed what they show.
///
/// A query subscribes with its full key; [invalidate] takes a prefix and reloads every query
/// whose key starts with it, so `['users']` reloads every page of users.
class ResourceInvalidator {
  final List<_Subscription> _subscriptions = [];

  /// Registers [listener] for [queryKey]; call the returned function to unsubscribe.
  VoidCallback subscribe(ResourceQueryKey queryKey, VoidCallback listener) {
    final subscription = _Subscription(queryKey, listener);
    _subscriptions.add(subscription);
    return () => _subscriptions.remove(subscription);
  }

  /// Reloads every subscribed query whose key starts with [partialKey].
  void invalidate(ResourceQueryKey partialKey) {
    for (final subscription in List<_Subscription>.of(_subscriptions)) {
      if (_matches(subscription.queryKey, partialKey)) subscription.listener();
    }
  }

  static bool _matches(ResourceQueryKey queryKey, ResourceQueryKey partialKey) {
    if (partialKey.length > queryKey.length) return false;
    for (var i = 0; i < partialKey.length; i++) {
      if (_encode(partialKey[i]) != _encode(queryKey[i])) return false;
    }
    return true;
  }

  static String _encode(Object? part) => jsonEncode(part, toEncodable: (value) => value.toString());
}

class _Subscription {
  final ResourceQueryKey queryKey;
  final VoidCallback listener;

  _Subscription(this.queryKey, this.listener);
}

/// A management read and its state: the counterpart of the React SDK's `useResourceQuery`.
///
/// Loads on creation (unless [enabled] is false), reloads when a mutation invalidates [key], and
/// notifies listeners on every change. Only the latest load may write state, so a slow earlier
/// response cannot overwrite a newer one. Errors are reported through [error], never thrown or
/// shown. Dispose it when done.
class ResourceQuery<T> extends ChangeNotifier {
  final ResourceQueryKey key;
  final Future<T> Function() _fetch;
  VoidCallback? _unsubscribe;
  T? _data;
  Object? _error;
  bool _isLoading;
  int _latestRequest = 0;
  bool _disposed = false;

  ResourceQuery(
    this._fetch, {
    required this.key,
    ResourceInvalidator? invalidator,
    bool enabled = true,
  }) : _isLoading = enabled {
    if (!enabled) return;
    _unsubscribe = invalidator?.subscribe(key, () => unawaited(refetch()));
    unawaited(refetch());
  }

  T? get data => _data;
  Object? get error => _error;
  bool get isLoading => _isLoading;

  /// Loads again. Resolves with the result, or `null` when the load failed (see [error]).
  Future<T?> refetch() async {
    if (_disposed) return null;
    final requestId = ++_latestRequest;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _fetch();
      if (_isCurrent(requestId)) {
        _data = result;
        _error = null;
      }
      return result;
    } catch (error) {
      if (_isCurrent(requestId)) _error = error;
      return null;
    } finally {
      if (_isCurrent(requestId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int requestId) => !_disposed && requestId == _latestRequest;

  @override
  void dispose() {
    _disposed = true;
    _unsubscribe?.call();
    super.dispose();
  }
}

/// A management write and its state: the counterpart of the React SDK's
/// `useResourceMutation`. On success it invalidates the queries the write affects.
class ResourceMutation<V, R> extends ChangeNotifier {
  final Future<R> Function(V variables) _mutate;
  final List<ResourceQueryKey> Function(V variables) _invalidates;
  final ResourceInvalidator? _invalidator;
  final void Function(R data, V variables)? onSuccess;
  final void Function(Object error, V variables)? onError;
  R? _data;
  Object? _error;
  bool _isLoading = false;
  bool _disposed = false;

  ResourceMutation(
    this._mutate, {
    List<ResourceQueryKey> Function(V variables)? invalidates,
    ResourceInvalidator? invalidator,
    this.onSuccess,
    this.onError,
  })  : _invalidates = invalidates ?? ((_) => const []),
        _invalidator = invalidator;

  R? get data => _data;
  Object? get error => _error;
  bool get isLoading => _isLoading;

  /// Runs the write and rethrows a failure, after recording it in [error].
  Future<R> mutateAsync(V variables) async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final result = await _mutate(variables);
      _data = result;
      for (final key in _invalidates(variables)) {
        _invalidator?.invalidate(key);
      }
      onSuccess?.call(result, variables);
      return result;
    } catch (error) {
      _error = error;
      onError?.call(error, variables);
      rethrow;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Runs the write; a failure is recorded in [error] and resolves to `null` instead of throwing.
  Future<R?> mutate(V variables) async {
    try {
      return await mutateAsync(variables);
    } catch (_) {
      return null;
    }
  }

  /// Clears [data] and [error].
  void reset() {
    _data = null;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
