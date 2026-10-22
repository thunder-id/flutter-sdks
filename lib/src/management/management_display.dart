// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/thunderid_error.dart';

/// Turns a failed management request into a message for admin UI. A missing permission and a
/// missing resource get their own messages; anything else gets [fallbackKey]. The server's own
/// error text is never shown (spec "UI", requirement 6).
///
/// [translate] resolves a translation key, e.g. `ThunderIDI18n.resolve`. Returns `null` when
/// [error] is `null`.
String? toManagementErrorMessage(
  String Function(String key) translate,
  Object? error,
  String fallbackKey,
) {
  if (error == null) return null;
  if (error is IAMException) {
    if (error.code == ThunderIDErrorCode.forbidden) return translate('admin.common.errors.forbidden');
    if (error.code == ThunderIDErrorCode.notFound) return translate('admin.common.errors.not_found');
  }
  return translate(fallbackKey);
}

/// Picks the label to show for a managed identity: the server's [display] value, then [name],
/// then the common name attributes, then [id].
String resolveManagedIdentityName({
  required String id,
  String? display,
  String? name,
  Map<String, dynamic> attributes = const {},
}) {
  if (display != null && display.isNotEmpty) return display;
  if (name != null && name.isNotEmpty) return name;

  final attributeName = attributes['name'];
  if (attributeName is String && attributeName.isNotEmpty) return attributeName;

  final fullName = [attributes['given_name'], attributes['family_name']]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' ');
  if (fullName.isNotEmpty) return fullName;

  final username = attributes['username'];
  if (username is String && username.isNotEmpty) return username;
  return id;
}
