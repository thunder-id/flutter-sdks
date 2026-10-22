// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/agent.dart';
import '../../models/management/group.dart';
import '../../models/management/managed_user.dart';
import '../../models/management/management_page.dart';
import '../../models/management/role.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'identity_candidate.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// Presentational list of who one role is assigned to.
///
/// Assigning appears only when [onAssign] and [candidates] are set, unassigning only when
/// [onUnassign] is set. Only the types present in [candidates] can be assigned.
class BaseRoleAssignments extends StatelessWidget {
  final List<RoleAssignment> assignments;
  final Map<RoleAssigneeType, List<IdentityCandidate>>? candidates;
  final ValueChanged<RoleAssignment>? onAssign;
  final ValueChanged<RoleAssignment>? onUnassign;
  final bool isLoading;
  final bool isMutating;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// The assignee type the list is narrowed to, or `null` for every type.
  final RoleAssigneeType? typeFilter;

  /// Narrows the list to one assignee type on the server, or back to every type with `null`. The
  /// type filter shows only when set.
  final ValueChanged<RoleAssigneeType?>? onTypeFilterChange;

  /// Builds custom UI in place of the default table and picker, from the assignments, the candidates, the loading and error state, and the assign and unassign callbacks.
  final AdminWidgetBuilder<RoleAssignmentsState>? builder;

