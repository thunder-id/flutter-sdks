// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../models/management/administration.dart';
import '../models/management/agent.dart';
import '../models/management/application.dart';
import '../models/management/entity_type.dart';
import '../models/management/group.dart';
import '../models/management/json_reader.dart';
import '../models/management/managed_user.dart';
import '../models/management/management_page.dart';
import '../models/management/role.dart';
import '../models/thunderid_error.dart';
import 'administration_flows.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'secrets.dart';

/// Keys of `ThunderIDConfig.endpoints` that override a management collection URL.
abstract final class ManagementEndpointKeys {
  static const String users = 'users';
  static const String userTypes = 'userTypes';
  static const String groups = 'groups';
  static const String roles = 'roles';
  static const String agents = 'agents';
  static const String agentTypes = 'agentTypes';
  static const String applications = 'applications';
  static const String organizationUnits = 'organizationUnits';
  static const String resourceServers = 'resourceServers';
  static const String connections = 'connections';
  static const String flows = 'flows';
  static const String notificationTemplates = 'notificationTemplates';
  static const String design = 'design';
  static const String i18n = 'i18n';
  static const String serverConfig = 'serverConfig';
  static const String gateways = 'gateways';
  static const String variables = 'variables';
  static const String secrets = 'secrets';
  static const String configurationVersions = 'configurationVersions';
  static const String import = 'import';
  static const String export = 'export';

  /// Every key, in the order above.
  static const List<String> values = [
    users,
    userTypes,
    groups,
    roles,
    agents,
    agentTypes,
    applications,
    organizationUnits,
    resourceServers,
    connections,
    flows,
    notificationTemplates,
    design,
    i18n,
    serverConfig,
    gateways,
    variables,
    secrets,
    configurationVersions,
    import,
    export,
  ];
}

