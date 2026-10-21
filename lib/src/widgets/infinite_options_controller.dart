// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/select.dart';
import '../models/select_loading.dart';

/// Loads the next batch of options. Returning `null` counts as an empty batch.
typedef SelectOptionsLoader<C> = Future<SelectOptionsBatch<C>?> Function(
  SelectOptionsLoadContext<C> context,
);

/// Keeps the option list of a [SelectField] that loads more options when the user asks for them.
///
/// It owns the cursor, appends each batch without duplicates, and stops at the end of the data.
/// Nothing is drawn, so it works with any list widget. A failed load never changes the options:
/// it sets [error], calls `onError`, and leaves the cursor where it was, so asking again repeats
/// the same request.
///
/// ```dart
/// final options = InfiniteOptionsController<int>(
///   load: (context) async {
///     final page = await fetchUsers(context.cursor ?? 0);
///     return SelectOptionsBatch.page(page.options, nextCursor: page.nextOffset);
///   },
/// )..loadMore();
///
/// ListenableBuilder(
///   listenable: options,
///   builder: (context, _) => SelectField(
///     name: 'owner',
///     value: owner,
///     onChanged: (value) => setState(() => owner = value),
///     options: options.options,
///     label: 'Owner',
///     loading: options.loading,
///     onLoadMore: options.hasMore ? options.loadMore : null,
///   ),
/// );
/// ```
///
/// Dispose it when the owner goes away; a request still in flight is then ignored.
class InfiniteOptionsController<C> extends ChangeNotifier {
  final List<SelectOption> _initialOptions;
  SelectOptionsLoader<C> _load;
  void Function(Object error)? _onError;

  List<SelectOption> _options;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  C? _cursor;
  bool _finished = false;
  bool _requested = false;
  int _generation = 0;
  bool _disposed = false;

  /// [initialOptions] are shown before anything is loaded, and again after [reset]. [load] loads
  /// the next batch. [onError] is called with the error of every failed load.
  InfiniteOptionsController({
    List<SelectOption> initialOptions = const [],
    required SelectOptionsLoader<C> load,
    void Function(Object error)? onError,
  })  : _initialOptions = List.unmodifiable(initialOptions),
        _options = List.unmodifiable(initialOptions),
        _load = load,
        _onError = onError;

  /// The options loaded so far.
  List<SelectOption> get options => _options;

  /// Whether a batch is being fetched.
  bool get loading => _loading;

  /// Whether more batches may be available.
  bool get hasMore => _hasMore;

  /// The error of the last load, cleared by the next successful one.
  Object? get error => _error;

  /// Replaces the loader and the error callback. A widget calls this on each build so a request
  /// made later uses the current values; it does not restart the list.
  void update({required SelectOptionsLoader<C> load, void Function(Object error)? onError}) {
    _load = load;
    _onError = onError;
  }

  /// Loads the next batch. Does nothing while a load is running or once the data has ended.
  void loadMore() {
    if (_disposed || _loading || _finished) return;
    _requested = true;
    _startLoad();
  }

  /// Goes back to the initial options and the first batch. A running load is dropped, and the
  /// first batch loads again right away if loading had already been requested.
  void reset() {
    if (_disposed) return;
    final shouldReload = _requested;
    _generation += 1;
    _cursor = null;
    _finished = false;
    _loading = false;
    _options = _initialOptions;
    _hasMore = true;
    _error = null;
    if (shouldReload) {
      _startLoad();
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _startLoad() {
    final generation = _generation;
    _loading = true;
    notifyListeners();
    unawaited(_run(generation));
  }

  Future<void> _run(int generation) async {
    try {
      await loadUntilOptionsGrow<SelectOptionsBatch<C>?>(
        loadBatch: () => _load(SelectOptionsLoadContext<C>(cursor: _cursor, options: _options)),
        applyBatch: _apply,
        isCurrent: () => _isCurrent(generation),
      );
    } catch (failure) {
      _fail(failure, generation);
    }
    _finish(generation);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  /// Adds a batch to the list. Returns `true` when it added nothing while more remain.
  bool _apply(SelectOptionsBatch<C>? batch) {
    final merged = mergeSelectOptionsBatch<C>(_cursor, _options, batch);
    if (merged.issue == SelectOptionsBatchIssue.cursorStuck) {
      debugPrint(
        '[InfiniteOptionsController] A load returned no new options and the same cursor; '
        'the list was treated as finished.',
      );
    }
    final addedNothing = merged.options.length == _options.length;
    _cursor = merged.cursor;
    _options = List.unmodifiable(merged.options);
    _finished = merged.finished;
    _hasMore = !merged.finished;
    _error = null;
    notifyListeners();
    return addedNothing && !merged.finished;
  }

  void _fail(Object failure, int generation) {
    if (!_isCurrent(generation)) return;
    _error = failure;
    notifyListeners();
    try {
      _onError?.call(failure);
    } catch (callbackError) {
      // A callback that throws must not break the list.
      debugPrint('[InfiniteOptionsController] The onError callback threw: $callbackError');
    }
  }

  void _finish(int generation) {
    if (!_isCurrent(generation)) return;
    _loading = false;
    notifyListeners();
  }
}
