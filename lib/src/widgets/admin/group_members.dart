// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/agent.dart';
import '../../models/management/group.dart';
import '../../models/management/managed_user.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'identity_candidate.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// Presentational member list of one group.
///
/// Adding appears only when [onAdd] and [candidates] are set, removing only when [onRemove] is
/// set. Only the types present in [candidates] can be added.
class BaseGroupMembers extends StatelessWidget {
  final List<GroupMember> members;
  final Map<GroupMemberType, List<IdentityCandidate>>? candidates;
  final ValueChanged<GroupMember>? onAdd;
  final ValueChanged<GroupMember>? onRemove;
  final bool isLoading;
  final bool isMutating;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default table and picker, from the members, the candidates, the loading and error state, and the add and remove callbacks.
  final AdminWidgetBuilder<GroupMembersState>? builder;

  const BaseGroupMembers({
    super.key,
    required this.members,
    this.candidates,
    this.onAdd,
    this.onRemove,
    this.isLoading = false,
    this.isMutating = false,
    this.error,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, preferences);
    final candidates = this.candidates;
    final onAdd = this.onAdd;
    final onRemove = this.onRemove;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        GroupMembersState(
          members: members,
          candidates: onAdd == null ? null : candidates,
          isLoading: isLoading,
          error: error,
          isMutating: isMutating,
          onAdd: candidates == null ? null : onAdd,
          onRemove: onRemove,
        ),
      );
    }
    String label(GroupMember member) => member.display ?? member.id;
    return AdminSection(
      ac: ac,
      block: 'group-members',
      title: title ?? ac.t('admin.groups.members.title'),
      description: description,
      nested: true,
      children: [
        if (onAdd != null && candidates != null)
          AdminIdentityPicker<GroupMemberType>(
            ac: ac,
            block: 'group-members',
            addLabel: ac.t('admin.groups.members.add'),
            typeValue: (type) => type.value,
            types: [
              for (final type in const [GroupMemberType.user, GroupMemberType.agent, GroupMemberType.group])
                if (candidates.containsKey(type)) (type, ac.identityType(type.value)),
            ],
            candidates: candidates,
            excludedIds: {for (final member in members) member.id},
            isSubmitting: isMutating,
            onAdd: (type, id) => onAdd(GroupMember(id: id, type: type)),
          ),
        AdminTable<GroupMember>(
          ac: ac,
          block: 'group-members',
          rows: members,
          rowId: (member) => '${member.type.value}:${member.id}',
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.groups.members.empty'),
          trailing: onRemove == null
              ? null
              : (member) => AdminRemoveButton(
                    ac: ac,
                    identifier: 'thunderid-action-group-members-remove-${member.id}',
                    semanticLabel: ac.t('admin.groups.members.remove_label', {'name': label(member)}),
                    onPressed: isMutating ? null : () => onRemove(member),
                  ),
          columns: [
            AdminColumn(header: ac.t('admin.groups.members.columns.member'), build: (member) => Text(label(member))),
            AdminColumn(
              header: ac.t('admin.groups.members.columns.type'),
              build: (member) => Text(ac.identityType(member.type.value)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Member list of one group, loaded through the management API.
///
/// Changing membership is off by default: set [editable] to offer adding users and agents and
/// removing members.
class GroupMembers extends StatefulWidget {
  final String groupId;
  final bool editable;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default table and picker. See [BaseGroupMembers.builder].
  final AdminWidgetBuilder<GroupMembersState>? builder;

  const GroupMembers({
    super.key,
    required this.groupId,
    this.editable = false,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<GroupMembers> createState() => _GroupMembersState();
}

class _GroupMembersState extends AdminConnectedState<GroupMembers> {
  ResourceQuery<ManagementPage<GroupMember>>? _members;
  ResourceQuery<ManagementPage<ManagedUser>>? _users;
  ResourceQuery<ManagementPage<Agent>>? _agents;
  ResourceMutation<GroupMembersVariables, Group?>? _add;
  ResourceMutation<GroupMembersVariables, Group?>? _remove;

  @override
  void bind(ManagementResources resources) {
    _members = own(resources.groupMembersQuery(widget.groupId, limit: 100));
    _users = own(resources.usersQuery(limit: 100, enabled: widget.editable));
    _agents = own(resources.agentsQuery(limit: 100, enabled: widget.editable));
    _add = own(resources.addGroupMembersMutation());
    _remove = own(resources.removeGroupMembersMutation());
  }

  @override
  void didUpdateWidget(GroupMembers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId || oldWidget.editable != widget.editable) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final add = _add;
    final remove = _remove;
    final editable = widget.editable && add != null && remove != null;
    return BaseGroupMembers(
      members: _members?.data?.items ?? const [],
      isLoading: _members?.isLoading ?? !providerFailed,
      isMutating: (add?.isLoading ?? false) || (remove?.isLoading ?? false),
      error: providerFailed
          ? ac.t('admin.groups.members.error')
          : toManagementErrorMessage(ac.t, _members?.error, 'admin.groups.members.error') ??
              toManagementErrorMessage(ac.t, add?.error ?? remove?.error, 'admin.groups.members.update_error'),
      candidates: editable
          ? {
              GroupMemberType.user: [
                for (final user in _users?.data?.items ?? const <ManagedUser>[])
                  IdentityCandidate(
                    id: user.id,
                    label: resolveManagedIdentityName(id: user.id, display: user.display, attributes: user.attributes),
                  ),
              ],
              GroupMemberType.agent: [
                for (final agent in _agents?.data?.items ?? const <Agent>[])
                  IdentityCandidate(id: agent.id, label: agent.name),
              ],
            }
          : null,
      onAdd: editable
          ? (member) => unawaited(add.mutate((groupId: widget.groupId, members: [member])))
          : null,
      onRemove: editable
          ? (member) => unawaited(
                remove.mutate((groupId: widget.groupId, members: [GroupMember(id: member.id, type: member.type)])),
              )
          : null,
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
