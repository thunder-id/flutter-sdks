// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/account/organization_unit.dart';
import '../../models/management/json_reader.dart';
import '../../models/thunderid_error.dart';
import '../management/management_request.dart';
import '../management/management_transport.dart';

/// Reads the organization units the signed-in user can access, from `GET {baseUrl}/users/me/ous`.
///
/// [fetcher] sends the request with the signed-in user's access token. [scope] narrows the list
/// relative to the current unit; [limit] and [offset] page it. Failures raise [IAMApiException]
/// with 401, 403 and 404 kept distinct, as for the management operations.
Future<AccessibleOrganizationUnitList> getAccessibleOrganizationUnits({
  required String baseUrl,
  required ManagementFetcher fetcher,
  AccessibleOrganizationUnitScope? scope,
  int? limit,
  int? offset,
}) async {
  const operation = 'getAccessibleOrganizationUnits';
  if ((limit != null && limit < 1) || (offset != null && offset < 0)) {
    throw const IAMException(
      ThunderIDErrorCode.invalidInput,
      '$operation: limit must be at least 1 and offset at least 0.',
    );
  }
  final url = buildManagementUrl(
    operation,
    '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/users',
    segments: const ['me', 'ous'],
    query: {'scope': scope?.value, 'limit': limit, 'offset': offset},
  );
  final json = await sendManagementRequest(
    fetcher: fetcher,
    operation: operation,
    failureMessage: 'Failed to list the organization units you can access',
    method: 'GET',
    url: url,
  );
  return AccessibleOrganizationUnitList.fromJson(readMap(json));
}
