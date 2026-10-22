// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../models/thunderid_error.dart';
import 'management_transport.dart';

// Package-internal: the one place a management request is built, sent, and its failure mapped.

const Set<String> _loopbackHosts = {'localhost', '127.0.0.1', '::1'};

/// Whether [uri] may carry a management request: HTTPS, or plain HTTP to a loopback address
/// for local development (spec "Configuration": `baseUrl`).
bool isAllowedManagementUrl(Uri uri) {
  if (!uri.hasAuthority || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  return uri.scheme == 'http' && _loopbackHosts.contains(uri.host.toLowerCase());
}

/// Builds the request URL: [collectionUrl], then `/{id}`, then `/{subPath}`, then [query]
/// with `null` values dropped.
Uri buildManagementUrl(
  String operation,
  String collectionUrl, {
  String? id,
  String? subPath,
  Map<String, Object?> query = const {},
}) {
  final trimmed = collectionUrl.replaceFirst(RegExp(r'/+$'), '');
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !isAllowedManagementUrl(parsed)) {
    throw IAMException(
      ThunderIDErrorCode.invalidConfiguration,
      '$operation: the management URL must be an absolute HTTPS URL '
      '(plain HTTP is accepted for a loopback address only).',
    );
  }
  if (id != null && id.trim().isEmpty) {
    throw IAMException(ThunderIDErrorCode.invalidInput, '$operation: a resource identifier is required.');
  }

  final segments = <String>[
    ...parsed.pathSegments.where((segment) => segment.isNotEmpty),
    if (id != null) id,
    if (id != null && subPath != null) ...subPath.split('/'),
  ];
  final params = <String, String>{
    ...parsed.queryParameters,
    for (final entry in query.entries)
      if (entry.value != null) entry.key: entry.value.toString(),
  };
  return parsed.replace(pathSegments: segments, queryParameters: params.isEmpty ? null : params);
}

/// Maps an HTTP failure status onto an error code. 403 and 404 are kept distinct so a caller
/// can tell a missing permission from a missing resource (spec "Management operations",
/// requirement 7).
ThunderIDErrorCode managementErrorCodeForStatus(int statusCode) {
  switch (statusCode) {
    case 400:
    case 409:
    case 422:
      return ThunderIDErrorCode.invalidInput;
    case 401:
      return ThunderIDErrorCode.sessionExpired;
    case 403:
      return ThunderIDErrorCode.forbidden;
    case 404:
      return ThunderIDErrorCode.notFound;
    default:
      return ThunderIDErrorCode.serverError;
  }
}

/// Sends one management request through [fetcher] and decodes the JSON answer.
///
/// Returns `null` for a `204` or a `DELETE`. Never retries (spec "Error model", requirement 6).
Future<Object?> sendManagementRequest({
  required ManagementFetcher fetcher,
  required String operation,
  required String failureMessage,
  required String method,
  required Uri url,
  Object? body,
}) async {
  final request = ManagementRequest(
    method: method,
    url: url,
    headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
    body: body == null ? null : jsonEncode(body),
  );

  final ManagementResponse response;
  try {
    response = await fetcher(request);
  } on IAMException {
    rethrow;
  } catch (error) {
    throw IAMApiException(
      ThunderIDErrorCode.networkError,
      '$failureMessage: the server could not be reached.',
      statusCode: 0,
      statusText: 'Network Error',
      operation: operation,
      cause: error,
    );
  }

  if (!response.ok) {
    throw IAMApiException(
      managementErrorCodeForStatus(response.statusCode),
      failureMessage,
      statusCode: response.statusCode,
      statusText: response.statusText,
      operation: operation,
      responseBody: response.body,
    );
  }

  if (response.statusCode == 204 || method == 'DELETE' || response.body.trim().isEmpty) {
    return null;
  }

  try {
    return jsonDecode(response.body);
  } on FormatException catch (error) {
    throw IAMApiException(
      ThunderIDErrorCode.serverError,
      '$failureMessage: the response was not valid JSON.',
      statusCode: response.statusCode,
      statusText: response.statusText,
      operation: operation,
      cause: error,
    );
  }
}
