// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/management/management_display.dart';
import '../../models/management/administration.dart';
import '../../models/management/role.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';
import 'role_assignments.dart';
import 'role_permissions.dart';

/// Presentational view of one role: its name and description, an overview, and the [sections]
/// below it, such as the role's permissions and assignments.
///
/// Delete appears only when [onDelete] is set, and never for a read-only role. It asks for
/// confirmation first (spec "UI", requirement 6).
class BaseRoleDetails extends StatelessWidget {
  final Role? role;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onDelete;
  final bool isDeleting;

  /// Views shown below the overview once the role is loaded, such as a [RolePermissions] and a
  /// [RoleAssignments].
  final List<Widget> sections;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the role, the loading and error state, the delete callback, and the [sections].
  final AdminWidgetBuilder<RoleDetailsState>? builder;

  const BaseRoleDetails({
    super.key,
    this.role,
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
    final role = this.role;
    final onDelete = role != null && !role.isReadOnly ? this.onDelete : null;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        RoleDetailsState(
          role: role,
          isLoading: isLoading,
          error: error,
          isDeleting: isDeleting,
          onDelete: onDelete,
          sections: sections,
        ),
      );
    }
    if (role == null) {
      return AdminSection(
        ac: ac,
        block: 'role-details',
        children: [
          if (isLoading)
            AdminLoading(ac: ac)
          else
            AdminAlert(ac: ac, block: 'role-details', message: error ?? ac.t('admin.common.errors.not_found')),
        ],
      );
    }

    return AdminSection(
      ac: ac,
      block: 'role-details',
      title: role.name,
      description: role.description,
      actions: [
        ...actions,
        if (onDelete != null)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('admin.roles.details.delete.action'),
            confirmText: ac.t('admin.roles.details.delete.confirm', {'name': role.name}),
            identifier: 'thunderid-action-role-details-delete',
            isLoading: isDeleting,
            onConfirm: onDelete,
          ),
      ],
      children: [
        if (error != null) AdminAlert(ac: ac, message: error!, block: 'role-details'),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.roles.details.overview'),
          child: AdminDetailList(
            ac: ac,
            items: [
              (ac.t('admin.common.columns.organization_unit'), Text(role.ouHandle ?? role.ouId)),
            ],
          ),
        ),
        ...sections,
      ],
    );
  }
}

/// Role details that loads the role through the management API and shows its permissions and
/// assignments below.
///
/// Changing data is off by default: set [editable] to offer editing the role's permissions and
/// assigning and unassigning the role, and [deletable] to offer delete (with confirmation, never
/// for a read-only role).
class RoleDetails extends StatefulWidget {
  final String roleId;

  /// Whether the embedded [RolePermissions] and [RoleAssignments] are editable: permissions can be
  /// added and removed, and the role assigned and unassigned.
  final bool editable;
  final bool deletable;

  /// How the delete and assignment removal run. [AdministrationMode.flow] runs the role deletion
  /// and assignment removal flows the server configures, falling back to the API when none is.
  final AdministrationMode administrationMode;
  final VoidCallback? onDeleted;

  /// Display names for resource server ids in the embedded [RolePermissions].
  final Map<String, String> resourceServerNames;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseRoleDetails.builder].
  final AdminWidgetBuilder<RoleDetailsState>? builder;

  const RoleDetails({
    super.key,
    required this.roleId,
    this.editable = false,
    this.deletable = false,
    this.administrationMode = AdministrationMode.native,
    this.onDeleted,
    this.resourceServerNames = const {},
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<RoleDetails> createState() => _RoleDetailsState();
}

class _RoleDetailsState extends AdminConnectedState<RoleDetails> {
  ResourceQuery<Role>? _role;
  ResourceMutation<String, void>? _delete;

  @override
  void bind(ManagementResources resources) {
    _role = own(resources.roleQuery(widget.roleId));
    _delete = own(
      resources.deleteRoleMutation(
        administrationMode: widget.administrationMode,
        onSuccess: (_, __) => widget.onDeleted?.call(),
      ),
    );
  }

  @override
  void didUpdateWidget(RoleDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleId != widget.roleId || oldWidget.administrationMode != widget.administrationMode) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final delete = _delete;
    final role = _role?.data;
    return BaseRoleDetails(
      role: role,
      isLoading: _role?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.roles.details.error')
          : toManagementErrorMessage(ac.t, _role?.error, 'admin.roles.details.error') ??
              toManagementErrorMessage(ac.t, delete?.error, 'admin.roles.details.delete.error'),
      isDeleting: delete?.isLoading ?? false,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.roleId)) : null,
      sections: [
        RolePermissions(
          roleId: widget.roleId,
          editable: widget.editable,
          resourceServerNames: widget.resourceServerNames,
          preferences: widget.preferences,
        ),
        RoleAssignments(
          roleId: widget.roleId,
          ouId: role?.ouId,
          editable: widget.editable && role != null,
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
