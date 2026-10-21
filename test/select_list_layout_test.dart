// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/select.dart';
import 'package:thunderid_flutter/src/widgets/select_list_layout.dart';

void main() {
  group('SelectListLayout', () {
    test('options with nothing more to load show no status and no Load more row', () {
      final layout = SelectListLayout.of(optionCount: 3, loading: false, canLoadMore: false);

      expect(layout.status, SelectListStatus.none);
      expect(layout.showsLoadMore, false);
    });

    test('options with more to load show the Load more row', () {
      final layout = SelectListLayout.of(optionCount: 30, loading: false, canLoadMore: true);

      expect(layout.status, SelectListStatus.none);
      expect(layout.showsLoadMore, true);
    });

    test('the Load more row stays while more options are loading', () {
      final layout = SelectListLayout.of(optionCount: 30, loading: true, canLoadMore: true);

      expect(layout.status, SelectListStatus.none);
      expect(layout.showsLoadMore, true);
    });

    test('the first load shows loading and no Load more row', () {
      final layout = SelectListLayout.of(optionCount: 0, loading: true, canLoadMore: true);

      expect(layout.status, SelectListStatus.loading);
      expect(layout.showsLoadMore, false);
    });

    test('a failed first load offers Load more again', () {
      final layout = SelectListLayout.of(optionCount: 0, loading: false, canLoadMore: true);

      expect(layout.status, SelectListStatus.none);
      expect(layout.showsLoadMore, true);
    });

    test('nothing at all, with nothing more to load, is empty', () {
      final layout = SelectListLayout.of(optionCount: 0, loading: false, canLoadMore: false);

      expect(layout.status, SelectListStatus.empty);
      expect(layout.showsLoadMore, false);
    });

    test('an empty list that cannot load more and is still loading shows loading', () {
      final layout = SelectListLayout.of(optionCount: 0, loading: true, canLoadMore: false);

      expect(layout.status, SelectListStatus.loading);
    });
  });

  group('resolveSelectOption', () {
    const loaded = [SelectOption('Ada', 'u-1')];
    const picked = SelectOption('Grace', 'u-2');
    const saved = SelectOption('Linus', 'u-3');

    test('an empty value has no option', () {
      expect(resolveSelectOption('', loaded, picked: picked, selectedOption: saved), isNull);
    });

    test('a loaded option wins', () {
      expect(resolveSelectOption('u-1', loaded, picked: picked, selectedOption: saved), loaded[0]);
    });

    test('the option last picked labels a value that is not loaded', () {
      expect(resolveSelectOption('u-2', loaded, picked: picked, selectedOption: saved), picked);
    });

    test('selectedOption labels a value that is neither loaded nor picked', () {
      expect(resolveSelectOption('u-3', loaded, picked: picked, selectedOption: saved), saved);
    });

    test('a value nothing knows has no option', () {
      expect(resolveSelectOption('u-9', loaded, picked: picked, selectedOption: saved), isNull);
    });

    test('a loaded option beats a stale picked copy of the same value', () {
      const stale = SelectOption('Ada (old)', 'u-1');

      expect(resolveSelectOption('u-1', loaded, picked: stale), loaded[0]);
    });
  });
}