/// Management operations for users, user types, groups, roles, agents, agent types, and
/// applications (spec "Management operations").
///
/// Every call is authorized with the signed-in user's access token through the default
/// transport; whether it succeeds is the server's decision. A failure is raised as an
/// [IAMApiException] whose `code` is `forbidden` for HTTP 403 and `notFound` for HTTP 404, and
/// whose [IAMApiException.serverError] carries the server's own error code and message when the
/// response body is the server's error envelope. Nothing here shows UI, translates text, or logs
/// (requirement 5).
///
/// The operations that revoke something (deleting a user, group, role, or application, removing
/// group members, role assignments, or role permissions, and regenerating a client secret) take
/// an `administrationMode`. [AdministrationMode.native], the default, calls the API directly.
/// [AdministrationMode.flow] runs the administration flow the server configures for the operation
/// instead (see [AdministrationFlowOperations]), and calls the API directly only when no flow is
/// configured. A flow that does not complete raises an [AdministrationFlowError]; running one
/// needs [baseUrl], since the flows live on the server rather than under a collection URL.
///
/// Each request URL comes from, in order: the `url` passed to the call, the [endpoints]
/// override for the collection, then [baseUrl] plus the collection path. A single resource is
/// the collection URL followed by its identifier. A `fetcher` passed to a call replaces
/// [fetcher] for that call only.
///
/// The other resource families are extensions on this class, one file each and all exported
/// with it: [AdministrationFlowOperations] and the account lifecycle, organization unit, resource
/// server, connection, flow, notification template, design, translation, server configuration,
/// gateway, variable and secret, configuration versioning/import/export, and user/application
/// sharing operations.
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

  /// Deletes a user. In [AdministrationMode.flow] the configured user deletion flow runs instead,
  /// revoking the user's grants and ending their sessions before the record goes.
  Future<void> deleteUser(
    String userId, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow &&
        await runAdministrationFlow(
              AdministrationFlowConfigKey.userDeletion,
              {AdministrationFlowInput.subject: userId},
              action: 'user deletion',
              fetcher: fetcher,
            ) !=
            null) {
      return;
    }
    await _send(
      operation: 'deleteUser',
      failureMessage: 'Failed to delete user',
      endpointKey: ManagementEndpointKeys.users,
      collection: 'users',
      method: 'DELETE',
      id: userId,
      url: url,
      fetcher: fetcher,
    );
  }

  /// Lists the resources that reference [userId], such as agents that name the user as their
  /// owner, and what happens to each when the user is deleted.
  Future<UserUsages> getUserUsages(String userId, {String? url, ManagementFetcher? fetcher}) async =>
      UserUsages.fromJson(
        readMap(
          await _send(
            operation: 'getUserUsages',
            failureMessage: 'Failed to fetch user usages',
            endpointKey: ManagementEndpointKeys.users,
            collection: 'users',
            id: userId,
            subPath: 'usages',
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Sets new values for some of [userId]'s credential attributes, such as the password.
  Future<void> updateUserCredentials(
    String userId,
    UpdateUserCredentialsRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        operation: 'updateUserCredentials',
        failureMessage: 'Failed to update user credentials',
        endpointKey: ManagementEndpointKeys.users,
        collection: 'users',
        method: 'POST',
        id: userId,
        subPath: 'update-credentials',
        body: payload.toJson(),
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

  // ── User types ──────────────────────────────────────────────────────────

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
          query: {'include': 'display', 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'types',
        (item) => ManagedUserType.fromJson(readMap(item)),
      );

  /// Reads a user type with its attribute schema.
  Future<ManagedUserTypeDetails> getUserType(String userTypeId, {String? url, ManagementFetcher? fetcher}) async =>
      ManagedUserTypeDetails.fromJson(
        readMap(
          await _send(
            operation: 'getUserType',
            failureMessage: 'Failed to fetch user type',
            endpointKey: ManagementEndpointKeys.userTypes,
            collection: 'user-types',
            id: userTypeId,
            query: const {'include': 'display'},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ManagedUserTypeDetails> createUserType(
    CreateUserTypeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedUserTypeDetails.fromJson(
        readMap(
          await _send(
            operation: 'createUserType',
            failureMessage: 'Failed to create user type',
            endpointKey: ManagementEndpointKeys.userTypes,
            collection: 'user-types',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ManagedUserTypeDetails> updateUserType(
    String userTypeId,
    UpdateUserTypeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedUserTypeDetails.fromJson(
        readMap(
          await _send(
            operation: 'updateUserType',
            failureMessage: 'Failed to update user type',
            endpointKey: ManagementEndpointKeys.userTypes,
            collection: 'user-types',
            method: 'PUT',
            id: userTypeId,
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteUserType(String userTypeId, {String? url, ManagementFetcher? fetcher}) => _send(
        operation: 'deleteUserType',
        failureMessage: 'Failed to delete user type',
        endpointKey: ManagementEndpointKeys.userTypes,
        collection: 'user-types',
        method: 'DELETE',
        id: userTypeId,
        url: url,
        fetcher: fetcher,
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

  /// Deletes a group. In [AdministrationMode.flow] the configured group deletion flow runs
  /// instead, revoking what the group's members held through it before the group goes.
  Future<void> deleteGroup(
    String groupId, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow &&
        await runAdministrationFlow(
              AdministrationFlowConfigKey.groupDeletion,
              {AdministrationFlowInput.group: groupId},
              action: 'group deletion',
              fetcher: fetcher,
            ) !=
            null) {
      return;
    }
    await _send(
      operation: 'deleteGroup',
      failureMessage: 'Failed to delete group',
      endpointKey: ManagementEndpointKeys.groups,
      collection: 'groups',
      method: 'DELETE',
      id: groupId,
      url: url,
      fetcher: fetcher,
    );
  }

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
  ///
  /// In [AdministrationMode.flow] the configured membership removal flow runs once for each
  /// member instead, revoking what the member held through the group, and the group is read
  /// afterwards.
  Future<Group?> removeGroupMembers(
    String groupId,
    List<GroupMember> members, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow) {
      const action = 'group membership removal';
      final flowId = await resolveAdministrationFlowId(
        AdministrationFlowConfigKey.groupMembershipRemoval,
        action: action,
        fetcher: fetcher,
      );
      if (flowId != null) {
        for (final member in members) {
          await executeAdministrationFlow(
            flowId,
            {AdministrationFlowInput.group: groupId, AdministrationFlowInput.member: member.id},
            action: action,
            fetcher: fetcher,
          );
        }
        return getGroup(groupId, url: url, fetcher: fetcher);
      }
    }
    return _changeGroupMembers(
        'removeGroupMembers',
      'Failed to remove group members',
      'members/remove',
      groupId,
      members,
      url,
      fetcher,
    );
  }

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
          query: {'include': 'display', 'limit': limit, 'offset': offset},
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
            query: const {'include': 'display'},
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

  /// Updates a role.
  ///
  /// In [AdministrationMode.flow] an update that removes a permission runs the configured
  /// permission removal flow, which revokes the scopes the permissions granted; the role's other
  /// fields are written first, so a rejected rename fails before anything is revoked. [current]
  /// is the role as it is now, used to tell whether the update removes a permission; when it is
  /// left out, the role is read first.
  Future<Role> updateRole(
    String roleId,
    UpdateRoleRequest payload, {
    AdministrationMode administrationMode = AdministrationMode.native,
    Role? current,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    Future<Role> put(UpdateRoleRequest body) async => Role.fromJson(
          readMap(
            await _send(
              operation: 'updateRole',
              failureMessage: 'Failed to update role',
              endpointKey: ManagementEndpointKeys.roles,
              collection: 'roles',
              method: 'PUT',
              id: roleId,
              body: body.toJson(),
              url: url,
              fetcher: fetcher,
            ),
          ),
        );

    if (administrationMode != AdministrationMode.flow) return put(payload);

    final before = current ?? await getRole(roleId, url: url, fetcher: fetcher);
    if (!_removesPermission(before.permissions, payload.permissions)) return put(payload);

    const action = 'role permission change';
    final flowId = await resolveAdministrationFlowId(
      AdministrationFlowConfigKey.rolePermissionRemoval,
      action: action,
      fetcher: fetcher,
    );
    if (flowId == null) return put(payload);

    // The flow writes only the permissions, so the other fields go first.
    final otherFieldsChanged = payload.name != before.name ||
        (payload.description ?? '') != (before.description ?? '') ||
        payload.ouId != before.ouId;
    final updated = otherFieldsChanged
        ? await put(
            UpdateRoleRequest(
              name: payload.name,
              ouId: payload.ouId,
              description: payload.description,
              permissions: before.permissions,
            ),
          )
        : before;

    await executeAdministrationFlow(
      flowId,
      {
        AdministrationFlowInput.permissions: jsonEncode(payload.permissions.map((entry) => entry.toJson()).toList()),
        AdministrationFlowInput.role: roleId,
      },
      action: action,
      fetcher: fetcher,
    );

    return Role(
      id: updated.id,
      name: updated.name,
      ouId: updated.ouId,
      ouHandle: updated.ouHandle,
      description: updated.description,
      isReadOnly: updated.isReadOnly,
      permissions: payload.permissions,
    );
  }

  /// Whether [next] drops any of the [current] permissions. Only a removal has anything to revoke.
  static bool _removesPermission(List<RoleResourcePermissions> current, List<RoleResourcePermissions> next) {
    final retained = {
      for (final resource in next)
        for (final permission in resource.permissions) '${resource.resourceServerId}\u0000$permission',
    };
    return current.any(
      (resource) => resource.permissions.any(
        (permission) => !retained.contains('${resource.resourceServerId}\u0000$permission'),
      ),
    );
  }

  /// Deletes a role. In [AdministrationMode.flow] the configured role deletion flow runs instead,
  /// revoking the scopes the role granted before it goes.
  Future<void> deleteRole(
    String roleId, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow &&
        await runAdministrationFlow(
              AdministrationFlowConfigKey.roleDeletion,
              {AdministrationFlowInput.role: roleId},
              action: 'role deletion',
              fetcher: fetcher,
            ) !=
            null) {
      return;
    }
    await _send(
      operation: 'deleteRole',
      failureMessage: 'Failed to delete role',
      endpointKey: ManagementEndpointKeys.roles,
      collection: 'roles',
      method: 'DELETE',
      id: roleId,
      url: url,
      fetcher: fetcher,
    );
  }

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

  /// Removes [roleId] from [assignments]. In [AdministrationMode.flow] the configured assignment
  /// removal flow runs once for each assignee instead, revoking the scopes the assignment
  /// conveyed.
  Future<void> removeRoleAssignments(
    String roleId,
    List<RoleAssignment> assignments, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow) {
      const action = 'role assignment removal';
      final flowId = await resolveAdministrationFlowId(
        AdministrationFlowConfigKey.roleAssignmentRemoval,
        action: action,
        fetcher: fetcher,
      );
      if (flowId != null) {
        for (final assignment in assignments) {
          await executeAdministrationFlow(
            flowId,
            {AdministrationFlowInput.assignee: assignment.id, AdministrationFlowInput.role: roleId},
            action: action,
            fetcher: fetcher,
          );
        }
        return;
      }
    }
    await _send(
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
  }

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

  /// Gives [agentId]'s OAuth client a new secret, generated here and saved on the agent.
  ///
  /// Raises [ThunderIDErrorCode.invalidInput] and saves nothing when the agent has no OAuth
  /// client. The update restates the agent as the server returned it, without the server-set `id`
  /// and `clientId` and the display-only `ouHandle` and `display`, and with `delegated` derived
  /// from the OAuth client's grant types, since the server does not store that flag.
  Future<RegenerateAgentSecretResult> regenerateAgentSecret(
    String agentId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'regenerateAgentSecret';
    final current = readMap(
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
    )..removeWhere((key, _) => key == 'id' || key == 'clientId' || key == 'ouHandle' || key == 'display');
    final inboundAuthConfig = readList(current, 'inboundAuthConfig');
    if (!_hasOAuthClient(inboundAuthConfig)) {
      throw const IAMException(
        ThunderIDErrorCode.invalidInput,
        '$operation: the agent has no OAuth client, so it has no client secret to regenerate.',
      );
    }

    final clientSecret = generateSecret();
    final updatedInboundAuthConfig = _withClientSecret(
      inboundAuthConfig,
      clientSecret,
      emptyConfig: const {'grantTypes': <String>[], 'responseTypes': <String>[]},
    );
    final agent = Agent.fromJson(
      readMap(
        await _send(
          operation: 'updateAgent',
          failureMessage: 'Failed to update agent',
          endpointKey: ManagementEndpointKeys.agents,
          collection: 'agents',
          method: 'PUT',
          id: agentId,
          body: {
            ...current,
            'delegated': isDelegatedAgent(updatedInboundAuthConfig),
            'inboundAuthConfig': updatedInboundAuthConfig,
          },
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
    return RegenerateAgentSecretResult(agent: agent, clientSecret: clientSecret);
  }

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

  // ── Agent types ─────────────────────────────────────────────────────────

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
          query: {'include': 'display', 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'types',
        (item) => AgentType.fromJson(readMap(item)),
      );

  /// Reads an agent type with its attribute schema.
  Future<AgentTypeDetails> getAgentType(String agentTypeId, {String? url, ManagementFetcher? fetcher}) async =>
      AgentTypeDetails.fromJson(
        readMap(
          await _send(
            operation: 'getAgentType',
            failureMessage: 'Failed to fetch agent type',
            endpointKey: ManagementEndpointKeys.agentTypes,
            collection: 'agent-types',
            id: agentTypeId,
            query: const {'include': 'display'},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<AgentTypeDetails> createAgentType(
    CreateAgentTypeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      AgentTypeDetails.fromJson(
        readMap(
          await _send(
            operation: 'createAgentType',
            failureMessage: 'Failed to create agent type',
            endpointKey: ManagementEndpointKeys.agentTypes,
            collection: 'agent-types',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<AgentTypeDetails> updateAgentType(
    String agentTypeId,
    UpdateAgentTypeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      AgentTypeDetails.fromJson(
        readMap(
          await _send(
            operation: 'updateAgentType',
            failureMessage: 'Failed to update agent type',
            endpointKey: ManagementEndpointKeys.agentTypes,
            collection: 'agent-types',
            method: 'PUT',
            id: agentTypeId,
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteAgentType(String agentTypeId, {String? url, ManagementFetcher? fetcher}) => _send(
        operation: 'deleteAgentType',
        failureMessage: 'Failed to delete agent type',
        endpointKey: ManagementEndpointKeys.agentTypes,
        collection: 'agent-types',
        method: 'DELETE',
        id: agentTypeId,
        url: url,
        fetcher: fetcher,
      );

  // ── Applications ────────────────────────────────────────────────────────

  Future<ManagementPage<BasicApplication>> getApplications({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          operation: 'getApplications',
          failureMessage: 'Failed to fetch applications',
          endpointKey: ManagementEndpointKeys.applications,
          collection: 'applications',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'applications',
        (item) => BasicApplication.fromJson(readMap(item)),
      );

  Future<Application> getApplication(String applicationId, {String? url, ManagementFetcher? fetcher}) async =>
      Application.fromJson(await _getApplicationJson(applicationId, url, fetcher));

  Future<Application> createApplication(
    CreateApplicationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Application.fromJson(
        readMap(
          await _send(
            operation: 'createApplication',
            failureMessage: 'Failed to create application',
            endpointKey: ManagementEndpointKeys.applications,
            collection: 'applications',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Replaces [applicationId]'s settable fields with [payload]. An [Application] read from the
  /// server can be passed as it is: its `toJson` leaves out the server-set fields and keeps the
  /// fields this SDK does not model.
  Future<Application> updateApplication(
    String applicationId,
    UpdateApplicationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Application.fromJson(await _putApplication(applicationId, payload.toJson(), url, fetcher));

  /// Deletes an application. In [AdministrationMode.flow] the configured application deletion
  /// flow runs instead, revoking what the application was granted before the record goes.
  Future<void> deleteApplication(
    String applicationId, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow &&
        await runAdministrationFlow(
              AdministrationFlowConfigKey.applicationDeletion,
              {AdministrationFlowInput.application: applicationId},
              action: 'application deletion',
              fetcher: fetcher,
            ) !=
            null) {
      return;
    }
    await _send(
      operation: 'deleteApplication',
      failureMessage: 'Failed to delete application',
      endpointKey: ManagementEndpointKeys.applications,
      collection: 'applications',
      method: 'DELETE',
      id: applicationId,
      url: url,
      fetcher: fetcher,
    );
  }

  /// Gives [applicationId] a new OAuth client secret.
  ///
  /// In [AdministrationMode.flow] the configured secret regeneration flow rotates it, revoking
  /// what the old secret was used for, and the result carries no application; a flow that returns
  /// no secret raises an [AdministrationFlowError]. Otherwise a new secret is generated here and
  /// saved on the application, which is restated as the server returned it, without the
  /// server-set `id`, `createdAt` and `updatedAt`. An application with no OAuth client raises
  /// [ThunderIDErrorCode.invalidInput] and nothing is saved.
  Future<RegenerateClientSecretResult> regenerateClientSecret(
    String applicationId, {
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'regenerateClientSecret';
    if (administrationMode == AdministrationMode.flow) {
      final result = await runAdministrationFlow(
        AdministrationFlowConfigKey.secretRegeneration,
        {AdministrationFlowInput.application: applicationId},
        action: 'client secret regeneration',
        fetcher: fetcher,
      );
      if (result != null) {
        final clientSecret = result[AdministrationFlowData.clientSecret];
        if (clientSecret == null || clientSecret.isEmpty) {
          throw const AdministrationFlowError(
            'The client secret regeneration flow completed without returning a secret.',
            '$operation-FlowError-001',
          );
        }
        return RegenerateClientSecretResult(clientSecret: clientSecret);
      }
    }

    final current = await _readApplicationForUpdate(applicationId, url, fetcher);
    final inboundAuthConfig = readList(current, 'inboundAuthConfig');
    if (!_hasOAuthClient(inboundAuthConfig)) {
      throw const IAMException(
        ThunderIDErrorCode.invalidInput,
        '$operation: the application has no OAuth client, so it has no client secret to regenerate.',
      );
    }

    final clientSecret = generateSecret();
    final application = await _putApplication(
      applicationId,
      {...current, 'inboundAuthConfig': _withClientSecret(inboundAuthConfig, clientSecret)},
      url,
      fetcher,
    );
    return RegenerateClientSecretResult(clientSecret: clientSecret, application: Application.fromJson(application));
  }

  /// Gives [applicationId] a new flow secret, generated here and saved on the application.
  Future<RegenerateFlowSecretResult> regenerateFlowSecret(
    String applicationId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    final current = await _readApplicationForUpdate(applicationId, url, fetcher);
    final flowSecret = generateSecret();
    final application = await _putApplication(applicationId, {...current, 'flowSecret': flowSecret}, url, fetcher);
    return RegenerateFlowSecretResult(flowSecret: flowSecret, application: Application.fromJson(application));
  }

  /// Reads a client ID metadata document (CIMD) through the server and returns what it declares,
  /// so an application can be registered from it. [clientId] is the URL of the document.
  ///
  /// The preview is a server endpoint of its own, not part of a collection, so it always goes to
  /// `{baseUrl}/cimd/preview`; the applications endpoint override does not apply.
  Future<CimdPreviewResponse> previewCimdDocument(String clientId, {ManagementFetcher? fetcher}) async =>
      CimdPreviewResponse.fromJson(
        readMap(
          await _send(
            operation: 'previewCimdDocument',
            failureMessage: 'Failed to read the client ID metadata document',
            collection: 'cimd',
            method: 'POST',
            id: 'preview',
            body: {'clientId': clientId},
            fetcher: fetcher,
          ),
        ),
      );

  /// Reads an application as the server returned it, without the fields the server sets, so it
  /// can go back in a full update unchanged.
  Future<Map<String, dynamic>> _readApplicationForUpdate(
    String applicationId,
    String? url,
    ManagementFetcher? fetcher,
  ) async =>
      (await _getApplicationJson(applicationId, url, fetcher))
        ..removeWhere((key, _) => key == 'id' || key == 'createdAt' || key == 'updatedAt');

  Future<Map<String, dynamic>> _getApplicationJson(
    String applicationId,
    String? url,
    ManagementFetcher? fetcher,
  ) async =>
      readMap(
        await _send(
          operation: 'getApplication',
          failureMessage: 'Failed to fetch application',
          endpointKey: ManagementEndpointKeys.applications,
          collection: 'applications',
          id: applicationId,
          url: url,
          fetcher: fetcher,
        ),
      );

  Future<Map<String, dynamic>> _putApplication(
    String applicationId,
    Map<String, dynamic> body,
    String? url,
    ManagementFetcher? fetcher,
  ) async =>
      readMap(
        await _send(
          operation: 'updateApplication',
          failureMessage: 'Failed to update application',
          endpointKey: ManagementEndpointKeys.applications,
          collection: 'applications',
          method: 'PUT',
          id: applicationId,
          body: body,
          url: url,
          fetcher: fetcher,
        ),
      );

  // ── Internals ───────────────────────────────────────────────────────────

  static bool _hasOAuthClient(List<Object?> inboundAuthConfig) =>
      inboundAuthConfig.any((inbound) => inbound is Map && inbound['type'] == 'oauth2');

  /// [inboundAuthConfig] with [clientSecret] set on the OAuth client's configuration, starting
  /// from [emptyConfig] when the client has none.
  static List<Map<String, dynamic>> _withClientSecret(
    List<Object?> inboundAuthConfig,
    String clientSecret, {
    Map<String, dynamic> emptyConfig = const {},
  }) =>
      [
        for (final inbound in inboundAuthConfig.map(readMap))
          inbound['type'] == 'oauth2'
              ? {
                  ...inbound,
                  'config': {
                    ...(inbound['config'] is Map ? readMap(inbound['config']) : emptyConfig),
                    'clientSecret': clientSecret,
                  },
                }
              : inbound,
      ];

  Future<Object?> _send({
    required String operation,
    required String failureMessage,
    String? endpointKey,
    required String collection,
    String method = 'GET',
    String? id,
    String? subPath,
    Map<String, Object?> query = const {},
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: endpointKey,
        collection: collection,
        method: method,
        segments: [
          if (id != null) id,
          if (id != null && subPath != null) ...subPath.split('/'),
        ],
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
