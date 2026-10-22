// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../management/management_transport.dart';
import '../management/thunderid_management_client.dart';
import '../models/management/agent.dart';
import '../models/management/group.dart';
import '../models/management/managed_user.dart';
import '../models/management/management_page.dart';
import '../models/management/role.dart';
import 'resource_notifiers.dart';

/// Query key prefixes, shared with the React SDK so invalidation behaves the same way.
abstract final class ManagementQueryKeys {
  static const String user = 'user';
  static const String users = 'users';
  static const String userTypes = 'user-types';
  static const String group = 'group';
  static const String groups = 'groups';
  static const String groupMembers = 'group-members';
  static const String memberships = 'group-memberships';
  static const String role = 'role';
  static const String roles = 'roles';
  static const String roleAssignments = 'role-assignments';
  static const String agent = 'agent';
  static const String agents = 'agents';
  static const String agentTypes = 'agent-types';
}

/// Variables of [ManagementResources.updateUserMutation].
typedef UpdateUserVariables = ({String userId, UpdateManagedUserRequest data});

/// Variables of [ManagementResources.updateGroupMutation].
typedef UpdateGroupVariables = ({String groupId, UpdateGroupRequest data});

/// Variables of the group member mutations.
typedef GroupMembersVariables = ({String groupId, List<GroupMember> members});

/// Variables of [ManagementResources.updateRoleMutation].
typedef UpdateRoleVariables = ({String roleId, UpdateRoleRequest data});

/// Variables of the role assignment mutations.
typedef RoleAssignmentsVariables = ({String roleId, List<RoleAssignment> assignments});

/// Variables of [ManagementResources.updateAgentMutation].
typedef UpdateAgentVariables = ({String agentId, UpdateAgentRequest data});

/// The state layer over [ThunderIDManagementClient]: each method returns a [ResourceQuery] or
/// [ResourceMutation] for one management operation, the Flutter counterpart of the React SDK's
/// hooks (`useGetUsers` is [usersQuery], `useCreateUser` is [createUserMutation], and so on).
///
/// Queries and mutations created from the same instance share one [invalidator], so a write
/// reloads every live read it affects. Callers own what they create and must dispose it.
/// Obtain the provider's instance from `ThunderIDProvider.of(context).managementResources`.
class ManagementResources {
  final ThunderIDManagementClient client;
  final ResourceInvalidator invalidator;

  ManagementResources(this.client, {ResourceInvalidator? invalidator})
      : invalidator = invalidator ?? ResourceInvalidator();

  ResourceQuery<T> _query<T>(ResourceQueryKey key, Future<T> Function() fetch, bool enabled) =>
      ResourceQuery<T>(fetch, key: key, invalidator: invalidator, enabled: enabled);

  ResourceMutation<V, R> _mutation<V, R>(
    Future<R> Function(V variables) mutate,
    List<ResourceQueryKey> Function(V variables) invalidates,
    void Function(R data, V variables)? onSuccess,
    void Function(Object error, V variables)? onError,
  ) =>
      ResourceMutation<V, R>(
        mutate,
        invalidates: invalidates,
        invalidator: invalidator,
        onSuccess: onSuccess,
        onError: onError,
      );

  // ── Users ───────────────────────────────────────────────────────────────

  ResourceQuery<ManagementPage<ManagedUser>> usersQuery({
    String? filter,
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.users, {'filter': filter, 'limit': limit, 'offset': offset}],
        () => client.getUsers(filter: filter, limit: limit, offset: offset, fetcher: fetcher),
        enabled,
      );

  ResourceQuery<ManagedUser> userQuery(String? userId, {bool enabled = true, ManagementFetcher? fetcher}) =>
      _query(
        [ManagementQueryKeys.user, userId],
        () => client.getUser(userId!, fetcher: fetcher),
        enabled && userId != null,
      );

