// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/thunderid_error.dart';
import 'management_request.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

// Package-internal (not exported): how every management operation, in the client and in the
// per-resource extensions, resolves its URL and sends its request.

/// Sends one request to a management collection of [client].
///
/// The collection URL is, in order: [url], the [ThunderIDManagementClient.endpoints] override
/// under [endpointKey], then `{baseUrl}/{collection}`. [segments] follow it, each encoded on its
/// own. [fetcher] replaces the client's transport for this call only.
Future<Object?> sendCollectionRequest(
  ThunderIDManagementClient client, {
  required String operation,
  required String failureMessage,
  String? endpointKey,
  required String collection,
  String method = 'GET',
  List<String> segments = const [],
  Map<String, Object?> query = const {},
  Object? body,
  String? url,
  ManagementFetcher? fetcher,
}) {
  final override = endpointKey == null ? null : client.endpoints[endpointKey];
  final collectionUrl = url ?? override ?? '${client.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$collection';
  final resolved = buildManagementUrl(operation, collectionUrl, segments: segments, query: query);
  return sendManagementRequest(
    fetcher: fetcher ?? client.fetcher,
    operation: operation,
    failureMessage: failureMessage,
    method: method,
    url: resolved,
    body: body,
  );
}

/// The segments of an organization unit handle path such as `engineering/platform`: leading and
/// trailing slashes are ignored, and each handle becomes its own URL segment, so a handle is
/// percent-encoded while the slashes between handles stay. Raises
/// [ThunderIDErrorCode.invalidInput] for a path with no handle or an empty one (`a//b`).
List<String> organizationUnitPathSegments(String operation, String path) {
  final trimmed = path.trim().replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'/+$'), '');
  final handles = trimmed.split('/');
  if (trimmed.isEmpty || handles.any((handle) => handle.trim().isEmpty)) {
    throw IAMException(
      ThunderIDErrorCode.invalidInput,
      '$operation: an organization unit path of one or more handles, such as "engineering/platform", is required.',
    );
  }
  return handles;
}
