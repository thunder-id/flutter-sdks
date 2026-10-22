// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// A pagination link returned with a management list.
class ManagementPaginationLink {
  final String href;
  final String rel;

  const ManagementPaginationLink({required this.href, required this.rel});

  factory ManagementPaginationLink.fromJson(Map<String, dynamic> json) =>
      ManagementPaginationLink(href: readString(json, 'href'), rel: readString(json, 'rel'));
}

/// One page of a management list, with the total count (spec "Management operations": List).
///
/// The server names the list field per resource (`users`, `groups`, `members`, ...); every page
/// exposes it here as [items].
class ManagementPage<T> {
  final List<T> items;

  /// Total number of records across all pages.
  final int totalResults;

  /// Index of the first record on this page.
  final int startIndex;

  /// Number of records on this page.
  final int count;

  final List<ManagementPaginationLink> links;

  const ManagementPage({
    required this.items,
    required this.totalResults,
    this.startIndex = 0,
    int? count,
    this.links = const [],
  }) : count = count ?? items.length;

  /// Parses a list response whose records sit under [listKey]. Records [parseItem] returns
  /// `null` for are dropped.
  static ManagementPage<T> fromJson<T>(
    Object? json,
    String listKey,
    T? Function(Object? item) parseItem,
  ) {
    final map = readMap(json);
    final items = readList(map, listKey).map(parseItem).whereType<T>().toList(growable: false);
    return ManagementPage<T>(
      items: items,
      totalResults: readInt(map, 'totalResults', items.length),
      startIndex: readInt(map, 'startIndex'),
      count: readInt(map, 'count', items.length),
      links: readList(map, 'links')
          .map((link) => ManagementPaginationLink.fromJson(readMap(link)))
          .toList(growable: false),
    );
  }
}