  ResourceQuery<ManagementPage<MembershipGroup>> userGroupsQuery(
    String? userId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.memberships, 'user', userId, {'limit': limit, 'offset': offset}],
        () => client.getUserGroups(userId!, limit: limit, offset: offset, fetcher: fetcher),
        enabled && userId != null,
      );

  ResourceQuery<ManagementPage<ManagedUserType>> userTypesQuery({
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.userTypes, {'limit': limit, 'offset': offset}],
        () => client.getUserTypes(limit: limit, offset: offset, fetcher: fetcher),
        enabled,
      );

  ResourceMutation<CreateManagedUserRequest, ManagedUser> createUserMutation({
    void Function(ManagedUser data, CreateManagedUserRequest variables)? onSuccess,
    void Function(Object error, CreateManagedUserRequest variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (CreateManagedUserRequest payload) => client.createUser(payload, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.users],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<UpdateUserVariables, ManagedUser> updateUserMutation({
    void Function(ManagedUser data, UpdateUserVariables variables)? onSuccess,
    void Function(Object error, UpdateUserVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (UpdateUserVariables v) => client.updateUser(v.userId, v.data, fetcher: fetcher),
        (UpdateUserVariables v) => [
          [ManagementQueryKeys.user, v.userId],
          [ManagementQueryKeys.users],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<String, void> deleteUserMutation({
    void Function(void data, String userId)? onSuccess,
    void Function(Object error, String userId)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (String userId) => client.deleteUser(userId, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.users],
        ],
        onSuccess,
        onError,
      );

  // ── Groups ──────────────────────────────────────────────────────────────

  ResourceQuery<ManagementPage<Group>> groupsQuery({
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.groups, {'limit': limit, 'offset': offset}],
        () => client.getGroups(limit: limit, offset: offset, fetcher: fetcher),
        enabled,
      );

  ResourceQuery<Group> groupQuery(String? groupId, {bool enabled = true, ManagementFetcher? fetcher}) => _query(
        [ManagementQueryKeys.group, groupId],
        () => client.getGroup(groupId!, fetcher: fetcher),
        enabled && groupId != null,
      );

  ResourceQuery<ManagementPage<GroupMember>> groupMembersQuery(
    String? groupId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.groupMembers, groupId, {'limit': limit, 'offset': offset}],
        () => client.getGroupMembers(groupId!, limit: limit, offset: offset, fetcher: fetcher),
        enabled && groupId != null,
      );

  ResourceMutation<CreateGroupRequest, Group> createGroupMutation({
    void Function(Group data, CreateGroupRequest variables)? onSuccess,
    void Function(Object error, CreateGroupRequest variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (CreateGroupRequest payload) => client.createGroup(payload, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.groups],
          [ManagementQueryKeys.memberships],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<UpdateGroupVariables, Group> updateGroupMutation({
    void Function(Group data, UpdateGroupVariables variables)? onSuccess,
    void Function(Object error, UpdateGroupVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (UpdateGroupVariables v) => client.updateGroup(v.groupId, v.data, fetcher: fetcher),
        (UpdateGroupVariables v) => [
          [ManagementQueryKeys.group, v.groupId],
          [ManagementQueryKeys.groups],
          [ManagementQueryKeys.memberships],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<String, void> deleteGroupMutation({
    void Function(void data, String groupId)? onSuccess,
    void Function(Object error, String groupId)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (String groupId) => client.deleteGroup(groupId, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.groups],
          [ManagementQueryKeys.memberships],
          [ManagementQueryKeys.roleAssignments],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<GroupMembersVariables, Group?> addGroupMembersMutation({
    void Function(Group? data, GroupMembersVariables variables)? onSuccess,
    void Function(Object error, GroupMembersVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (GroupMembersVariables v) => client.addGroupMembers(v.groupId, v.members, fetcher: fetcher),
        _groupMembershipKeys,
        onSuccess,
        onError,
      );

  ResourceMutation<GroupMembersVariables, Group?> removeGroupMembersMutation({
    void Function(Group? data, GroupMembersVariables variables)? onSuccess,
    void Function(Object error, GroupMembersVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (GroupMembersVariables v) => client.removeGroupMembers(v.groupId, v.members, fetcher: fetcher),
        _groupMembershipKeys,
        onSuccess,
        onError,
      );

  static List<ResourceQueryKey> _groupMembershipKeys(GroupMembersVariables v) => [
        [ManagementQueryKeys.group, v.groupId],
        [ManagementQueryKeys.groupMembers, v.groupId],
        [ManagementQueryKeys.memberships],
        [ManagementQueryKeys.roleAssignments],
      ];

  // ── Roles ───────────────────────────────────────────────────────────────

  ResourceQuery<ManagementPage<Role>> rolesQuery({
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.roles, {'limit': limit, 'offset': offset}],
        () => client.getRoles(limit: limit, offset: offset, fetcher: fetcher),
        enabled,
      );

  ResourceQuery<Role> roleQuery(String? roleId, {bool enabled = true, ManagementFetcher? fetcher}) => _query(
        [ManagementQueryKeys.role, roleId],
        () => client.getRole(roleId!, fetcher: fetcher),
        enabled && roleId != null,
      );

  ResourceQuery<ManagementPage<RoleAssignment>> roleAssignmentsQuery(
    String? roleId, {
    RoleAssigneeType? type,
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [
          ManagementQueryKeys.roleAssignments,
          roleId,
          {'limit': limit, 'offset': offset, 'type': type?.value},
        ],
        () => client.getRoleAssignments(roleId!, type: type, limit: limit, offset: offset, fetcher: fetcher),
        enabled && roleId != null,
      );

  ResourceMutation<CreateRoleRequest, Role> createRoleMutation({
    void Function(Role data, CreateRoleRequest variables)? onSuccess,
    void Function(Object error, CreateRoleRequest variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (CreateRoleRequest payload) => client.createRole(payload, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.roles],
          [ManagementQueryKeys.roleAssignments],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<UpdateRoleVariables, Role> updateRoleMutation({
    void Function(Role data, UpdateRoleVariables variables)? onSuccess,
    void Function(Object error, UpdateRoleVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (UpdateRoleVariables v) => client.updateRole(v.roleId, v.data, fetcher: fetcher),
        (UpdateRoleVariables v) => [
          [ManagementQueryKeys.role, v.roleId],
          [ManagementQueryKeys.roles],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<String, void> deleteRoleMutation({
    void Function(void data, String roleId)? onSuccess,
    void Function(Object error, String roleId)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (String roleId) => client.deleteRole(roleId, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.roles],
          [ManagementQueryKeys.roleAssignments],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<RoleAssignmentsVariables, void> addRoleAssignmentsMutation({
    void Function(void data, RoleAssignmentsVariables variables)? onSuccess,
    void Function(Object error, RoleAssignmentsVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (RoleAssignmentsVariables v) => client.addRoleAssignments(v.roleId, v.assignments, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.roleAssignments],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<RoleAssignmentsVariables, void> removeRoleAssignmentsMutation({
    void Function(void data, RoleAssignmentsVariables variables)? onSuccess,
    void Function(Object error, RoleAssignmentsVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (RoleAssignmentsVariables v) => client.removeRoleAssignments(v.roleId, v.assignments, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.roleAssignments],
        ],
        onSuccess,
        onError,
      );

  // ── Agents ──────────────────────────────────────────────────────────────

  ResourceQuery<ManagementPage<Agent>> agentsQuery({
    String? filter,
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.agents, {'filter': filter, 'limit': limit, 'offset': offset}],
        () => client.getAgents(filter: filter, limit: limit, offset: offset, fetcher: fetcher),
        enabled,
      );

  ResourceQuery<Agent> agentQuery(String? agentId, {bool enabled = true, ManagementFetcher? fetcher}) => _query(
        [ManagementQueryKeys.agent, agentId],
        () => client.getAgent(agentId!, fetcher: fetcher),
        enabled && agentId != null,
      );

  ResourceQuery<ManagementPage<MembershipGroup>> agentGroupsQuery(
    String? agentId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.memberships, 'agent', agentId, {'limit': limit, 'offset': offset}],
        () => client.getAgentGroups(agentId!, limit: limit, offset: offset, fetcher: fetcher),
        enabled && agentId != null,
      );

  ResourceQuery<ManagementPage<String>> agentRolesQuery(
    String? agentId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.roleAssignments, 'agent', agentId, {'limit': limit, 'offset': offset}],
        () => client.getAgentRoles(agentId!, limit: limit, offset: offset, fetcher: fetcher),
        enabled && agentId != null,
      );

  ResourceQuery<ManagementPage<AgentType>> agentTypesQuery({
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) =>
      _query(
        [ManagementQueryKeys.agentTypes, {'limit': limit, 'offset': offset}],
        () => client.getAgentTypes(limit: limit, offset: offset, fetcher: fetcher),
        enabled,
      );

  ResourceMutation<CreateAgentRequest, Agent> createAgentMutation({
    void Function(Agent data, CreateAgentRequest variables)? onSuccess,
    void Function(Object error, CreateAgentRequest variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (CreateAgentRequest payload) => client.createAgent(payload, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.agents],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<UpdateAgentVariables, Agent> updateAgentMutation({
    void Function(Agent data, UpdateAgentVariables variables)? onSuccess,
    void Function(Object error, UpdateAgentVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (UpdateAgentVariables v) => client.updateAgent(v.agentId, v.data, fetcher: fetcher),
        (UpdateAgentVariables v) => [
          [ManagementQueryKeys.agent, v.agentId],
          [ManagementQueryKeys.agents],
        ],
        onSuccess,
        onError,
      );

  ResourceMutation<String, void> deleteAgentMutation({
    void Function(void data, String agentId)? onSuccess,
    void Function(Object error, String agentId)? onError,
    ManagementFetcher? fetcher,
  }) =>
      _mutation(
        (String agentId) => client.deleteAgent(agentId, fetcher: fetcher),
        (_) => [
          [ManagementQueryKeys.agents],
        ],
        onSuccess,
        onError,
      );
}