  const BaseRoleAssignments({
    super.key,
    required this.assignments,
    this.candidates,
    this.onAssign,
    this.onUnassign,
    this.isLoading = false,
    this.isMutating = false,
    this.error,
    this.title,
    this.description,
    this.preferences,
    this.typeFilter,
    this.onTypeFilterChange,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, preferences);
    final candidates = this.candidates;
    final onAssign = this.onAssign;
    final onUnassign = this.onUnassign;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        RoleAssignmentsState(
          assignments: assignments,
          candidates: onAssign == null ? null : candidates,
          isLoading: isLoading,
          error: error,
          isMutating: isMutating,
          onAssign: candidates == null ? null : onAssign,
          onUnassign: onUnassign,
          typeFilter: typeFilter,
          onTypeFilterChange: onTypeFilterChange,
        ),
      );
    }
    String label(RoleAssignment assignment) => assignment.display ?? assignment.id;
    return AdminSection(
      ac: ac,
      block: 'role-assignments',
      title: title ?? ac.t('admin.roles.assignments.title'),
      description: description,
      nested: true,
      children: [
        if (onTypeFilterChange != null)
          AdminDropdown(
            ac: ac,
            label: ac.t('admin.common.filters.type'),
            identifier: 'thunderid-field-role-assignments-type-filter',
            value: typeFilter?.value ?? '',
            options: [
              AdminSelectOption(value: '', label: ac.t('admin.common.filters.all_types')),
              for (final type in const [
                RoleAssigneeType.user,
                RoleAssigneeType.group,
                RoleAssigneeType.agent,
                RoleAssigneeType.app,
              ])
                AdminSelectOption(value: type.value, label: ac.t('admin.common.identity_types.${type.value}')),
            ],
            onChanged: (value) => onTypeFilterChange!(RoleAssigneeType.fromValue(value)),
          ),
        if (onAssign != null && candidates != null)
          AdminIdentityPicker<RoleAssigneeType>(
            ac: ac,
            block: 'role-assignments',
            addLabel: ac.t('admin.roles.assignments.add'),
            typeValue: (type) => type.value,
            types: [
              for (final type in const [
                RoleAssigneeType.user,
                RoleAssigneeType.group,
                RoleAssigneeType.agent,
                RoleAssigneeType.app,
              ])
                if (candidates.containsKey(type)) (type, ac.identityType(type.value)),
            ],
            candidates: candidates,
            excludedIds: {for (final assignment in assignments) assignment.id},
            isSubmitting: isMutating,
            onAdd: (type, id) => onAssign(RoleAssignment(id: id, type: type)),
          ),
        AdminTable<RoleAssignment>(
          ac: ac,
          block: 'role-assignments',
          rows: assignments,
          rowId: (assignment) => '${assignment.type.value}:${assignment.id}',
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.roles.assignments.empty'),
          trailing: onUnassign == null
              ? null
              : (assignment) => AdminRemoveButton(
                    ac: ac,
                    identifier: 'thunderid-action-role-assignments-remove-${assignment.id}',
                    semanticLabel: ac.t('admin.roles.assignments.remove_label', {'name': label(assignment)}),
                    onPressed: isMutating ? null : () => onUnassign(assignment),
                  ),
          columns: [
            AdminColumn(
              header: ac.t('admin.roles.assignments.columns.assignee'),
              build: (assignment) => Text(label(assignment)),
            ),
            AdminColumn(
              header: ac.t('admin.roles.assignments.columns.type'),
              build: (assignment) => Text(ac.identityType(assignment.type.value)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Assignments of one role, loaded through the management API.
///
/// Changing assignments is off by default: set [editable] to offer assigning users, groups,
/// and agents and removing assignments.
class RoleAssignments extends StatefulWidget {
  final String roleId;
  final bool editable;

  /// Whether to show the assignee type filter, which narrows the list on the server.
  final bool filterable;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default table and picker. See [BaseRoleAssignments.builder].
  final AdminWidgetBuilder<RoleAssignmentsState>? builder;

  const RoleAssignments({
    super.key,
    required this.roleId,
    this.editable = false,
    this.filterable = true,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<RoleAssignments> createState() => _RoleAssignmentsState();
}

class _RoleAssignmentsState extends AdminConnectedState<RoleAssignments> {
  ResourceQuery<ManagementPage<RoleAssignment>>? _assignments;
  ResourceQuery<ManagementPage<ManagedUser>>? _users;
  ResourceQuery<ManagementPage<Group>>? _groups;
  ResourceQuery<ManagementPage<Agent>>? _agents;
  ResourceMutation<RoleAssignmentsVariables, void>? _assign;
  ResourceMutation<RoleAssignmentsVariables, void>? _unassign;
  RoleAssigneeType? _typeFilter;

  @override
  void bind(ManagementResources resources) {
    _assignments = own(resources.roleAssignmentsQuery(widget.roleId, type: _typeFilter, limit: 100));
    _users = own(resources.usersQuery(limit: 100, enabled: widget.editable));
    _groups = own(resources.groupsQuery(limit: 100, enabled: widget.editable));
    _agents = own(resources.agentsQuery(limit: 100, enabled: widget.editable));
    _assign = own(resources.addRoleAssignmentsMutation());
    _unassign = own(resources.removeRoleAssignmentsMutation());
  }

  @override
  void didUpdateWidget(RoleAssignments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleId != widget.roleId || oldWidget.editable != widget.editable) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final assign = _assign;
    final unassign = _unassign;
    final editable = widget.editable && assign != null && unassign != null;
    return BaseRoleAssignments(
      assignments: _assignments?.data?.items ?? const [],
      isLoading: _assignments?.isLoading ?? !providerFailed,
      isMutating: (assign?.isLoading ?? false) || (unassign?.isLoading ?? false),
      error: providerFailed
          ? ac.t('admin.roles.assignments.error')
          : toManagementErrorMessage(ac.t, _assignments?.error, 'admin.roles.assignments.error') ??
              toManagementErrorMessage(
                ac.t,
                assign?.error ?? unassign?.error,
                'admin.roles.assignments.update_error',
              ),
      candidates: editable
          ? {
              RoleAssigneeType.user: [
                for (final user in _users?.data?.items ?? const <ManagedUser>[])
                  IdentityCandidate(
                    id: user.id,
                    label: resolveManagedIdentityName(id: user.id, display: user.display, attributes: user.attributes),
                  ),
              ],
              RoleAssigneeType.group: [
                for (final group in _groups?.data?.items ?? const <Group>[])
                  IdentityCandidate(id: group.id, label: group.name),
              ],
              RoleAssigneeType.agent: [
                for (final agent in _agents?.data?.items ?? const <Agent>[])
                  IdentityCandidate(id: agent.id, label: agent.name),
              ],
            }
          : null,
      onAssign: editable
          ? (assignment) => unawaited(assign.mutate((roleId: widget.roleId, assignments: [assignment])))
          : null,
      onUnassign: editable
          ? (assignment) => unawaited(
                unassign.mutate(
                  (roleId: widget.roleId, assignments: [RoleAssignment(id: assignment.id, type: assignment.type)]),
                ),
              )
          : null,
      title: widget.title,
      description: widget.description,
      typeFilter: _typeFilter,
      onTypeFilterChange: widget.filterable
          ? (type) {
              setState(() => _typeFilter = type);
              rebind();
            }
          : null,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
