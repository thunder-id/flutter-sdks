// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/select.dart';

void main() {
  group('resolvePageSize', () {
    test('uses the default when none is given', () {
      expect(resolvePageSize(), SelectConstants.defaultPageSize);
      expect(SelectConstants.defaultPageSize, 30);
    });

    test('keeps a size the API serves', () {
      expect(resolvePageSize(1), 1);
      expect(resolvePageSize(50), 50);
      expect(resolvePageSize(100), 100);
    });

    test('raises a size below 1 to 1', () {
      expect(resolvePageSize(0), 1);
      expect(resolvePageSize(-5), 1);
    });

    test('caps a size above what the API serves', () {
      expect(SelectConstants.maxPageSize, 100);
      expect(resolvePageSize(101), 100);
      expect(resolvePageSize(5000), 100);
    });
  });

  group('computeNextPageOffset', () {
    test('null once the page comes back empty', () {
      expect(computeNextPageOffset(0, 0, 100), null);
    });

    test('null on a malformed negative count', () {
      expect(computeNextPageOffset(0, -1, 100), null);
    });

    test('null on a malformed negative request offset', () {
      expect(computeNextPageOffset(-30, 30, 100), null);
    });

    test('advances by the returned count', () {
      expect(computeNextPageOffset(0, 30, 100), 30);
    });

    test('null once the next offset reaches totalResults', () {
      expect(computeNextPageOffset(70, 30, 100), null);
    });

    test('null once the next offset exceeds totalResults', () {
      expect(computeNextPageOffset(90, 30, 100), null);
    });

    test('advances when totalResults is unknown', () {
      expect(computeNextPageOffset(30, 30, null), 60);
    });
  });

  group('isAdvancingPageOffset', () {
    test('a null nextOffset is not advancing (page exhausted)', () {
      expect(isAdvancingPageOffset(30, null), false);
    });

    test('an equal offset is not advancing (would loop)', () {
      expect(isAdvancingPageOffset(30, 30), false);
    });

    test('a lower offset is not advancing (would go backwards)', () {
      expect(isAdvancingPageOffset(30, 10), false);
    });

    test('a strictly greater offset is advancing', () {
      expect(isAdvancingPageOffset(30, 60), true);
    });
  });

  group('dedupeSelectOptions', () {
    test('preserves first-seen order across both lists', () {
      const existing = [SelectOption('Alice', '1'), SelectOption('Bob', '2')];
      const incoming = [SelectOption('Carol', '3')];
      final result = dedupeSelectOptions(existing, incoming);
      expect(result.map((o) => o.value), ['1', '2', '3']);
    });

    test('a repeated value keeps its first position but takes the newest data', () {
      const existing = [SelectOption('Alice', '1'), SelectOption('Bob (stale)', '2')];
      const incoming = [SelectOption('Bob (fresh)', '2'), SelectOption('Carol', '3')];
      final result = dedupeSelectOptions(existing, incoming);
      expect(result.map((o) => o.value), ['1', '2', '3']);
      expect(result[1].label, 'Bob (fresh)');
    });

    test('a value repeated inside one batch collapses to one option', () {
      const incoming = [SelectOption('A', '1'), SelectOption('A again', '1')];
      final result = dedupeSelectOptions(const [], incoming);
      expect(result, hasLength(1));
      expect(result.single.label, 'A again');
    });

    test('both lists empty is empty', () {
      expect(dedupeSelectOptions(const [], const []), isEmpty);
    });
  });

  group('SelectOption', () {
    test('equal when label, value and disabled all match', () {
      expect(const SelectOption('A', '1'), const SelectOption('A', '1'));
    });

    test('not equal when disabled differs', () {
      expect(
        const SelectOption('A', '1', disabled: true),
        isNot(const SelectOption('A', '1')),
      );
    });
  });

  group('toSelectOption(s)', () {
    final mapping = SelectOptionMapping<Map<String, String?>>(
      label: (item) => item['title'],
      value: (item) => item['sku'],
    );

    test('uses the mapped label and value', () {
      expect(
        toSelectOption({'sku': 'p-1', 'title': 'Widget'}, mapping),
        const SelectOption('Widget', 'p-1'),
      );
    });

    test('falls back to the value when there is no label', () {
      expect(toSelectOption({'sku': 'p-1'}, mapping)?.label, 'p-1');
    });

    test('drops an item without a value', () {
      expect(toSelectOption({'title': 'Widget'}, mapping), isNull);
    });

    test('converts a page and skips items without a value', () {
      final items = <Map<String, String?>>[
        {'sku': 'p-1', 'title': 'A'},
        {'title': 'B'},
        {'sku': 'p-3', 'title': 'C'},
      ];
      final options = toSelectOptions(items, mapping);
      expect(options.map((o) => o.value), ['p-1', 'p-3']);
    });
  });

  group('toListSelectPage', () {
    test('the next offset follows the count the backend returned, not the options kept', () {
      final page = toListSelectPage<String>(
        options: const [SelectOption('A', '1')],
        count: 30,
        totalResults: 100,
        requestOffset: 0,
      );
      expect(page.nextOffset, 30);
      expect(page.totalResults, 100);
      expect(page.options, hasLength(1));
    });

    test('the last page has no next offset', () {
      final page = toListSelectPage<String>(
        options: const [],
        count: 10,
        totalResults: 100,
        requestOffset: 90,
      );
      expect(page.nextOffset, null);
    });
  });
}
