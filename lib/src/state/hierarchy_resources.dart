// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../api/management/management_transport.dart';
import '../api/management/organization_units.dart';
import '../api/management/projects.dart';
import '../api/management/sharing.dart';
import '../models/management/management_page.dart';
import '../models/management/organization_unit.dart';
import '../models/management/project.dart';
import '../models/management/sharing_policy.dart';
import 'management_resources.dart';
import 'resource_notifiers.dart';

/// Variables of [HierarchyResources.updateProjectMutation].
typedef UpdateProjectVariables = ({String projectId, UpdateProjectRequest data});

/// Variables of [HierarchyResources.updateOrganizationUnitMutation].
typedef UpdateOrganizationUnitVariables = ({String ouId, UpdateOrganizationUnitRequest data});

/// Variables of [HierarchyResources.createSharingPolicyMutation].
typedef CreateSharingPolicyVariables = ({String resourceId, CreateSharingPolicyRequest data});

/// Variables of [HierarchyResources.updateSharingPolicyMutation].
typedef UpdateSharingPolicyVariables = ({String resourceId, String policyId, UpdateSharingPolicyRequest data});

/// Variables of [HierarchyResources.deleteSharingPolicyMutation].
typedef DeleteSharingPolicyVariables = ({String resourceId, String policyId});

/// The queries and mutations for projects, organization units, and sharing policies, on the same
/// [ManagementResources] (and so the same invalidator) as every other management read and write.
extension HierarchyResources on ManagementResources {
  ResourceQuery<T> _read<T>(ResourceQueryKey key, Future<T> Function() fetch, bool enabled) =>
      ResourceQuery<T>(fetch, key: key, invalidator: invalidator, enabled: enabled);

  ResourceMutation<V, R> _write<V, R>(
    Future<R> Function(V variables) mutate,
    List<ResourceQueryKey> Function(V variables) invalidates,
    void Function(R data, V variables)? onSuccess,
    void Function(Object error, V variables)? onError,
  ) => ResourceMutation<V, R>(
    mutate,
    invalidates: invalidates,
    invalidator: invalidator,
    onSuccess: onSuccess,
    onError: onError,
  );

  // ── Projects ────────────────────────────────────────────────────────────

