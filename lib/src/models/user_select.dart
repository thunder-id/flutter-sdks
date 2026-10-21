// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'select.dart';

/// A user record managed through the ThunderID management API.
///
/// This is a server record, distinct from `User` (`lib/src/models/user.dart`), which describes
/// the signed-in user. Nothing in this package populates it yet: the `client.getUsers()` bridge
/// call is not wired (native `users.list` support has not been released for the iOS/Android SDKs
/// this package bridges to). An application can fill it from its own API, convert a page with
/// [toUserSelectPage] and list it in a `SelectField` through an `InfiniteOptionsController`.
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

/// Loads one page of users.
typedef FetchUsers = FetchSelectPage<ManagedUser>;

/// Chooses which attribute of a [ManagedUser] is the label and which is the value, for a
/// field that does not want the default `display -> username -> email -> id` chain.
typedef UserSelectOptionMapping = SelectOptionMapping<ManagedUser>;

String? _attributeText(ManagedUser user, String key) {
  final raw = user.attributes?[key];
  return raw is String ? raw : null;
}

/// The trimmed text, or `null` when it is empty or only repeats the user's ID.
String? _labelText(String? text, ManagedUser user) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == user.id) return null;
  return trimmed;
}

/// Converts one directory user into an option: submits the user's ID and labels it from
/// `display`, then `username`, then `email`, unless [mapping] says otherwise. A label equal to
/// the ID is treated as unset, since the backend returns the ID as display when a user type has
/// no display attribute configured.
SelectOption? toUserSelectOption(ManagedUser user, {UserSelectOptionMapping? mapping}) {
  if (mapping != null) return toSelectOption(user, mapping);

  final label = _labelText(user.display, user) ??
      _labelText(_attributeText(user, 'username'), user) ??
      _labelText(_attributeText(user, 'email'), user) ??
      user.id;
  return SelectOption(label, user.id);
}

/// Converts a page of users into options, dropping any user the mapping has no value for.
List<SelectOption> toUserSelectOptions(
  List<ManagedUser> users, {
  UserSelectOptionMapping? mapping,
}) =>
    users
        .map((user) => toUserSelectOption(user, mapping: mapping))
        .whereType<SelectOption>()
        .toList();

/// Converts a `GET /users` response into a loader page. The next offset comes from the
/// backend's own `count`, so users dropped by the mapping never shift the paging.
SelectPage<ManagedUser> toUserSelectPage(
  ManagedUserListResponse response,
  int requestOffset, {
  UserSelectOptionMapping? mapping,
}) =>
    toListSelectPage<ManagedUser>(
      options: toUserSelectOptions(response.users, mapping: mapping),
      count: response.count,
      totalResults: response.totalResults,
      requestOffset: requestOffset,
    );
