// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/select.dart';

/// What the list under the options says about its own state.
enum SelectListStatus {
  /// The first options are being fetched.
  loading,

  /// There are no options, nothing is loading and there is nothing more to load.
  empty,

  /// Nothing to say: options are listed, or a "Load more" row is available.
  none,
}

/// Which rows follow the options, decided from the state of the list.
class SelectListLayout {
  final SelectListStatus status;

  /// Whether the "Load more" row is listed. While loading it reads "Loading more…" and cannot be
  /// chosen.
  final bool showsLoadMore;

  const SelectListLayout._(this.status, this.showsLoadMore);

  factory SelectListLayout.of({
    required int optionCount,
    required bool loading,
    required bool canLoadMore,
  }) {
    final SelectListStatus status;
    if (loading && optionCount == 0) {
      status = SelectListStatus.loading;
    } else if (optionCount == 0 && !canLoadMore && !loading) {
      status = SelectListStatus.empty;
    } else {
      status = SelectListStatus.none;
    }
    // During the first load there is nothing to load more of; after a failed first load the row
    // stays, so choosing it repeats the request.
    return SelectListLayout._(status, canLoadMore && (optionCount > 0 || !loading));
  }
}

/// The option that labels [value]: the loaded option with that value, else the one last
/// [picked], else [selectedOption]. `null` when none of them has that value.
SelectOption? resolveSelectOption(
  String value,
  List<SelectOption> options, {
  SelectOption? picked,
  SelectOption? selectedOption,
}) {
  if (value.isEmpty) return null;
  for (final option in options) {
    if (option.value == value) return option;
  }
  if (picked != null && picked.value == value) return picked;
  if (selectedOption != null && selectedOption.value == value) return selectedOption;
  return null;
}
