// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/paged_select.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';

void main() {
  group('computeNextPageOffset', () {
    test('null once the page comes back empty', () {
      expect(computeNextPageOffset(0, 0, 100), null);
    });

    test('null on a malformed negative count', () {
      expect(computeNextPageOffset(0, -1, 100), null);
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

  group('dedupePagedSelectOptions', () {
    test('preserves first-seen order across both lists', () {
      const existing = [PagedSelectOption('Alice', '1'), PagedSelectOption('Bob', '2')];
      const incoming = [PagedSelectOption('Carol', '3')];
      final result = dedupePagedSelectOptions(existing, incoming);
      expect(result.map((o) => o.value), ['1', '2', '3']);
    });

    test('a repeated value keeps its first position but takes the newest data', () {
      const existing = [PagedSelectOption('Alice', '1'), PagedSelectOption('Bob (stale)', '2')];
      const incoming = [PagedSelectOption('Bob (fresh)', '2'), PagedSelectOption('Carol', '3')];
      final result = dedupePagedSelectOptions(existing, incoming);
      expect(result.map((o) => o.value), ['1', '2', '3']);
      expect(result[1].label, 'Bob (fresh)');
    });

    test('both lists empty is empty', () {
      expect(dedupePagedSelectOptions(const [], const []), isEmpty);
    });
  });

  group('PagedSelectOption', () {
    test('equal when label, value and disabled all match', () {
      expect(const PagedSelectOption('A', '1'), const PagedSelectOption('A', '1'));
    });

    test('not equal when disabled differs', () {
      expect(
        const PagedSelectOption('A', '1', disabled: true),
        isNot(const PagedSelectOption('A', '1')),
      );
    });
  });

  group('mapPagedSelectError', () {
    test('trusts an IAMException message', () {
      const error = IAMException(ThunderIDErrorCode.networkError, 'Network unreachable');
      expect(mapPagedSelectError(error).message, 'Network unreachable');
    });

    test('a bare exception carries no message', () {
      expect(mapPagedSelectError(Exception('internal detail')).message, null);
    });

    test('a plain thrown string carries no message', () {
      expect(mapPagedSelectError('raw string error').message, null);
    });
  });

  group('toPagedSelectOption(s)', () {
    final mapping = PagedSelectOptionMapping<Map<String, String?>>(
      label: (item) => item['title'],
      value: (item) => item['sku'],
    );

    test('uses the mapped label and value', () {
      expect(
        toPagedSelectOption({'sku': 'p-1', 'title': 'Widget'}, mapping),
        const PagedSelectOption('Widget', 'p-1'),
      );
    });

    test('falls back to the value when there is no label', () {
      expect(toPagedSelectOption({'sku': 'p-1'}, mapping)?.label, 'p-1');
    });

    test('drops an item without a value', () {
      expect(toPagedSelectOption({'title': 'Widget'}, mapping), isNull);
    });

    test('converts a page and skips items without a value', () {
      final items = <Map<String, String?>>[
        {'sku': 'p-1', 'title': 'A'},
        {'title': 'B'},
        {'sku': 'p-3', 'title': 'C'},
      ];
      final options = toPagedSelectOptions(items, mapping);
      expect(options.map((o) => o.value), ['p-1', 'p-3']);
    });
  });
}
