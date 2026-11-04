// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/management/management_display.dart';
import '../../models/management/administration.dart';
import '../../models/management/group.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'group_members.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// Presentational view of one group: its name and description, an overview, and the [sections]
/// below it, such as the group's member list.
///
/// Delete appears only when [onDelete] is set, and asks for confirmation first (spec "UI",
/// requirement 6).
class BaseGroupDetails extends StatelessWidget {
  final Group? group;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onDelete;
  final bool isDeleting;

  /// Views shown below the overview once the group is loaded, such as a [GroupMembers].
  final List<Widget> sections;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the group, the loading and error state, the delete callback, and the [sections].
  final AdminWidgetBuilder<GroupDetailsState>? builder;

  const BaseGroupDetails({
    super.key,
    this.group,
    this.isLoading = false,
    this.error,
    this.onDelete,
    this.isDeleting = false,
    this.sections = const [],
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, preferences);
    final group = this.group;
    final onDelete = group != null ? this.onDelete : null;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        GroupDetailsState(
          group: group,
          isLoading: isLoading,
          error: error,
          isDeleting: isDeleting,
          onDelete: onDelete,
          sections: sections,
        ),
      );
    }
    if (group == null) {
      return AdminSection(
        ac: ac,
        block: 'group-details',
        children: [
          if (isLoading)
            AdminLoading(ac: ac)
          else
            AdminAlert(ac: ac, block: 'group-details', message: error ?? ac.t('admin.common.errors.not_found')),
        ],
      );
    }

    return AdminSection(
      ac: ac,
      block: 'group-details',
      title: group.name,
      description: group.description,
      actions: [
        ...actions,
        if (onDelete != null)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('admin.groups.details.delete.action'),
            confirmText: ac.t('admin.groups.details.delete.confirm', {'name': group.name}),
            identifier: 'thunderid-action-group-details-delete',
            isLoading: isDeleting,
            onConfirm: onDelete,
          ),
      ],
      children: [
        if (error != null) AdminAlert(ac: ac, message: error!, block: 'group-details'),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.groups.details.overview'),
          child: AdminDetailList(
            ac: ac,
            items: [
              (ac.t('admin.common.columns.organization_unit'), Text(group.ouHandle ?? group.ouId)),
            ],
          ),
        ),
        ...sections,
      ],
    );
  }
}

/// Group details that loads the group through the management API and lists its members below.
///
/// Changing data is off by default: set [editable] to offer adding and removing members, and
/// [deletable] to offer delete (with confirmation).
class GroupDetails extends StatefulWidget {
  final String groupId;

  /// Whether members can be added and removed from the embedded [GroupMembers].
  final bool editable;
  final bool deletable;

  /// How the delete and member removal run. [AdministrationMode.flow] runs the group deletion and
  /// membership removal flows the server configures, falling back to the API when none is.
  final AdministrationMode administrationMode;
  final VoidCallback? onDeleted;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseGroupDetails.builder].
  final AdminWidgetBuilder<GroupDetailsState>? builder;

  const GroupDetails({
    super.key,
    required this.groupId,
    this.editable = false,
    this.deletable = false,
    this.administrationMode = AdministrationMode.native,
    this.onDeleted,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<GroupDetails> createState() => _GroupDetailsState();
}

class _GroupDetailsState extends AdminConnectedState<GroupDetails> {
  ResourceQuery<Group>? _group;
  ResourceMutation<String, void>? _delete;

  @override
  void bind(ManagementResources resources) {
    _group = own(resources.groupQuery(widget.groupId));
    _delete = own(
      resources.deleteGroupMutation(
        administrationMode: widget.administrationMode,
        onSuccess: (_, __) => widget.onDeleted?.call(),
      ),
    );
  }

  @override
  void didUpdateWidget(GroupDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId || oldWidget.administrationMode != widget.administrationMode) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final delete = _delete;
    final group = _group?.data;
    return BaseGroupDetails(
      group: group,
      isLoading: _group?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.groups.details.error')
          : toManagementErrorMessage(ac.t, _group?.error, 'admin.groups.details.error') ??
              toManagementErrorMessage(ac.t, delete?.error, 'admin.groups.details.delete.error'),
      isDeleting: delete?.isLoading ?? false,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.groupId)) : null,
      sections: [
        GroupMembers(
          groupId: widget.groupId,
          ouId: group?.ouId,
          editable: widget.editable && group != null,
          administrationMode: widget.administrationMode,
          preferences: widget.preferences,
        ),
      ],
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
