// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// Reads the permissions an access token grants from its `scope` claim (a space-separated
/// string) or `scopes` claim (a list), the two forms the ThunderID server accepts.
///
/// The token is decoded, not verified: use the result only to decide what to show. The server
/// still checks every request (spec "Management operations", requirement 8).
///
/// Returns an empty list when [accessToken] is not a readable JWT.
List<String> getTokenPermissions(String? accessToken) {
  final parts = accessToken?.split('.') ?? const <String>[];
  if (parts.length < 2 || parts[1].isEmpty) return const [];

  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (payload is! Map) return const [];

    final scopes = payload['scopes'];
    if (scopes is List) return scopes.whereType<String>().toList(growable: false);

    final scope = payload['scope'];
    if (scope is String) {
      return scope.split(' ').where((entry) => entry.isNotEmpty).toList(growable: false);
    }
    return const [];
  } on FormatException {
    return const [];
  }
}

/// Whether [granted] covers [required], with the server's hierarchy: permissions are
/// `:`-separated paths, and a permission covers itself and everything under it, so `system`
/// covers `system:user:view`. An empty [required] is always covered.
///
/// The result only decides what to show; the server still decides every request.
bool hasPermission(Iterable<String> granted, String required) =>
    required.isEmpty ||
    granted.any((permission) => permission == required || required.startsWith('$permission:'));