  ResourceQuery<ManagementPage<Project>> projectsQuery({
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [
      ManagementQueryKeys.projects,
      {'limit': limit, 'offset': offset},
    ],
    () => client.getProjects(limit: limit, offset: offset, fetcher: fetcher),
    enabled,
  );

  ResourceQuery<Project> projectQuery(String? projectId, {bool enabled = true, ManagementFetcher? fetcher}) => _read(
    [ManagementQueryKeys.project, projectId],
    () => client.getProject(projectId!, fetcher: fetcher),
    enabled && projectId != null,
  );

  ResourceMutation<CreateProjectRequest, Project> createProjectMutation({
    void Function(Project data, CreateProjectRequest variables)? onSuccess,
    void Function(Object error, CreateProjectRequest variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (CreateProjectRequest payload) => client.createProject(payload, fetcher: fetcher),
    (_) => [
      [ManagementQueryKeys.projects],
    ],
    onSuccess,
    onError,
  );

  ResourceMutation<UpdateProjectVariables, Project> updateProjectMutation({
    void Function(Project data, UpdateProjectVariables variables)? onSuccess,
    void Function(Object error, UpdateProjectVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (UpdateProjectVariables v) => client.updateProject(v.projectId, v.data, fetcher: fetcher),
    (UpdateProjectVariables v) => [
      [ManagementQueryKeys.project, v.projectId],
      [ManagementQueryKeys.projects],
    ],
    onSuccess,
    onError,
  );

  ResourceMutation<String, void> deleteProjectMutation({
    void Function(void data, String projectId)? onSuccess,
    void Function(Object error, String projectId)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (String projectId) => client.deleteProject(projectId, fetcher: fetcher),
    (_) => [
      [ManagementQueryKeys.projects],
      [ManagementQueryKeys.applications],
      [ManagementQueryKeys.agents],
    ],
    onSuccess,
    onError,
  );

  // ── Organization units ──────────────────────────────────────────────────

  /// The root organization units, or the children of [parentId] when it is given.
  ResourceQuery<ManagementPage<BasicOrganizationUnit>> organizationUnitsQuery({
    String? parentId,
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [
      ManagementQueryKeys.organizationUnits,
      parentId,
      {'limit': limit, 'offset': offset},
    ],
    () => parentId == null
        ? client.getOrganizationUnits(limit: limit, offset: offset, fetcher: fetcher)
        : client.getOrganizationUnitChildren(ouId: parentId, limit: limit, offset: offset, fetcher: fetcher),
    enabled,
  );

  ResourceQuery<OrganizationUnit> organizationUnitQuery(
    String? ouId, {
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [ManagementQueryKeys.organizationUnit, ouId],
    () => client.getOrganizationUnit(ouId!, fetcher: fetcher),
    enabled && ouId != null,
  );

  ResourceQuery<ManagementPage<OrganizationUnitUser>> organizationUnitUsersQuery(
    String? ouId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [
      ManagementQueryKeys.organizationUnitMembers,
      ouId,
      'users',
      {'limit': limit, 'offset': offset},
    ],
    () => client.getOrganizationUnitUsers(ouId: ouId, limit: limit, offset: offset, fetcher: fetcher),
    enabled && ouId != null,
  );

  ResourceQuery<ManagementPage<OrganizationUnitGroup>> organizationUnitGroupsQuery(
    String? ouId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [
      ManagementQueryKeys.organizationUnitMembers,
      ouId,
      'groups',
      {'limit': limit, 'offset': offset},
    ],
    () => client.getOrganizationUnitGroups(ouId: ouId, limit: limit, offset: offset, fetcher: fetcher),
    enabled && ouId != null,
  );

  ResourceQuery<ManagementPage<OrganizationUnitRole>> organizationUnitRolesQuery(
    String? ouId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [
      ManagementQueryKeys.organizationUnitMembers,
      ouId,
      'roles',
      {'limit': limit, 'offset': offset},
    ],
    () => client.getOrganizationUnitRoles(ouId: ouId, limit: limit, offset: offset, fetcher: fetcher),
    enabled && ouId != null,
  );

  ResourceMutation<CreateOrganizationUnitRequest, OrganizationUnit> createOrganizationUnitMutation({
    void Function(OrganizationUnit data, CreateOrganizationUnitRequest variables)? onSuccess,
    void Function(Object error, CreateOrganizationUnitRequest variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (CreateOrganizationUnitRequest payload) => client.createOrganizationUnit(payload, fetcher: fetcher),
    (_) => [
      [ManagementQueryKeys.organizationUnits],
    ],
    onSuccess,
    onError,
  );

  ResourceMutation<UpdateOrganizationUnitVariables, OrganizationUnit> updateOrganizationUnitMutation({
    void Function(OrganizationUnit data, UpdateOrganizationUnitVariables variables)? onSuccess,
    void Function(Object error, UpdateOrganizationUnitVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (UpdateOrganizationUnitVariables v) => client.updateOrganizationUnit(v.ouId, v.data, fetcher: fetcher),
    (UpdateOrganizationUnitVariables v) => [
      [ManagementQueryKeys.organizationUnit, v.ouId],
      [ManagementQueryKeys.organizationUnits],
    ],
    onSuccess,
    onError,
  );

  ResourceMutation<String, void> deleteOrganizationUnitMutation({
    void Function(void data, String ouId)? onSuccess,
    void Function(Object error, String ouId)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (String ouId) => client.deleteOrganizationUnit(ouId, fetcher: fetcher),
    (_) => [
      [ManagementQueryKeys.organizationUnits],
    ],
    onSuccess,
    onError,
  );

  // ── Sharing policies ────────────────────────────────────────────────────

  ResourceQuery<ManagementPage<SharingPolicy>> sharingPoliciesQuery(
    SharingResourceType type,
    String? resourceId, {
    int? limit,
    int? offset,
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) => _read(
    [
      ManagementQueryKeys.sharingPolicies,
      type.value,
      resourceId,
      {'limit': limit, 'offset': offset},
    ],
    () {
      final id = resourceId!;
      return switch (type) {
        SharingResourceType.user => client.getUserSharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher),
        SharingResourceType.application => client.getApplicationSharingPolicies(
          id,
          limit: limit,
          offset: offset,
          fetcher: fetcher,
        ),
        SharingResourceType.role => client.getRoleSharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher),
        SharingResourceType.flow => client.getFlowSharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher),
      };
    },
    enabled && resourceId != null,
  );

  /// How the resource appears in the organization unit [ouId]. Disabled until [ouId] is given.
  ResourceQuery<ResolvedOverlay> overlayRulesQuery(
    SharingResourceType type,
    String? resourceId,
    String? ouId, {
    bool enabled = true,
    ManagementFetcher? fetcher,
  }) {
    Future<ResolvedOverlay> fetch() {
      final id = resourceId!;
      return switch (type) {
        SharingResourceType.user => client.getUserOverlayRules(id, ouId: ouId, fetcher: fetcher),
        SharingResourceType.application => client.getApplicationOverlayRules(id, ouId: ouId, fetcher: fetcher),
        SharingResourceType.role => client.getRoleOverlayRules(id, ouId: ouId, fetcher: fetcher),
        SharingResourceType.flow => client.getFlowOverlayRules(id, ouId: ouId, fetcher: fetcher),
      };
    }

    final key = [ManagementQueryKeys.overlayRules, type.value, resourceId, ouId];
    return _read(key, fetch, enabled && resourceId != null && ouId != null);
  }

  ResourceMutation<CreateSharingPolicyVariables, SharingPolicy> createSharingPolicyMutation(
    SharingResourceType type, {
    void Function(SharingPolicy data, CreateSharingPolicyVariables variables)? onSuccess,
    void Function(Object error, CreateSharingPolicyVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (CreateSharingPolicyVariables v) => switch (type) {
      SharingResourceType.user => client.createUserSharingPolicy(v.resourceId, v.data, fetcher: fetcher),
      SharingResourceType.application => client.createApplicationSharingPolicy(v.resourceId, v.data, fetcher: fetcher),
      SharingResourceType.role => client.createRoleSharingPolicy(v.resourceId, v.data, fetcher: fetcher),
      SharingResourceType.flow => client.createFlowSharingPolicy(v.resourceId, v.data, fetcher: fetcher),
    },
    (CreateSharingPolicyVariables v) => _sharingKeys(type, v.resourceId),
    onSuccess,
    onError,
  );

  ResourceMutation<UpdateSharingPolicyVariables, SharingPolicy> updateSharingPolicyMutation(
    SharingResourceType type, {
    void Function(SharingPolicy data, UpdateSharingPolicyVariables variables)? onSuccess,
    void Function(Object error, UpdateSharingPolicyVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (UpdateSharingPolicyVariables v) => switch (type) {
      SharingResourceType.user => client.updateUserSharingPolicy(v.resourceId, v.policyId, v.data, fetcher: fetcher),
      SharingResourceType.application => client.updateApplicationSharingPolicy(
        v.resourceId,
        v.policyId,
        v.data,
        fetcher: fetcher,
      ),
      SharingResourceType.role => client.updateRoleSharingPolicy(v.resourceId, v.policyId, v.data, fetcher: fetcher),
      SharingResourceType.flow => client.updateFlowSharingPolicy(v.resourceId, v.policyId, v.data, fetcher: fetcher),
    },
    (UpdateSharingPolicyVariables v) => _sharingKeys(type, v.resourceId),
    onSuccess,
    onError,
  );

  ResourceMutation<DeleteSharingPolicyVariables, void> deleteSharingPolicyMutation(
    SharingResourceType type, {
    void Function(void data, DeleteSharingPolicyVariables variables)? onSuccess,
    void Function(Object error, DeleteSharingPolicyVariables variables)? onError,
    ManagementFetcher? fetcher,
  }) => _write(
    (DeleteSharingPolicyVariables v) => switch (type) {
      SharingResourceType.user => client.deleteUserSharingPolicy(v.resourceId, v.policyId, fetcher: fetcher),
      SharingResourceType.application => client.deleteApplicationSharingPolicy(
        v.resourceId,
        v.policyId,
        fetcher: fetcher,
      ),
      SharingResourceType.role => client.deleteRoleSharingPolicy(v.resourceId, v.policyId, fetcher: fetcher),
      SharingResourceType.flow => client.deleteFlowSharingPolicy(v.resourceId, v.policyId, fetcher: fetcher),
    },
    (DeleteSharingPolicyVariables v) => _sharingKeys(type, v.resourceId),
    onSuccess,
    onError,
  );

  static List<ResourceQueryKey> _sharingKeys(SharingResourceType type, String resourceId) => [
    [ManagementQueryKeys.sharingPolicies, type.value, resourceId],
    [ManagementQueryKeys.overlayRules, type.value, resourceId],
  ];
}
