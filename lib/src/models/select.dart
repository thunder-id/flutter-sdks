// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// A selectable option: [label] is shown, [value] is submitted.
class SelectOption {
  final String label;
  final String value;
  final bool disabled;

  const SelectOption(this.label, this.value, {this.disabled = false});

  @override
  bool operator ==(Object other) =>
      other is SelectOption &&
      other.label == label &&
      other.value == value &&
      other.disabled == disabled;

  @override
  int get hashCode => Object.hash(label, value, disabled);
}

/// One page request sent to a [FetchSelectPage] loader.
class SelectPageRequest {
  final int limit;
  final int offset;
  final String? filter;

  const SelectPageRequest(this.limit, this.offset, {this.filter});
}

/// One page returned by a loader. Return ready-made [options], or raw [items] for the field
/// to convert with its mapping. [nextOffset] is `null` on the last page, otherwise it must be
/// greater than the request's `offset`.
class SelectPage<T> {
  final List<T>? items;
  final List<SelectOption>? options;
  final int? nextOffset;
  final int? totalResults;

  const SelectPage({this.items, this.options, this.nextOffset, this.totalResults});
}

/// Loads one page of options for a request. Generic over the raw item type a specialised
/// picker (users, emails, ...) fetches; [SelectPageRequest]/[SelectPage] stay the same either way.
typedef FetchSelectPage<T> = Future<SelectPage<T>> Function(SelectPageRequest request);

/// Chooses which field of each raw item is the label and which is the value, for a field that
/// does not want a type's built-in default conversion.
class SelectOptionMapping<T> {
  final String? Function(T item) label;
  final String? Function(T item) value;

  const SelectOptionMapping({required this.label, required this.value});
}

/// Limits and values shared by the select fields that list a resource a page at a time.
abstract final class SelectConstants {
  /// How many options a field asks for at a time when it is not told otherwise.
  static const int defaultPageSize = 30;

  /// The largest page the management API serves. The flow list clamps a larger request and the
  /// user type list rejects it, so loaders cap their request at this size.
  static const int maxPageSize = 100;

  /// Batches in a row that add nothing new before the loading helper stops continuing by itself
  /// and waits for the next request.
  static const int maxEmptyContinuations = 3;
}

/// The page size a field asks for: the default when none is given, otherwise the given size
/// clamped to at least 1 and at most what the management API serves.
int resolvePageSize([int pageSize = SelectConstants.defaultPageSize]) =>
    pageSize.clamp(1, SelectConstants.maxPageSize);

/// Whether a loader's reported next offset is safe to follow: an integer past the request
/// offset. Anything else would loop or go backwards, so the list ends instead.
bool isAdvancingPageOffset(int requestOffset, int? nextOffset) =>
    nextOffset != null && nextOffset > requestOffset;

/// Offset of the next page: the request offset plus the number of items the backend returned,
/// or `null` once the list is exhausted.
int? computeNextPageOffset(int requestOffset, int count, int? totalResults) {
  if (requestOffset < 0 || count <= 0) return null;
  final next = requestOffset + count;
  if (totalResults != null && next >= totalResults) return null;
  return next;
}

/// Converts one raw item into an option using [mapping]: the mapped value is submitted and the
/// mapped label is shown, falling back to the value. `null` when the mapping has no value for
/// the item.
SelectOption? toSelectOption<T>(T item, SelectOptionMapping<T> mapping) {
  final value = mapping.value(item);
  if (value == null) return null;
  return SelectOption(mapping.label(item) ?? value, value);
}

/// Converts a page of raw items into options, dropping any item the mapping has no value for.
List<SelectOption> toSelectOptions<T>(List<T> items, SelectOptionMapping<T> mapping) =>
    items.map((item) => toSelectOption(item, mapping)).whereType<SelectOption>().toList();

/// Appends [incoming] to [existing], keeping each value at its first position and taking the
/// newest data when a value repeats (offset paging can return the same item on two pages).
List<SelectOption> dedupeSelectOptions(List<SelectOption> existing, List<SelectOption> incoming) {
  final byValue = <String, SelectOption>{};
  for (final option in [...existing, ...incoming]) {
    byValue[option.value] = option;
  }
  return byValue.values.toList();
}

/// Builds a loader page from one page of a list response. The next offset comes from the
/// backend's own [count], so items dropped by a mapping never shift the paging.
SelectPage<T> toListSelectPage<T>({
  required List<SelectOption> options,
  required int count,
  required int totalResults,
  required int requestOffset,
}) =>
    SelectPage<T>(
      options: options,
      nextOffset: computeNextPageOffset(requestOffset, count, totalResults),
      totalResults: totalResults,
    );
