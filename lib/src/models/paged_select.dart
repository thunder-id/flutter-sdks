// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'thunderid_error.dart';

/// A selectable option: [label] is shown, [value] is submitted.
class PagedSelectOption {
  final String label;
  final String value;
  final bool disabled;

  const PagedSelectOption(this.label, this.value, {this.disabled = false});

  @override
  bool operator ==(Object other) =>
      other is PagedSelectOption &&
      other.label == label &&
      other.value == value &&
      other.disabled == disabled;

  @override
  int get hashCode => Object.hash(label, value, disabled);
}

/// One page request sent to a [FetchPagedOptions] loader.
class PagedSelectRequest {
  final int limit;
  final int offset;
  final String? filter;

  const PagedSelectRequest(this.limit, this.offset, {this.filter});
}

/// One page returned by a loader. Return ready-made [options], or raw [items] for the picker
/// to convert with its mapping. [nextOffset] is `null` on the last page, otherwise it must be
/// greater than the request's `offset`.
class PagedSelectPage<T> {
  final List<T>? items;
  final List<PagedSelectOption>? options;
  final int? nextOffset;
  final int? totalResults;

  const PagedSelectPage({this.items, this.options, this.nextOffset, this.totalResults});
}

/// Loads one page of options for a request. Generic over the raw item type a specialised
/// picker (users, emails, ...) fetches — [PagedSelectRequest]/[PagedSelectPage] stay the same
/// either way.
typedef FetchPagedOptions<T> = Future<PagedSelectPage<T>> Function(PagedSelectRequest request);

/// Chooses which field of each raw item is the label and which is the value, for a picker
/// that does not want a type's built-in default conversion.
class PagedSelectOptionMapping<T> {
  final String? Function(T item) label;
  final String? Function(T item) value;

  const PagedSelectOptionMapping({required this.label, required this.value});
}

/// Whether a loader's reported next offset is safe to follow: `null` (exhausted) or an integer
/// past the request offset. Anything else would loop or go backwards.
bool isAdvancingPageOffset(int requestOffset, int? nextOffset) =>
    nextOffset != null && nextOffset > requestOffset;

/// Offset of the next page: the request offset plus the number of items the backend returned,
/// or `null` once the list is exhausted.
int? computeNextPageOffset(int requestOffset, int count, int? totalResults) {
  if (count <= 0) return null;
  final next = requestOffset + count;
  if (totalResults != null && next >= totalResults) return null;
  return next;
}

/// Converts one raw item into an option using [mapping]: the mapped value is submitted and the
/// mapped label is shown, falling back to the value. `null` when the mapping has no value for
/// the item.
PagedSelectOption? toPagedSelectOption<T>(T item, PagedSelectOptionMapping<T> mapping) {
  final value = mapping.value(item);
  if (value == null) return null;
  return PagedSelectOption(mapping.label(item) ?? value, value);
}

/// Converts a page of raw items into options, dropping any item the mapping has no value for.
List<PagedSelectOption> toPagedSelectOptions<T>(
  List<T> items,
  PagedSelectOptionMapping<T> mapping,
) =>
    items.map((item) => toPagedSelectOption(item, mapping)).whereType<PagedSelectOption>().toList();

/// Appends [incoming] to [existing], keeping each value at its first position and taking the
/// newest data when a value repeats (offset paging can return the same item on two pages).
List<PagedSelectOption> dedupePagedSelectOptions(
  List<PagedSelectOption> existing,
  List<PagedSelectOption> incoming,
) {
  final byValue = <String, PagedSelectOption>{};
  for (final option in [...existing, ...incoming]) {
    byValue[option.value] = option;
  }
  return byValue.values.toList();
}

/// Where a failed page load should get its display text from.
///
/// [message] is present only when the loader threw an [IAMException], and takes precedence
/// when it is. When it is absent, the caller falls back to a generic, translatable message
/// (`i18n.resolve('pagedSelect.loadError')`) — this type only records that a load failed, not
/// what to say about it, keeping this module free of i18n concerns the same way
/// `mapCredentialError` is.
class PagedSelectFailure {
  final String? message;

  const PagedSelectFailure(this.message);
}

/// Maps a `FetchPagedOptions` loader failure onto what a picker should show.
///
/// The loader is consumer-supplied — it is not guaranteed to throw an [IAMException] the way
/// a bridged client operation does — so only an [IAMException]'s message is trusted for direct
/// display; anything else (a bare exception, an upstream failure with an unreviewed message)
/// carries no message, and the caller shows the generic fallback instead.
PagedSelectFailure mapPagedSelectError(Object error) =>
    PagedSelectFailure(error is IAMException ? error.message : null);
