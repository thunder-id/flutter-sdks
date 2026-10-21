// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/select.dart';
import 'package:thunderid_flutter/src/models/select_loading.dart';

SelectOption option(String value, [String? label]) => SelectOption(label ?? value, value);

SelectOptionsBatch<int> optionList(List<String> values) =>
    SelectOptionsBatch<int>.list(values.map(option).toList());

SelectOptionsBatch<int> pageOf(List<String> values, {int? nextCursor}) =>
    SelectOptionsBatch<int>.page(values.map(option).toList(), nextCursor: nextCursor);

List<String> values(SelectOptionsMergeResult<int> result) =>
    result.options.map((o) => o.value).toList();

void main() {
  group('mergeSelectOptionsBatch', () {
    test('a list that adds something continues', () {
      final result = mergeSelectOptionsBatch<int>(null, [option('a')], optionList(['b']));

      expect(values(result), ['a', 'b']);
      expect(result.finished, false);
    });

    test('a list that adds nothing new ends the data', () {
      final result = mergeSelectOptionsBatch<int>(null, [option('a')], optionList(['a']));

      expect(result.finished, true);
      expect(result.issue, isNull);
    });

    test('a page without a cursor ends the data after appending', () {
      final result = mergeSelectOptionsBatch<int>(0, const [], pageOf(['a']));

      expect(values(result), ['a']);
      expect(result.finished, true);
      expect(result.cursor, isNull);
    });

    test('a page with a cursor continues from it', () {
      final result = mergeSelectOptionsBatch<int>(0, const [], pageOf(['a'], nextCursor: 30));

      expect(result.finished, false);
      expect(result.cursor, 30);
    });

    test('a page of duplicates with an advancing cursor continues', () {
      final result = mergeSelectOptionsBatch<int>(0, [option('a')], pageOf(['a'], nextCursor: 30));

      expect(result.finished, false);
      expect(result.cursor, 30);
    });

    test('a page of duplicates with the same cursor ends the data and reports it', () {
      final result =
          mergeSelectOptionsBatch<int>(30, [option('a')], pageOf(['a'], nextCursor: 30));

      expect(result.finished, true);
      expect(result.issue, SelectOptionsBatchIssue.cursorStuck);
    });

    test('a page that adds something with the same cursor is not stuck', () {
      final result =
          mergeSelectOptionsBatch<int>(30, [option('a')], pageOf(['b'], nextCursor: 30));

      expect(result.finished, false);
      expect(result.issue, isNull);
    });

    test('a repeated option is replaced in place by its newer copy', () {
      final existing = [option('a', 'Old'), option('b')];
      final batch = SelectOptionsBatch<int>.list([option('a', 'New')]);
      final result = mergeSelectOptionsBatch<int>(null, existing, batch);

      expect(result.options.map((o) => o.label), ['New', 'b']);
    });

    test('a missing batch counts as an empty list', () {
      final result = mergeSelectOptionsBatch<int>(null, [option('a')], null);

      expect(values(result), ['a']);
      expect(result.finished, true);
    });
  });

  group('loadUntilOptionsGrow', () {
    test('stops after a batch that grew the list', () async {
      var loads = 0;

      await loadUntilOptionsGrow<int>(
        loadBatch: () async => ++loads,
        applyBatch: (_) => false,
        isCurrent: () => true,
      );

      expect(loads, 1);
    });

    test('keeps loading while batches add nothing but stops after a few in a row', () async {
      var loads = 0;

      await loadUntilOptionsGrow<int>(
        loadBatch: () async => ++loads,
        applyBatch: (_) => true,
        isCurrent: () => true,
      );

      expect(loads, SelectConstants.maxEmptyContinuations + 1);
    });

    test('stops without applying once the list was reset', () async {
      var applied = 0;

      await loadUntilOptionsGrow<int>(
        loadBatch: () async => 1,
        applyBatch: (_) {
          applied += 1;
          return true;
        },
        isCurrent: () => false,
      );

      expect(applied, 0);
    });

    test('passes a load failure on', () async {
      await expectLater(
        loadUntilOptionsGrow<int>(
          loadBatch: () async => throw StateError('boom'),
          applyBatch: (_) => false,
          isCurrent: () => true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
