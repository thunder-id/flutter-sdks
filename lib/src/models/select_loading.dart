// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'select.dart';

/// One batch of options from a loader. A [SelectOptionsBatch.list] ends the data when it is empty
/// or adds nothing new; a [SelectOptionsBatch.page] ends it when `nextCursor` is `null`.
sealed class SelectOptionsBatch<C> {
  const SelectOptionsBatch();

  const factory SelectOptionsBatch.list(List<SelectOption> options) = SelectOptionList<C>;

  const factory SelectOptionsBatch.page(List<SelectOption> options, {C? nextCursor}) =
      SelectOptionPage<C>;
}

/// A batch that is a plain list of options, with no cursor.
final class SelectOptionList<C> extends SelectOptionsBatch<C> {
  final List<SelectOption> options;

  const SelectOptionList(this.options);
}

/// A batch that came with the cursor of the next one, or `null` when it was the last.
final class SelectOptionPage<C> extends SelectOptionsBatch<C> {
  final List<SelectOption> options;
  final C? nextCursor;

  const SelectOptionPage(this.options, {this.nextCursor});
}

/// What a loader receives when its select asks for more options.
class SelectOptionsLoadContext<C> {
  /// `null` on the first call, then the `nextCursor` of the previous batch.
  final C? cursor;

  /// The options loaded so far.
  final List<SelectOption> options;

  const SelectOptionsLoadContext({this.cursor, this.options = const []});
}

/// Something about a batch that the caller may want to log. The merge itself carried on.
enum SelectOptionsBatchIssue {
  /// The batch added nothing and its cursor did not move: a loader that ignores its cursor.
  cursorStuck,
}

/// The options and cursor after a batch was added, and whether the data has ended.
class SelectOptionsMergeResult<C> {
  final C? cursor;

  /// No more batches should be requested.
  final bool finished;
  final SelectOptionsBatchIssue? issue;
  final List<SelectOption> options;

  const SelectOptionsMergeResult({
    required this.cursor,
    required this.finished,
    required this.issue,
    required this.options,
  });
}

/// Adds one loaded batch to the options loaded so far and decides whether the data has ended.
/// Options that are already present are replaced in place by their newer copy. A page ends when
/// its cursor is missing, or when it adds nothing and the cursor did not move. A plain list ends
/// when it adds nothing new. A missing batch counts as an empty list.
SelectOptionsMergeResult<C> mergeSelectOptionsBatch<C>(
  C? cursor,
  List<SelectOption> options,
  SelectOptionsBatch<C>? batch,
) {
  final List<SelectOption> incoming;
  C? nextCursor;
  var hasCursorForm = false;

  switch (batch) {
    case SelectOptionList<C>(options: final list):
      incoming = list;
    case SelectOptionPage<C>(options: final pageOptions, nextCursor: final pageCursor):
      incoming = pageOptions;
      nextCursor = pageCursor;
      hasCursorForm = true;
    case null:
      incoming = const [];
  }

  final merged = dedupeSelectOptions(options, incoming);
  final addedNothing = merged.length == options.length;

  if (!hasCursorForm) {
    return SelectOptionsMergeResult<C>(
      cursor: cursor,
      finished: addedNothing,
      issue: null,
      options: merged,
    );
  }

  final cursorStuck = addedNothing && nextCursor != null && nextCursor == cursor;
  return SelectOptionsMergeResult<C>(
    cursor: nextCursor,
    finished: nextCursor == null || cursorStuck,
    issue: cursorStuck ? SelectOptionsBatchIssue.cursorStuck : null,
    options: merged,
  );
}

/// Loads batches until one adds something new, the data ends, or a few empty batches in a row
/// have been skipped.
///
/// A batch that adds nothing new while more remain would leave the list empty or stuck, so a
/// request for more options would appear to do nothing. The helper keeps going instead, a few
/// batches at most.
///
/// [loadBatch] loads the next batch. [applyBatch] adds a batch to the list and returns `true`
/// when it added nothing while more remain. [isCurrent] returns `false` once the list was reset
/// or its owner went away, which stops the loop.
Future<void> loadUntilOptionsGrow<B>({
  required Future<B> Function() loadBatch,
  required bool Function(B batch) applyBatch,
  required bool Function() isCurrent,
}) async {
  var emptyBatches = 0;
  while (emptyBatches <= SelectConstants.maxEmptyContinuations) {
    final batch = await loadBatch();
    if (!isCurrent() || !applyBatch(batch)) return;
    emptyBatches += 1;
  }
}
