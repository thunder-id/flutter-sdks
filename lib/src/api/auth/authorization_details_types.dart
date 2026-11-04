// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/authorization_details_type_metadata.dart';
import '../../models/management/json_reader.dart';
import '../management/management_request.dart';
import '../management/management_transport.dart';

/// Lists the RFC 9396 authorization details types a client may request, in their public request
/// view (`GET {baseUrl}/oauth2/authorization-details-types`).
///
/// The endpoint is public: the default transport sends no access token. [url] replaces the
/// endpoint URL (for example the `authorization_details_types_endpoint` from the server's
/// discovery document), and [fetcher] replaces the transport. [allowInsecureConnections] mirrors
/// `ThunderIDConfig.allowInsecureConnections` for the default transport. A failure raises an
/// [IAMApiException] like a management operation does.
Future<List<AuthorizationDetailsTypeMetadata>> getSupportedAuthorizationDetailsTypes({
  required String baseUrl,
  String? url,
  ManagementFetcher? fetcher,
  bool allowInsecureConnections = false,
}) async {
  const operation = 'getSupportedAuthorizationDetailsTypes';
  final json = readMap(
    await sendManagementRequest(
      fetcher: fetcher ?? _publicFetcher(allowInsecureConnections),
      operation: operation,
      failureMessage: 'Failed to fetch the supported authorization details types',
      method: 'GET',
      url: buildManagementUrl(operation, url ?? _endpoint(baseUrl)),
    ),
  );
  return [
    for (final item in readList(json, 'types'))
      if (item is Map) AuthorizationDetailsTypeMetadata.fromJson(readMap(item)),
  ];
}

/// Reads the public request view of the authorization details type whose value is [type]
/// (`GET {baseUrl}/oauth2/authorization-details-types/{type}`). [type] is percent-encoded as one
/// path segment, since it may be a URI. An unregistered type raises an [IAMApiException] with
/// `notFound`. The other parameters work as in [getSupportedAuthorizationDetailsTypes], with
/// [url] replacing the list endpoint the type is appended to.
Future<AuthorizationDetailsTypeMetadata> getSupportedAuthorizationDetailsType(
  String type, {
  required String baseUrl,
  String? url,
  ManagementFetcher? fetcher,
  bool allowInsecureConnections = false,
}) async {
  const operation = 'getSupportedAuthorizationDetailsType';
  return AuthorizationDetailsTypeMetadata.fromJson(
    readMap(
      await sendManagementRequest(
        fetcher: fetcher ?? _publicFetcher(allowInsecureConnections),
        operation: operation,
        failureMessage: 'Failed to fetch the authorization details type',
        method: 'GET',
        url: buildManagementUrl(operation, url ?? _endpoint(baseUrl), segments: [type]),
      ),
    ),
  );
}

String _endpoint(String baseUrl) => '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/oauth2/authorization-details-types';

ManagementFetcher _publicFetcher(bool allowInsecureConnections) =>
    createAuthenticatedFetcher(() async => '', allowInsecureConnections: allowInsecureConnections);
