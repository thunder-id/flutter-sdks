// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/organization_unit.dart';
import '../../models/thunderid_error.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Organization unit operations: `/organization-units`, addressed by identifier or by handle
/// path (`engineering/platform`, under `/organization-units/tree/`). Each handle in a path is
/// percent-encoded on its own and the slashes between them are kept.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.organizationUnits] override, then `{baseUrl}/organization-units`.
extension OrganizationUnitOperations on ThunderIDManagementClient {
  /// [filter] narrows the page, such as `handle eq "engineering"`; [ManagementFilter.equality]
  /// builds one.
  Future<ManagementPage<BasicOrganizationUnit>> getOrganizationUnits({
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getOrganizationUnits',
          'Failed to fetch organization units',
          query: {'filter': filter, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'organizationUnits',
        (item) => BasicOrganizationUnit.fromJson(readMap(item)),
      );

  Future<OrganizationUnit> getOrganizationUnit(String ouId, {String? url, ManagementFetcher? fetcher}) async =>
      OrganizationUnit.fromJson(
        readMap(
          await _send(
            'getOrganizationUnit',
            'Failed to fetch organization unit',
            segments: [ouId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Reads the organization unit at [path], a path of handles such as `engineering/platform`.
  Future<OrganizationUnit> getOrganizationUnitByPath(String path, {String? url, ManagementFetcher? fetcher}) async {
    const operation = 'getOrganizationUnitByPath';
    return OrganizationUnit.fromJson(
      readMap(
        await _send(
          operation,
          'Failed to fetch organization unit',
          segments: ['tree', ...organizationUnitPathSegments(operation, path)],
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
  }

  Future<OrganizationUnit> createOrganizationUnit(
    CreateOrganizationUnitRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      OrganizationUnit.fromJson(
        readMap(
          await _send(
            'createOrganizationUnit',
            'Failed to create organization unit',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<OrganizationUnit> updateOrganizationUnit(
    String ouId,
    UpdateOrganizationUnitRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      OrganizationUnit.fromJson(
        readMap(
          await _send(
            'updateOrganizationUnit',
            'Failed to update organization unit',
            method: 'PUT',
            segments: [ouId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Updates the organization unit at [path], a path of handles such as `engineering/platform`.
  Future<OrganizationUnit> updateOrganizationUnitByPath(
    String path,
    UpdateOrganizationUnitByPathRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'updateOrganizationUnitByPath';
    return OrganizationUnit.fromJson(
      readMap(
        await _send(
          operation,
          'Failed to update organization unit',
          method: 'PUT',
          segments: ['tree', ...organizationUnitPathSegments(operation, path)],
          body: payload.toJson(),
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
  }

  Future<void> deleteOrganizationUnit(String ouId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteOrganizationUnit',
        'Failed to delete organization unit',
        method: 'DELETE',
        segments: [ouId],
        url: url,
        fetcher: fetcher,
      );

  /// Deletes the organization unit at [path], a path of handles such as `engineering/platform`.
  Future<void> deleteOrganizationUnitByPath(String path, {String? url, ManagementFetcher? fetcher}) {
    const operation = 'deleteOrganizationUnitByPath';
    return _send(
      operation,
      'Failed to delete organization unit',
      method: 'DELETE',
      segments: ['tree', ...organizationUnitPathSegments(operation, path)],
      url: url,
      fetcher: fetcher,
    );
  }

  /// Lists the child units of the unit given by [ouId] or by [path] (exactly one of them).
  Future<ManagementPage<BasicOrganizationUnit>> getOrganizationUnitChildren({
    String? ouId,
    String? path,
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getOrganizationUnitChildren';
    return ManagementPage.fromJson(
      await _send(
        operation,
        'Failed to fetch child organization units',
        segments: [..._unitSegments(operation, ouId, path), 'ous'],
        query: {'filter': filter, 'limit': limit, 'offset': offset},
        url: url,
        fetcher: fetcher,
      ),
      'organizationUnits',
      (item) => BasicOrganizationUnit.fromJson(readMap(item)),
    );
  }

  /// Lists the users in the unit given by [ouId] or by [path] (exactly one of them), each with
  /// the label the server resolves for it.
  Future<ManagementPage<OrganizationUnitUser>> getOrganizationUnitUsers({
    String? ouId,
    String? path,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getOrganizationUnitUsers';
    return ManagementPage.fromJson(
      await _send(
        operation,
        'Failed to fetch organization unit users',
        segments: [..._unitSegments(operation, ouId, path), 'users'],
        query: {'include': 'display', 'limit': limit, 'offset': offset},
        url: url,
        fetcher: fetcher,
      ),
      'users',
      (item) => OrganizationUnitUser.fromJson(readMap(item)),
    );
  }

  /// Lists the groups in the unit given by [ouId] or by [path] (exactly one of them).
  Future<ManagementPage<OrganizationUnitGroup>> getOrganizationUnitGroups({
    String? ouId,
    String? path,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getOrganizationUnitGroups';
    return ManagementPage.fromJson(
      await _send(
        operation,
        'Failed to fetch organization unit groups',
        segments: [..._unitSegments(operation, ouId, path), 'groups'],
        query: {'limit': limit, 'offset': offset},
        url: url,
        fetcher: fetcher,
      ),
      'groups',
      (item) => OrganizationUnitGroup.fromJson(readMap(item)),
    );
  }

  /// Lists the roles in the unit given by [ouId] or by [path] (exactly one of them).
  Future<ManagementPage<OrganizationUnitRole>> getOrganizationUnitRoles({
    String? ouId,
    String? path,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getOrganizationUnitRoles';
    return ManagementPage.fromJson(
      await _send(
        operation,
        'Failed to fetch organization unit roles',
        segments: [..._unitSegments(operation, ouId, path), 'roles'],
        query: {'limit': limit, 'offset': offset},
        url: url,
        fetcher: fetcher,
      ),
      'roles',
      (item) => OrganizationUnitRole.fromJson(readMap(item)),
    );
  }

  /// `[ouId]`, or `tree` followed by the handles of [path]. Exactly one must be given.
  static List<String> _unitSegments(String operation, String? ouId, String? path) {
    if ((ouId == null) == (path == null)) {
      throw IAMException(
        ThunderIDErrorCode.invalidInput,
        '$operation: give the organization unit either by ouId or by path, not both or neither.',
      );
    }
    return ouId != null ? [ouId] : ['tree', ...organizationUnitPathSegments(operation, path!)];
  }

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
        endpointKey: ManagementEndpointKeys.organizationUnits,
        collection: 'organization-units',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
