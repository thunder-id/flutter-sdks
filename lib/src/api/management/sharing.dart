// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/group.dart';
import '../../models/management/json_reader.dart';
import '../../models/management/managed_user.dart';
import '../../models/management/management_page.dart';
import '../../models/management/sharing_policy.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// The user, group, application, role, and flow endpoints beyond their CRUD: users and groups by
/// organization unit path (`/users/tree/{path}`, `/groups/tree/{path}`), sharing policies
/// (`/{users|applications|roles|flows}/{id}/sharing-policies`), and the overlay that applies to a
/// shared user, application, role, or flow in a unit (`.../overlay-rules`).
///
/// URLs resolve like the other operations on the same collection: the `url` passed to the call,
/// the [ManagementEndpointKeys.users], [ManagementEndpointKeys.groups],
/// [ManagementEndpointKeys.applications], [ManagementEndpointKeys.roles], or
/// [ManagementEndpointKeys.flows] override, then `{baseUrl}/users`, `{baseUrl}/groups`,
/// `{baseUrl}/applications`, `{baseUrl}/roles`, or `{baseUrl}/flows`.
extension SharingOperations on ThunderIDManagementClient {
  // ── Users by path ──────────────────────────────────────────────────────

  /// Lists the users in the organization unit at [path], a path of handles such as
  /// `engineering/platform`. The server takes no filter on this listing.
  Future<ManagementPage<ManagedUser>> getUsersByPath(
    String path, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getUsersByPath';
    return ManagementPage.fromJson(
      await _send(
        _users,
        operation,
        'Failed to fetch users',
        segments: ['tree', ...organizationUnitPathSegments(operation, path)],
        query: {'include': 'display', 'limit': limit, 'offset': offset},
        url: url,
        fetcher: fetcher,
      ),
      'users',
      (item) => ManagedUser.fromJson(readMap(item)),
    );
  }

