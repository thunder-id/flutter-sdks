// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// Builds the filter expressions the management list endpoints accept.
abstract final class ManagementFilter {
  static final RegExp _attribute = RegExp(r'^\w+(\.\w+)*$');

  /// `attribute eq "value"`, for example to search users by username. The server matches the whole value.
  ///
  /// Surrounding whitespace is ignored and double quotes, which the expression cannot carry, are removed.
  /// Returns `null` when the value is blank or the attribute name is not valid.
  static String? equality(String attribute, String value) {
    final cleaned = value.replaceAll('"', '').trim();
    if (cleaned.isEmpty || !_attribute.hasMatch(attribute)) return null;
    return '$attribute eq "$cleaned"';
  }
}
