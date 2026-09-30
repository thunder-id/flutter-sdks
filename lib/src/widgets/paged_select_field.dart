// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../i18n/thunderid_i18n.dart';
import '../models/paged_select.dart';
import 'thunderid_provider.dart';

/// A single-choice picker whose options load a page at a time from [fetchOptions]. The chosen
/// option's value is written to [controller], the same `TextEditingController` `FlowForm` reads
/// every other field's value from at submit time.
///
/// A loader that returns raw `items` needs a [mapping]; without one it must return ready-made
/// `options`. There is no built-in data source: this platform has no user-directory bridge yet.
class PagedSelectField<T> extends StatefulWidget {
  final String fieldRef;
  final TextEditingController controller;
  final String label;
  final FetchPagedOptions<T> fetchOptions;
  final PagedSelectOptionMapping<T>? mapping;
  final int pageSize;
  final String? filter;

  const PagedSelectField({
    super.key,
    required this.fieldRef,
    required this.controller,
    required this.label,
    required this.fetchOptions,
    this.mapping,
    this.pageSize = 30,
    this.filter,
  });

  @override
  State<PagedSelectField<T>> createState() => _PagedSelectFieldState<T>();
}

class _PagedSelectFieldState<T> extends State<PagedSelectField<T>> {
  PagedSelectOption? _selected;

  Future<void> _open(BuildContext context, ThunderIDI18n i18n) async {
    final selected = await Navigator.of(context).push<PagedSelectOption>(
      PageRouteBuilder<PagedSelectOption>(
        opaque: true,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, animation, secondaryAnimation) => _PagedSelectListPage<T>(
          fetchOptions: widget.fetchOptions,
          mapping: widget.mapping,
          pageSize: widget.pageSize,
          filter: widget.filter,
          i18n: i18n,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    widget.controller.text = selected.value;
    setState(() => _selected = selected);
  }

  /// The label for the controller's current value: the chosen option's, else the raw value (a
  /// prefilled or externally set value has no known label), else `null` when empty.
  String? _labelFor(String value) {
    if (value.isEmpty) return null;
    final selected = _selected;
    return selected != null && selected.value == value ? selected.label : value;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ThunderIDProvider.of(context).i18n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // See the note on FlowForm's own fields: Semantics.identifier is what an external,
      // black-box test driver can target (maps to resource-id/accessibilityIdentifier), so it
      // carries the field identifier alongside the widget Key used by in-process widget tests.
      child: Semantics(
        identifier: 'thunderid-field-${widget.fieldRef}',
        child: InkWell(
          key: Key('thunderid-field-${widget.fieldRef}'),
          onTap: () => _open(context, i18n),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder(),
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final label = _labelFor(value.text);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        label ?? i18n.resolve('pagedSelect.placeholder'),
                        style: label == null ? TextStyle(color: Theme.of(context).hintColor) : null,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen picker page pushed by [_PagedSelectFieldState._open]. Owns its own paging state,
/// the same `StatefulWidget`/`setState` shape `ChangeCredential`'s edit page uses for a page
/// reached via [Navigator.push] rather than as a descendant of the field that opened it.
class _PagedSelectListPage<T> extends StatefulWidget {
  final FetchPagedOptions<T> fetchOptions;
  final PagedSelectOptionMapping<T>? mapping;
  final int pageSize;
  final String? filter;
  final ThunderIDI18n i18n;

  const _PagedSelectListPage({
    required this.fetchOptions,
    required this.mapping,
    required this.pageSize,
    required this.filter,
    required this.i18n,
  });

  @override
  State<_PagedSelectListPage<T>> createState() => _PagedSelectListPageState<T>();
}

class _PagedSelectListPageState<T> extends State<_PagedSelectListPage<T>> {
  final _scrollController = ScrollController();

  List<PagedSelectOption> _options = const [];
  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int? _nextOffset = 0;
  PagedSelectFailure? _failure;
  int _failedOffset = 0;

  // Guards a page result that completes after the page has been popped.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_nextOffset == null || _isLoading || _isLoadingMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadPage(_nextOffset!);
    }
  }

  Future<void> _loadPage(int offset) async {
    final isFirstPage = offset == 0;
    setState(() {
      if (isFirstPage) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
      _failure = null;
    });

    try {
      final page = await widget.fetchOptions(
        PagedSelectRequest(widget.pageSize, offset, filter: widget.filter),
      );
      if (_disposed) return;
      final mapping = widget.mapping;
      final incoming = page.options ??
          (mapping == null
              ? const <PagedSelectOption>[]
              : toPagedSelectOptions(page.items ?? const [], mapping));
      setState(() {
        _options = dedupePagedSelectOptions(isFirstPage ? const [] : _options, incoming);
        _nextOffset = isAdvancingPageOffset(offset, page.nextOffset) ? page.nextOffset : null;
        _hasLoaded = true;
      });
    } catch (e) {
      if (_disposed) return;
      _failedOffset = offset;
      setState(() => _failure = mapPagedSelectError(e));
    } finally {
      if (!_disposed) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = widget.i18n;
    return Scaffold(
      appBar: AppBar(leading: const CloseButton()),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: _options.length + 1,
        itemBuilder: (context, index) {
          if (index < _options.length) {
            final option = _options[index];
            return ListTile(
              key: Key('thunderid-option-${option.value}'),
              enabled: !option.disabled,
              title: Text(option.label),
              onTap: option.disabled ? null : () => Navigator.of(context).pop(option),
            );
          }
          return _Footer(
            i18n: i18n,
            isLoading: _isLoading,
            isLoadingMore: _isLoadingMore,
            hasLoaded: _hasLoaded,
            hasMore: _nextOffset != null,
            isEmpty: _options.isEmpty,
            failure: _failure,
            onRetry: () => _loadPage(_failedOffset),
            onLoadMore: () => _loadPage(_nextOffset!),
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final ThunderIDI18n i18n;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasLoaded;
  final bool hasMore;
  final bool isEmpty;
  final PagedSelectFailure? failure;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  const _Footer({
    required this.i18n,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasLoaded,
    required this.hasMore,
    required this.isEmpty,
    required this.failure,
    required this.onRetry,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading || isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(i18n.resolve(isLoading ? 'pagedSelect.loading' : 'pagedSelect.loadingMore')),
          ],
        ),
      );
    }
    final failure = this.failure;
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failure.message ?? i18n.resolve('pagedSelect.loadError')),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(i18n.resolve('pagedSelect.retry'))),
          ],
        ),
      );
    }
    // Paging depends on the server having more pages, not on how many options survived mapping,
    // so an empty mapped page or a page too short to scroll still offers the next one.
    if (hasLoaded && hasMore) {
      return TextButton(onPressed: onLoadMore, child: Text(i18n.resolve('pagedSelect.loadMore')));
    }
    if (hasLoaded && isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(i18n.resolve('pagedSelect.empty')),
      );
    }
    return const SizedBox.shrink();
  }
}
