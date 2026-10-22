// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/management/agent.dart';
import '../models/management/group.dart';
import '../models/management/json_reader.dart';
import '../models/management/managed_user.dart';
import '../models/management/management_page.dart';
import '../models/management/role.dart';
import 'management_request.dart';
import 'management_transport.dart';

/// Keys of `ThunderIDConfig.endpoints` that override a management collection URL.
abstract final class ManagementEndpointKeys {
  static const String users = 'users';
  static const String userTypes = 'userTypes';
  static const String groups = 'groups';
  static const String roles = 'roles';
  static const String agents = 'agents';
  static const String agentTypes = 'agentTypes';
}

/// Management operations for users, groups, roles, and agents (spec "Management operations").
///
/// Every call is authorized with the signed-in user's access token through the default
/// transport; whether it succeeds is the server's decision. A failure is raised as an
/// [IAMApiException] whose `code` is `forbidden` for HTTP 403 and `notFound` for HTTP 404.
/// Nothing here shows UI, translates text, or logs (requirement 5).
///
/// Each request URL comes from, in order: the `url` passed to the call, the [endpoints]
/// override for the collection, then [baseUrl] plus the collection path. A single resource is
/// the collection URL followed by its identifier. A `fetcher` passed to a call replaces
/// [fetcher] for that call only.
///
/// Get one from `ThunderIDClient.management` or `ThunderIDProvider.of(context).management`, or
/// construct it directly for use outside the provider.
class ThunderIDManagementClient {
  final String baseUrl;

  /// Collection URL overrides keyed by [ManagementEndpointKeys].
  final Map<String, String> endpoints;

  /// The transport used when a call does not pass its own.
  final ManagementFetcher fetcher;

  ThunderIDManagementClient({
    required this.baseUrl,
    this.endpoints = const {},
    ManagementFetcher? fetcher,
    AccessTokenProvider? accessTokenProvider,
    bool allowInsecureConnections = false,
  }) : fetcher = fetcher ??
            createAuthenticatedFetcher(
              accessTokenProvider ?? _missingTokenProvider,
              allowInsecureConnections: allowInsecureConnections,
            );

  static Future<String> _missingTokenProvider() async => '';

  // ── Users ───────────────────────────────────────────────────────────────