  /// Creates a user in the organization unit at [path], a path of handles such as
  /// `engineering/platform`.
  Future<ManagedUser> createUserByPath(
    String path,
    CreateUserByPathRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'createUserByPath';
    return ManagedUser.fromJson(
      readMap(
        await _send(
          _users,
          operation,
          'Failed to create user',
          method: 'POST',
          segments: ['tree', ...organizationUnitPathSegments(operation, path)],
          body: payload.toJson(),
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
  }

  // ── Groups by path ─────────────────────────────────────────────────────

  /// Lists the groups in the organization unit at [path], a path of handles such as
  /// `engineering/platform`. Each handle is percent-encoded on its own and the slashes between
  /// them are kept. The server takes no filter on this listing.
  Future<ManagementPage<Group>> getGroupsByPath(
    String path, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getGroupsByPath';
    return ManagementPage.fromJson(
      await _send(
        _groups,
        operation,
        'Failed to fetch groups',
        segments: ['tree', ...organizationUnitPathSegments(operation, path)],
        query: {'include': 'display', 'limit': limit, 'offset': offset},
        url: url,
        fetcher: fetcher,
      ),
      'groups',
      (item) => Group.fromJson(readMap(item)),
    );
  }

  /// Creates a group in the organization unit at [path], a path of handles such as
  /// `engineering/platform`. Every initial member must be owned by, or shared with, that unit.
  Future<Group> createGroupByPath(
    String path,
    CreateGroupByPathRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'createGroupByPath';
    return Group.fromJson(
      readMap(
        await _send(
          _groups,
          operation,
          'Failed to create group',
          method: 'POST',
          segments: ['tree', ...organizationUnitPathSegments(operation, path)],
          body: payload.toJson(),
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
  }

  // ── User sharing ───────────────────────────────────────────────────────

  Future<ManagementPage<SharingPolicy>> getUserSharingPolicies(
    String userId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getPolicies(_users, 'getUserSharingPolicies', userId, limit, offset, url, fetcher);

  Future<SharingPolicy> createUserSharingPolicy(
    String userId,
    CreateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_users, 'createUserSharingPolicy', 'POST', userId, null, payload.toJson(), url, fetcher);

  Future<SharingPolicy> getUserSharingPolicy(
    String userId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_users, 'getUserSharingPolicy', 'GET', userId, policyId, null, url, fetcher);

  Future<SharingPolicy> updateUserSharingPolicy(
    String userId,
    String policyId,
    UpdateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_users, 'updateUserSharingPolicy', 'PUT', userId, policyId, payload.toJson(), url, fetcher);

  Future<void> deleteUserSharingPolicy(
    String userId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _deletePolicy(_users, 'deleteUserSharingPolicy', userId, policyId, url, fetcher);

  /// Reads how [userId] appears in the organization unit [ouId] (by default, the unit the
  /// caller signed in to).
  Future<ResolvedOverlay> getUserOverlayRules(
    String userId, {
    String? ouId,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getOverlay(_users, 'getUserOverlayRules', userId, ouId, url, fetcher);

  // ── Application sharing ────────────────────────────────────────────────

  Future<ManagementPage<SharingPolicy>> getApplicationSharingPolicies(
    String applicationId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getPolicies(_applications, 'getApplicationSharingPolicies', applicationId, limit, offset, url, fetcher);

  Future<SharingPolicy> createApplicationSharingPolicy(
    String applicationId,
    CreateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(
        _applications,
        'createApplicationSharingPolicy',
        'POST',
        applicationId,
        null,
        payload.toJson(),
        url,
        fetcher,
      );

  Future<SharingPolicy> getApplicationSharingPolicy(
    String applicationId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_applications, 'getApplicationSharingPolicy', 'GET', applicationId, policyId, null, url, fetcher);

  Future<SharingPolicy> updateApplicationSharingPolicy(
    String applicationId,
    String policyId,
    UpdateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(
        _applications,
        'updateApplicationSharingPolicy',
        'PUT',
        applicationId,
        policyId,
        payload.toJson(),
        url,
        fetcher,
      );

  Future<void> deleteApplicationSharingPolicy(
    String applicationId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _deletePolicy(_applications, 'deleteApplicationSharingPolicy', applicationId, policyId, url, fetcher);

  /// Reads how [applicationId] appears in the organization unit [ouId] (by default, the unit the
  /// caller signed in to).
  Future<ResolvedOverlay> getApplicationOverlayRules(
    String applicationId, {
    String? ouId,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getOverlay(_applications, 'getApplicationOverlayRules', applicationId, ouId, url, fetcher);

  // ── Role sharing ────────────────────────────────────────────────────────

  Future<ManagementPage<SharingPolicy>> getRoleSharingPolicies(
    String roleId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getPolicies(_roles, 'getRoleSharingPolicies', roleId, limit, offset, url, fetcher);

  Future<SharingPolicy> createRoleSharingPolicy(
    String roleId,
    CreateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_roles, 'createRoleSharingPolicy', 'POST', roleId, null, payload.toJson(), url, fetcher);

  Future<SharingPolicy> getRoleSharingPolicy(
    String roleId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_roles, 'getRoleSharingPolicy', 'GET', roleId, policyId, null, url, fetcher);

  Future<SharingPolicy> updateRoleSharingPolicy(
    String roleId,
    String policyId,
    UpdateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_roles, 'updateRoleSharingPolicy', 'PUT', roleId, policyId, payload.toJson(), url, fetcher);

  Future<void> deleteRoleSharingPolicy(
    String roleId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _deletePolicy(_roles, 'deleteRoleSharingPolicy', roleId, policyId, url, fetcher);

  /// Reads how [roleId] appears in the organization unit [ouId]: whether it owns the role, the
  /// policies that reached it, and whether it may assign the role. The server requires [ouId] here.
  Future<ResolvedOverlay> getRoleOverlayRules(
    String roleId, {
    String? ouId,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getOverlay(_roles, 'getRoleOverlayRules', roleId, ouId, url, fetcher);

  // ── Flow sharing ────────────────────────────────────────────────────────

  Future<ManagementPage<SharingPolicy>> getFlowSharingPolicies(
    String flowId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getPolicies(_flows, 'getFlowSharingPolicies', flowId, limit, offset, url, fetcher);

  Future<SharingPolicy> createFlowSharingPolicy(
    String flowId,
    CreateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_flows, 'createFlowSharingPolicy', 'POST', flowId, null, payload.toJson(), url, fetcher);

  Future<SharingPolicy> getFlowSharingPolicy(
    String flowId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_flows, 'getFlowSharingPolicy', 'GET', flowId, policyId, null, url, fetcher);

  Future<SharingPolicy> updateFlowSharingPolicy(
    String flowId,
    String policyId,
    UpdateSharingPolicyRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _writePolicy(_flows, 'updateFlowSharingPolicy', 'PUT', flowId, policyId, payload.toJson(), url, fetcher);

  Future<void> deleteFlowSharingPolicy(
    String flowId,
    String policyId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _deletePolicy(_flows, 'deleteFlowSharingPolicy', flowId, policyId, url, fetcher);

  /// Reads how [flowId] appears in the organization unit [ouId]: whether it owns the flow, the
  /// policies that reached it, and the rule for each variable (keyed `variables.<identifier>`).
  /// The server requires [ouId] here.
  Future<ResolvedOverlay> getFlowOverlayRules(
    String flowId, {
    String? ouId,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _getOverlay(_flows, 'getFlowOverlayRules', flowId, ouId, url, fetcher);

  // ── Internals ──────────────────────────────────────────────────────────

  static const _Collection _users = (key: ManagementEndpointKeys.users, path: 'users', noun: 'user');
  static const _Collection _applications =
      (key: ManagementEndpointKeys.applications, path: 'applications', noun: 'application');
  static const _Collection _groups = (key: ManagementEndpointKeys.groups, path: 'groups', noun: 'group');
  static const _Collection _roles = (key: ManagementEndpointKeys.roles, path: 'roles', noun: 'role');
  static const _Collection _flows = (key: ManagementEndpointKeys.flows, path: 'flows', noun: 'flow');

  Future<ManagementPage<SharingPolicy>> _getPolicies(
    _Collection collection,
    String operation,
    String id,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  ) async =>
      ManagementPage.fromJson(
        await _send(
          collection,
          operation,
          'Failed to fetch ${collection.noun} sharing policies',
          segments: [id, 'sharing-policies'],
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'policies',
        (item) => SharingPolicy.fromJson(readMap(item)),
      );

  Future<SharingPolicy> _writePolicy(
    _Collection collection,
    String operation,
    String method,
    String id,
    String? policyId,
    Map<String, dynamic>? body,
    String? url,
    ManagementFetcher? fetcher,
  ) async {
    final verb = switch (method) { 'POST' => 'create', 'PUT' => 'update', _ => 'fetch' };
    return SharingPolicy.fromJson(
      readMap(
        await _send(
          collection,
          operation,
          'Failed to $verb ${collection.noun} sharing policy',
          method: method,
          segments: [id, 'sharing-policies', if (policyId != null) policyId],
          body: body,
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
  }

  Future<void> _deletePolicy(
    _Collection collection,
    String operation,
    String id,
    String policyId,
    String? url,
    ManagementFetcher? fetcher,
  ) =>
      _send(
        collection,
        operation,
        'Failed to delete ${collection.noun} sharing policy',
        method: 'DELETE',
        segments: [id, 'sharing-policies', policyId],
        url: url,
        fetcher: fetcher,
      );

  Future<ResolvedOverlay> _getOverlay(
    _Collection collection,
    String operation,
    String id,
    String? ouId,
    String? url,
    ManagementFetcher? fetcher,
  ) async =>
      ResolvedOverlay.fromJson(
        readMap(
          await _send(
            collection,
            operation,
            'Failed to fetch ${collection.noun} overlay rules',
            segments: [id, 'overlay-rules'],
            query: {'ouId': ouId},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Object?> _send(
    _Collection collection,
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
        endpointKey: collection.key,
        collection: collection.path,
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}

typedef _Collection = ({String key, String path, String noun});
