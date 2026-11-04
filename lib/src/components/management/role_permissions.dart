// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/management/management_display.dart';
import '../../api/management/resource_servers.dart';
import '../../models/management/resource_server.dart';
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

/// Presentational view of the permissions one role grants, grouped by resource server.
///
/// Adding appears only when [onAdd] and [availablePermissions] are set, removing only when
/// [onRemove] is set. A removal asks for confirmation first (spec "UI", requirement 6).
class BaseRolePermissions extends StatelessWidget {
  final List<RoleResourcePermissions> permissions;

  /// Display names for resource server ids; the id is shown when a name is missing.
  final Map<String, String> resourceServerNames;

  /// The permissions each resource server offers, keyed by resource server id, to pick from when
  /// adding. A permission the role already grants is not offered again.
  final Map<String, List<String>>? availablePermissions;
  final ValueChanged<RolePermission>? onAdd;
  final ValueChanged<RolePermission>? onRemove;
  final bool isLoading;
  final bool isMutating;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the granted permissions grouped by
  /// resource server, the loading and error state, a resource server name lookup, and, when the
  /// view is editable, the permissions to pick from and the add and remove callbacks.
  final AdminWidgetBuilder<RolePermissionsState>? builder;

  const BaseRolePermissions({
    super.key,
    required this.permissions,
    this.resourceServerNames = const {},
    this.availablePermissions,
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
    final granted = permissions.where((entry) => entry.permissions.isNotEmpty).toList();
    final onAdd = this.onAdd;
    final onRemove = this.onRemove;
    final available = onAdd == null ? null : availablePermissions;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        RolePermissionsState(
          permissions: granted,
          isLoading: isLoading,
          error: error,
          resourceServerNames: resourceServerNames,
          availablePermissions: available,
          onAdd: available == null ? null : onAdd,
          onRemove: onRemove,
          isMutating: isMutating,
        ),
      );
    }
    String serverName(String id) => resourceServerNames[id] ?? id;
    final List<Widget> content;
    if (isLoading) {
      content = [AdminLoading(ac: ac)];
    } else {
      content = [
        if (error != null) AdminAlert(ac: ac, message: error!, block: 'role-permissions'),
        if (onAdd != null && available != null) _picker(ac, onAdd, available, serverName),
        if (granted.isEmpty && error == null) AdminMuted(ac: ac, text: ac.t('admin.roles.permissions.empty')),
        for (final entry in granted)
          AdminPanel(
            ac: ac,
            title: serverName(entry.resourceServerId),
            child: onRemove == null
                ? AdminChipList(
                    ac: ac,
                    label: serverName(entry.resourceServerId),
                    emptyText: ac.t('admin.roles.permissions.empty'),
                    items: [for (final permission in entry.permissions) AdminChip(id: permission, label: permission)],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final permission in entry.permissions)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              Text(permission, style: TextStyle(color: ac.colors.text)),
                              AdminConfirmButton(
                                ac: ac,
                                label: ac.t('admin.common.actions.remove'),
                                semanticLabel: ac.t('admin.roles.permissions.remove_label', {'permission': permission}),
                                confirmText: ac.t('admin.roles.permissions.remove_confirm', {
                                  'permission': permission,
                                  'resourceServer': serverName(entry.resourceServerId),
                                }),
                                identifier:
                                    'thunderid-action-role-permissions-remove-${entry.resourceServerId}-$permission',
                                onConfirm: () => onRemove(
                                  RolePermission(resourceServerId: entry.resourceServerId, permission: permission),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
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

  Widget _picker(
    AdminContext ac,
    ValueChanged<RolePermission> onAdd,
    Map<String, List<String>> available,
    String Function(String id) serverName,
  ) {
    final grantedByServer = {
      for (final entry in permissions) entry.resourceServerId: entry.permissions.toSet(),
    };
    final candidates = <String, List<IdentityCandidate>>{
      for (final entry in available.entries)
        entry.key: [
          for (final permission in entry.value)
            if (!(grantedByServer[entry.key]?.contains(permission) ?? false))
              IdentityCandidate(id: permission, label: permission),
        ],
    };
    return AdminIdentityPicker<String>(
      ac: ac,
      block: 'role-permissions',
      addLabel: ac.t('admin.roles.permissions.add'),
      typeLabel: ac.t('admin.roles.permissions.fields.resource_server'),
      itemLabel: ac.t('admin.roles.permissions.fields.permission'),
      itemPlaceholder: ac.t('admin.roles.permissions.fields.permission_placeholder'),
      itemEmptyText: ac.t('admin.roles.permissions.fields.permission_empty'),
      typeValue: (id) => id,
      types: [for (final id in available.keys) (id, serverName(id))],
      candidates: candidates,
      isSubmitting: isMutating,
      onAdd: (resourceServerId, permission) =>
          onAdd(RolePermission(resourceServerId: resourceServerId, permission: permission)),
    );
  }
}

/// The resource servers a role can grant permissions on, with the permissions each one's
/// actions grant.
typedef _PermissionOptions = List<(ResourceServer, List<String>)>;

/// The permissions one role grants, loaded through the management API.
///
/// Changing permissions is off by default: set [editable] to offer adding a permission, picked
/// from the resource servers and the permissions their actions grant, and removing one (with
/// confirmation). Each change saves the role. A read-only role is never editable.
class RolePermissions extends StatefulWidget {
  final String roleId;
  final bool editable;
  final Map<String, String> resourceServerNames;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseRolePermissions.builder].
  final AdminWidgetBuilder<RolePermissionsState>? builder;

  const RolePermissions({
    super.key,
    required this.roleId,
    this.editable = false,
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
  static const int _pageSize = 100;

  ResourceQuery<Role>? _role;
  ResourceQuery<_PermissionOptions>? _options;
  ResourceMutation<UpdateRoleVariables, Role>? _update;

  @override
  void bind(ManagementResources resources) {
    _role = own(resources.roleQuery(widget.roleId));
    _options = own(
      ResourceQuery<_PermissionOptions>(
        () => _loadOptions(resources),
        key: const ['role-permission-options'],
        invalidator: resources.invalidator,
        enabled: widget.editable,
      ),
    );
    _update = own(resources.updateRoleMutation());
  }

  static Future<_PermissionOptions> _loadOptions(ManagementResources resources) async {
    final servers = await resources.client.getResourceServers(limit: _pageSize);
    return Future.wait([
      for (final server in servers.items)
        resources.client
            .getActions(server.id, limit: _pageSize)
            .then((actions) => (server, [for (final action in actions.items) action.permission])),
    ]);
  }

  @override
  void didUpdateWidget(RolePermissions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleId != widget.roleId || oldWidget.editable != widget.editable) rebind();
  }

  void _save(Role role, List<RoleResourcePermissions> permissions) {
    final update = _update;
    if (update == null || update.isLoading) return;
    final data = UpdateRoleRequest(
      name: role.name,
      ouId: role.ouId,
      description: role.description,
      permissions: permissions,
    );
    unawaited(update.mutate((roleId: role.id, data: data)));
  }

  void _add(Role role, RolePermission added) {
    var found = false;
    final next = <RoleResourcePermissions>[];
    for (final entry in role.permissions) {
      if (entry.resourceServerId != added.resourceServerId) {
        next.add(entry);
        continue;
      }
      found = true;
      next.add(
        RoleResourcePermissions(
          resourceServerId: entry.resourceServerId,
          permissions: [...entry.permissions.where((p) => p != added.permission), added.permission],
        ),
      );
    }
    if (!found) {
      next.add(RoleResourcePermissions(resourceServerId: added.resourceServerId, permissions: [added.permission]));
    }
    _save(role, next);
  }

  void _remove(Role role, RolePermission removed) {
    final next = <RoleResourcePermissions>[];
    for (final entry in role.permissions) {
      if (entry.resourceServerId != removed.resourceServerId) {
        next.add(entry);
        continue;
      }
      final kept = entry.permissions.where((p) => p != removed.permission).toList();
      if (kept.isNotEmpty) next.add(RoleResourcePermissions(resourceServerId: entry.resourceServerId, permissions: kept));
    }
    _save(role, next);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final role = _role?.data;
    final update = _update;
    final options = _options?.data;
    final editable = widget.editable && role != null && !role.isReadOnly && update != null;
    return BaseRolePermissions(
      permissions: role?.permissions ?? const [],
      resourceServerNames: {
        for (final (server, _) in options ?? const <(ResourceServer, List<String>)>[]) server.id: server.name,
        ...widget.resourceServerNames,
      },
      availablePermissions: editable && options != null
          ? {
              for (final (server, permissions) in options)
                if (permissions.isNotEmpty) server.id: permissions,
            }
          : null,
      onAdd: editable ? (permission) => _add(role, permission) : null,
      onRemove: editable ? (permission) => _remove(role, permission) : null,
      isLoading: _role?.isLoading ?? !providerFailed,
      isMutating: update?.isLoading ?? false,
      error: providerFailed
          ? ac.t('admin.roles.permissions.error')
          : toManagementErrorMessage(ac.t, _role?.error, 'admin.roles.permissions.error') ??
              toManagementErrorMessage(ac.t, update?.error, 'admin.roles.permissions.update_error') ??
              toManagementErrorMessage(ac.t, _options?.error, 'admin.roles.permissions.options_error'),
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