  Future<ManagementPage<ManagedUser>> getUsers({
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getUsers',
          failureMessage: 'Failed to fetch users',
          endpointKey: ManagementEndpointKeys.users,
          collection: 'users',
          query: {'filter': filter, 'include': 'display', 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'users',
        (item) => ManagedUser.fromJson(readMap(item)),
      );

  Future<ManagedUser> getUser(String userId, {String? url, ManagementFetcher? fetcher}) async =>
      ManagedUser.fromJson(
        readMap(
          await _send(
            operation: 'getUser',
            failureMessage: 'Failed to fetch user',
            endpointKey: ManagementEndpointKeys.users,
            collection: 'users',
            id: userId,
            query: const {'include': 'display'},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ManagedUser> createUser(
    CreateManagedUserRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedUser.fromJson(
        readMap(
          await _send(
            operation: 'createUser',
            failureMessage: 'Failed to create user',
            endpointKey: ManagementEndpointKeys.users,
            collection: 'users',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ManagedUser> updateUser(
    String userId,
    UpdateManagedUserRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedUser.fromJson(
        readMap(
          await _send(
            operation: 'updateUser',
            failureMessage: 'Failed to update user',
            endpointKey: ManagementEndpointKeys.users,
            collection: 'users',
            method: 'PUT',
            id: userId,
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteUser(String userId, {String? url, ManagementFetcher? fetcher}) => _send(
        operation: 'deleteUser',
        failureMessage: 'Failed to delete user',
        endpointKey: ManagementEndpointKeys.users,
        collection: 'users',
        method: 'DELETE',
        id: userId,
        url: url,
        fetcher: fetcher,
      );

  /// Lists the groups [userId] belongs to.
  Future<ManagementPage<MembershipGroup>> getUserGroups(
    String userId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getUserGroups',
          failureMessage: 'Failed to fetch user groups',
          endpointKey: ManagementEndpointKeys.users,
          collection: 'users',
          id: userId,
          subPath: 'groups',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'groups',
        (item) => MembershipGroup.fromJson(readMap(item)),
      );

  /// Lists the user types a user can be created as.
  Future<ManagementPage<ManagedUserType>> getUserTypes({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getUserTypes',
          failureMessage: 'Failed to fetch user types',
          endpointKey: ManagementEndpointKeys.userTypes,
          collection: 'user-types',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'types',
        (item) => ManagedUserType.fromJson(readMap(item)),
      );

  // ── Groups ──────────────────────────────────────────────────────────────

  Future<ManagementPage<Group>> getGroups({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getGroups',
          failureMessage: 'Failed to fetch groups',
          endpointKey: ManagementEndpointKeys.groups,
          collection: 'groups',
          query: {'include': 'display', 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'groups',
        (item) => Group.fromJson(readMap(item)),
      );

  Future<Group> getGroup(String groupId, {String? url, ManagementFetcher? fetcher}) async =>
      Group.fromJson(
        readMap(
          await _send(
            operation: 'getGroup',
            failureMessage: 'Failed to fetch group',
            endpointKey: ManagementEndpointKeys.groups,
            collection: 'groups',
            id: groupId,
            query: const {'include': 'display'},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Group> createGroup(CreateGroupRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      Group.fromJson(
        readMap(
          await _send(
            operation: 'createGroup',
            failureMessage: 'Failed to create group',
            endpointKey: ManagementEndpointKeys.groups,
            collection: 'groups',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Group> updateGroup(
    String groupId,
    UpdateGroupRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Group.fromJson(
        readMap(
          await _send(
            operation: 'updateGroup',
            failureMessage: 'Failed to update group',
            endpointKey: ManagementEndpointKeys.groups,
            collection: 'groups',
            method: 'PUT',
            id: groupId,
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteGroup(String groupId, {String? url, ManagementFetcher? fetcher}) => _send(
        operation: 'deleteGroup',
        failureMessage: 'Failed to delete group',
        endpointKey: ManagementEndpointKeys.groups,
        collection: 'groups',
        method: 'DELETE',
        id: groupId,
        url: url,
        fetcher: fetcher,
      );

  Future<ManagementPage<GroupMember>> getGroupMembers(
    String groupId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getGroupMembers',
          failureMessage: 'Failed to fetch group members',
          endpointKey: ManagementEndpointKeys.groups,
          collection: 'groups',
          id: groupId,
          subPath: 'members',
          query: {'include': 'display', 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'members',
        GroupMember.tryFromJson,
      );

  /// Adds [members] to [groupId] without rewriting the group. Returns the updated group, or
  /// `null` when the server answers without a body.
  Future<Group?> addGroupMembers(
    String groupId,
    List<GroupMember> members, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _changeGroupMembers('addGroupMembers', 'Failed to add group members', 'members/add', groupId, members, url, fetcher);

  /// Removes [members] from [groupId]. Returns the updated group, or `null` when the server
  /// answers without a body.
  Future<Group?> removeGroupMembers(
    String groupId,
    List<GroupMember> members, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _changeGroupMembers(
        'removeGroupMembers',
        'Failed to remove group members',
        'members/remove',
        groupId,
        members,
        url,
        fetcher,
      );

  Future<Group?> _changeGroupMembers(
    String operation,
    String failureMessage,
    String subPath,
    String groupId,
    List<GroupMember> members,
    String? url,
    ManagementFetcher? fetcher,
  ) async {
    final json = await _send(
      operation: operation,
      failureMessage: failureMessage,
      endpointKey: ManagementEndpointKeys.groups,
      collection: 'groups',
      method: 'POST',
      id: groupId,
      subPath: subPath,
      body: {'members': members.map((member) => member.toJson()).toList()},
      url: url,
      fetcher: fetcher,
    );
    return json == null ? null : Group.fromJson(readMap(json));
  }

  // ── Roles ───────────────────────────────────────────────────────────────

  Future<ManagementPage<Role>> getRoles({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getRoles',
          failureMessage: 'Failed to fetch roles',
          endpointKey: ManagementEndpointKeys.roles,
          collection: 'roles',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'roles',
        (item) => Role.fromJson(readMap(item)),
      );

  Future<Role> getRole(String roleId, {String? url, ManagementFetcher? fetcher}) async => Role.fromJson(
        readMap(
          await _send(
            operation: 'getRole',
            failureMessage: 'Failed to fetch role',
            endpointKey: ManagementEndpointKeys.roles,
            collection: 'roles',
            id: roleId,
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Role> createRole(CreateRoleRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      Role.fromJson(
        readMap(
          await _send(
            operation: 'createRole',
            failureMessage: 'Failed to create role',
            endpointKey: ManagementEndpointKeys.roles,
            collection: 'roles',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Role> updateRole(
    String roleId,
    UpdateRoleRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Role.fromJson(
        readMap(
          await _send(
            operation: 'updateRole',
            failureMessage: 'Failed to update role',
            endpointKey: ManagementEndpointKeys.roles,
            collection: 'roles',
            method: 'PUT',
            id: roleId,
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteRole(String roleId, {String? url, ManagementFetcher? fetcher}) => _send(
        operation: 'deleteRole',
        failureMessage: 'Failed to delete role',
        endpointKey: ManagementEndpointKeys.roles,
        collection: 'roles',
        method: 'DELETE',
        id: roleId,
        url: url,
        fetcher: fetcher,
      );

  /// Lists who [roleId] is assigned to, optionally only assignees of [type].
  Future<ManagementPage<RoleAssignment>> getRoleAssignments(
    String roleId, {
    RoleAssigneeType? type,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getRoleAssignments',
          failureMessage: 'Failed to fetch role assignments',
          endpointKey: ManagementEndpointKeys.roles,
          collection: 'roles',
          id: roleId,
          subPath: 'assignments',
          query: {'include': 'display', 'limit': limit, 'offset': offset, 'type': type?.value},
          url: url,
          fetcher: fetcher,
        ),
        'assignments',
        RoleAssignment.tryFromJson,
      );

  /// Assigns [roleId] to [assignments] without rewriting the role.
  Future<void> addRoleAssignments(
    String roleId,
    List<RoleAssignment> assignments, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        operation: 'addRoleAssignments',
        failureMessage: 'Failed to add role assignments',
        endpointKey: ManagementEndpointKeys.roles,
        collection: 'roles',
        method: 'POST',
        id: roleId,
        subPath: 'assignments/add',
        body: {'assignments': assignments.map((assignment) => assignment.toJson()).toList()},
        url: url,
        fetcher: fetcher,
      );

  /// Removes [roleId] from [assignments].
  Future<void> removeRoleAssignments(
    String roleId,
    List<RoleAssignment> assignments, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        operation: 'removeRoleAssignments',
        failureMessage: 'Failed to remove role assignments',
        endpointKey: ManagementEndpointKeys.roles,
        collection: 'roles',
        method: 'POST',
        id: roleId,
        subPath: 'assignments/remove',
        body: {'assignments': assignments.map((assignment) => assignment.toJson()).toList()},
        url: url,
        fetcher: fetcher,
      );

  // ── Agents ──────────────────────────────────────────────────────────────

  /// [filter] narrows the page on a custom agent attribute, such as `name eq "Calendar Agent"`;
  /// [ManagementFilter.equality] builds one.
  Future<ManagementPage<Agent>> getAgents({
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getAgents',
          failureMessage: 'Failed to fetch agents',
          endpointKey: ManagementEndpointKeys.agents,
          collection: 'agents',
          query: {'filter': filter, 'include': 'display', 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'agents',
        (item) => Agent.fromJson(readMap(item)),
      );

  Future<Agent> getAgent(String agentId, {String? url, ManagementFetcher? fetcher}) async => Agent.fromJson(
        readMap(
          await _send(
            operation: 'getAgent',
            failureMessage: 'Failed to fetch agent',
            endpointKey: ManagementEndpointKeys.agents,
            collection: 'agents',
            id: agentId,
            query: const {'include': 'display'},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Agent> createAgent(CreateAgentRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      Agent.fromJson(
        readMap(
          await _send(
            operation: 'createAgent',
            failureMessage: 'Failed to create agent',
            endpointKey: ManagementEndpointKeys.agents,
            collection: 'agents',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Agent> updateAgent(
    String agentId,
    UpdateAgentRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Agent.fromJson(
        readMap(
          await _send(
            operation: 'updateAgent',
            failureMessage: 'Failed to update agent',
            endpointKey: ManagementEndpointKeys.agents,
            collection: 'agents',
            method: 'PUT',
            id: agentId,
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteAgent(String agentId, {String? url, ManagementFetcher? fetcher}) => _send(
        operation: 'deleteAgent',
        failureMessage: 'Failed to delete agent',
        endpointKey: ManagementEndpointKeys.agents,
        collection: 'agents',
        method: 'DELETE',
        id: agentId,
        url: url,
        fetcher: fetcher,
      );

  /// Lists the groups [agentId] belongs to.
  Future<ManagementPage<MembershipGroup>> getAgentGroups(
    String agentId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getAgentGroups',
          failureMessage: 'Failed to fetch agent groups',
          endpointKey: ManagementEndpointKeys.agents,
          collection: 'agents',
          id: agentId,
          subPath: 'groups',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'groups',
        (item) => MembershipGroup.fromJson(readMap(item)),
      );

  /// Lists the names of the roles assigned to [agentId].
  Future<ManagementPage<String>> getAgentRoles(
    String agentId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getAgentRoles',
          failureMessage: 'Failed to fetch agent roles',
          endpointKey: ManagementEndpointKeys.agents,
          collection: 'agents',
          id: agentId,
          subPath: 'roles',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'roles',
        (item) => item is String ? item : null,
      );

  /// Lists the agent types an agent can be registered as.
  Future<ManagementPage<AgentType>> getAgentTypes({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getAgentTypes',
          failureMessage: 'Failed to fetch agent types',
          endpointKey: ManagementEndpointKeys.agentTypes,
          collection: 'agent-types',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'types',
        (item) => AgentType.fromJson(readMap(item)),
      );

  // ── Internals ───────────────────────────────────────────────────────────

  Future<Object?> _send({
    required String operation,
    required String failureMessage,
    required String endpointKey,
    required String collection,
    String method = 'GET',
    String? id,
    String? subPath,
    Map<String, Object?> query = const {},
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    final collectionUrl = url ?? endpoints[endpointKey] ?? '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$collection';
    final resolved = buildManagementUrl(operation, collectionUrl, id: id, subPath: subPath, query: query);
    return sendManagementRequest(
      fetcher: fetcher ?? this.fetcher,
      operation: operation,
      failureMessage: failureMessage,
      method: method,
      url: resolved,
      body: body,
    );
  }
}
