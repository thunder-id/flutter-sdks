// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/authorization_detail_type.dart';
import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// RFC 9396 authorization details type operations: `/authorization-detail-types`. The public view
/// of the registered types, which a client reads before requesting them, is
/// `getSupportedAuthorizationDetailsTypes` in the auth data layer.
///
/// A processor's credential values are write-only; nothing here logs them.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.authorizationDetailTypes] override, then
/// `{baseUrl}/authorization-detail-types`.
extension AuthorizationDetailTypeOperations on ThunderIDManagementClient {
  /// Lists the registered types, a page at a time, ordered by type value.
  Future<ManagementPage<AuthorizationDetailType>> getAuthorizationDetailTypes({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getAuthorizationDetailTypes',
          'Failed to fetch authorization detail types',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'types',
        (item) => AuthorizationDetailType.fromJson(readMap(item)),
      );

  /// Reads one type by its [id] (not its `type` value).
  Future<AuthorizationDetailType> getAuthorizationDetailType(
    String id, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      AuthorizationDetailType.fromJson(
        readMap(
          await _send(
            'getAuthorizationDetailType',
            'Failed to fetch authorization detail type',
            segments: [id],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<AuthorizationDetailType> createAuthorizationDetailType(
    AuthorizationDetailTypeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      AuthorizationDetailType.fromJson(
        readMap(
          await _send(
            'createAuthorizationDetailType',
            'Failed to create authorization detail type',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<AuthorizationDetailType> updateAuthorizationDetailType(
    String id,
    AuthorizationDetailTypeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      AuthorizationDetailType.fromJson(
        readMap(
          await _send(
            'updateAuthorizationDetailType',
            'Failed to update authorization detail type',
            method: 'PUT',
            segments: [id],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteAuthorizationDetailType(String id, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteAuthorizationDetailType',
        'Failed to delete authorization detail type',
        method: 'DELETE',
        segments: [id],
        url: url,
        fetcher: fetcher,
      );

  Future<Object?> _send(
    String operation,
    String failureMessage, {
    String method = 'GET',
    List<String> segments = const [],
    Map<String, Object?> query = const {},
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: ManagementEndpointKeys.authorizationDetailTypes,
        collection: 'authorization-detail-types',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
