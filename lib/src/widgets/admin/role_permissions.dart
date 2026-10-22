// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/role.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';

/// Presentational, read-only view of the permissions one role grants, grouped by resource
/// server.
class BaseRolePermissions extends StatelessWidget {
  final List<RoleResourcePermissions> permissions;

  /// Display names for resource server ids; the id is shown when a name is missing.
  final Map<String, String> resourceServerNames;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the granted permissions grouped by resource server, the loading and error state, and a resource server name lookup.
  final AdminWidgetBuilder<RolePermissionsState>? builder;

  const BaseRolePermissions({
    super.key,
    required this.permissions,
    this.resourceServerNames = const {},
    this.isLoading = false,
    this.error,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, preferences);
    final granted = permissions.where((entry) => entry.permissions.isNotEmpty).toList();
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        RolePermissionsState(
          permissions: granted,
          isLoading: isLoading,
          error: error,
          resourceServerNames: resourceServerNames,
        ),
      );
    }
    final List<Widget> content;
    if (isLoading) {
      content = [AdminLoading(ac: ac)];
    } else if (error != null) {
      content = [AdminAlert(ac: ac, message: error!, block: 'role-permissions')];
    } else if (granted.isEmpty) {
      content = [AdminMuted(ac: ac, text: ac.t('admin.roles.permissions.empty'))];
    } else {
      content = [
        for (final entry in granted)
          AdminPanel(
            ac: ac,
            title: resourceServerNames[entry.resourceServerId] ?? entry.resourceServerId,
            child: AdminChipList(
              ac: ac,
              label: resourceServerNames[entry.resourceServerId] ?? entry.resourceServerId,
              emptyText: ac.t('admin.roles.permissions.empty'),
              items: [for (final permission in entry.permissions) AdminChip(id: permission, label: permission)],
            ),
          ),
      ];
    }
    return AdminSection(
      ac: ac,
      block: 'role-permissions',
      title: title ?? ac.t('admin.roles.permissions.title'),
      description: description,
      nested: true,
      children: content,
    );
  }
}

/// The permissions one role grants, loaded through the management API. Read-only.
class RolePermissions extends StatefulWidget {
  final String roleId;
  final Map<String, String> resourceServerNames;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseRolePermissions.builder].
  final AdminWidgetBuilder<RolePermissionsState>? builder;

  const RolePermissions({
    super.key,
    required this.roleId,
    this.resourceServerNames = const {},
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<RolePermissions> createState() => _RolePermissionsState();
}

class _RolePermissionsState extends AdminConnectedState<RolePermissions> {
  ResourceQuery<Role>? _role;

  @override
  void bind(ManagementResources resources) {
    _role = own(resources.roleQuery(widget.roleId));
  }

  @override
  void didUpdateWidget(RolePermissions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleId != widget.roleId) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    return BaseRolePermissions(
      permissions: _role?.data?.permissions ?? const [],
      resourceServerNames: widget.resourceServerNames,
      isLoading: _role?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.roles.permissions.error')
          : toManagementErrorMessage(ac.t, _role?.error, 'admin.roles.permissions.error'),
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
