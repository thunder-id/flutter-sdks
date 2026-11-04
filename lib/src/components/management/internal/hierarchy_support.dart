// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

// Package-internal (not exported): what the project, organization unit, and sharing components
// share.

/// The handle rule projects and organization units share: lowercase letters, numbers, hyphens and
/// underscores, starting and ending with a letter or a number, at most 100 characters.
bool isValidAdminHandle(String handle) =>
    handle.length <= 100 && RegExp(r'^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$').hasMatch(handle);

/// `null` for blank text, otherwise the trimmed text.
String? optionalText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// An RFC 3339 timestamp as `YYYY-MM-DD HH:MM` in local time, or the text as given when it does
/// not parse.
String formatAdminTimestamp(String? text) {
  if (text == null || text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// The server's error codes a project or organization unit write maps to its own message.
abstract final class HierarchyErrorKeys {
  /// Project create and update: `PRJ-1006` the id and `PRJ-1012` the handle is already used, and
  /// `PRJ-1007` the handle cannot be changed. The server never refuses a project delete, so it has
  /// no codes of its own.
  static const Map<String, String> project = {
    'PRJ-1006': 'admin.projects.errors.id_conflict',
    'PRJ-1012': 'admin.projects.errors.handle_conflict',
    'PRJ-1007': 'admin.projects.errors.handle_immutable',
  };

  /// Organization unit create and update: `OU-1004` the name and `OU-1008` the handle is already
  /// used, and `OU-1012` the unit is a declarative resource that cannot be modified.
  static const Map<String, String> organizationUnit = {
    'OU-1004': 'admin.organization_units.errors.name_conflict',
    'OU-1008': 'admin.organization_units.errors.handle_conflict',
    'OU-1012': 'admin.organization_units.errors.declarative',
  };

  /// Organization unit delete: `OU-1006` the unit still has child units, users, groups or other
  /// resources, and `OU-1012` the unit is a declarative resource.
  static const Map<String, String> organizationUnitDelete = {
    'OU-1006': 'admin.organization_units.details.delete.has_children',
    'OU-1012': 'admin.organization_units.errors.declarative',
  };

  /// Sharing policy writes, for each resource type: an edit against a stale version, and a second
  /// policy from the same organization unit.
  static const Map<String, String> sharing = {
    'USR-1032': 'admin.sharing.errors.conflict',
    'APP-1054': 'admin.sharing.errors.conflict',
    'ROL-1024': 'admin.sharing.errors.conflict',
    'FLM-1032': 'admin.sharing.errors.conflict',
    'USR-1031': 'admin.sharing.errors.exists',
    'APP-1053': 'admin.sharing.errors.exists',
    'ROL-1023': 'admin.sharing.errors.exists',
    'FLM-1031': 'admin.sharing.errors.exists',
  };
}
