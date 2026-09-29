// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'paged_select.dart';

/// A user record managed through the ThunderID management API.
///
/// This is a server record, distinct from `User` (`lib/src/models/user.dart`), which describes
/// the signed-in user. Nothing in this package populates it yet: the `client.getUsers()` bridge
/// call is not wired (native `users.list` support has not been released for the iOS/Android SDKs
/// this package bridges to). An application can fill it from its own API and pass the loader to
/// a `PagedSelectField<ManagedUser>`.
class ManagedUser {
  final String id;
  final String? ouId;
  final String? type;
  final Map<String, dynamic>? attributes;
  final String? display;
  final bool? isReadOnly;

  const ManagedUser({
    required this.id,
    this.ouId,
    this.type,
    this.attributes,
    this.display,
    this.isReadOnly,
  });

  factory ManagedUser.fromMap(Map<dynamic, dynamic> map) => ManagedUser(
        id: map['id'] as String? ?? '',
        ouId: map['ouId'] as String?,
        type: map['type'] as String?,
        attributes: (map['attributes'] as Map?)?.cast<String, dynamic>(),
        display: map['display'] as String?,
        isReadOnly: map['isReadOnly'] as bool?,
      );
}

/// A page of users, as `GET /users` returns it.
class ManagedUserListResponse {
  final int totalResults;
  final int startIndex;
  final int count;
  final List<ManagedUser> users;

  const ManagedUserListResponse({
    required this.totalResults,
    required this.startIndex,
    required this.count,
    required this.users,
  });
}

/// Loads one page of users, for a `PagedSelectField<ManagedUser>`.
typedef FetchUsers = FetchPagedOptions<ManagedUser>;

/// Chooses which attribute of a [ManagedUser] is the label and which is the value, for a
/// picker that does not want the default `display -> username -> email -> id` chain.
typedef UserSelectOptionMapping = PagedSelectOptionMapping<ManagedUser>;

String? _attributeText(ManagedUser user, String key) {
  final raw = user.attributes?[key];
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Converts one directory user into an option: submits the user's ID and labels it from
/// `display`, then `username`, then `email`, unless [mapping] says otherwise. `display` equal
/// to the ID is treated as unset, since the backend returns the ID as display when a user type
/// has no display attribute configured.
PagedSelectOption? toUserSelectOption(ManagedUser user, {UserSelectOptionMapping? mapping}) {
  if (mapping != null) return toPagedSelectOption(user, mapping);

  final display = user.display?.trim();
  final label = (display != null && display.isNotEmpty && display != user.id)
      ? display
      : _attributeText(user, 'username') ?? _attributeText(user, 'email') ?? user.id;
  return PagedSelectOption(label, user.id);
}

/// Converts a page of users into picker options, dropping any user the mapping has no value for.
List<PagedSelectOption> toUserSelectOptions(
  List<ManagedUser> users, {
  UserSelectOptionMapping? mapping,
}) =>
    users
        .map((user) => toUserSelectOption(user, mapping: mapping))
        .whereType<PagedSelectOption>()
        .toList();

/// Converts a `GET /users` response into a loader page. The next offset comes from the
/// backend's own `count`, so users dropped by the mapping never shift the paging.
PagedSelectPage<ManagedUser> toUserSelectPage(
  ManagedUserListResponse response,
  int requestOffset, {
  UserSelectOptionMapping? mapping,
}) =>
    PagedSelectPage(
      options: toUserSelectOptions(response.users, mapping: mapping),
      nextOffset: computeNextPageOffset(requestOffset, response.count, response.totalResults),
      totalResults: response.totalResults,
    );
