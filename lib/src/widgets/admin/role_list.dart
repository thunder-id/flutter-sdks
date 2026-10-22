// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/management_page.dart';
import '../../models/management/role.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';

/// Presentational role list: renders [roles] and reports selection and paging.
class BaseRoleList extends StatelessWidget {
  final List<Role> roles;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<Role>? onSelect;
  final String? selectedRoleId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the roles, the loading and error state, and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<Role>>? builder;

  const BaseRoleList({
    super.key,
    required this.roles,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedRoleId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        AdminListState(
          rows: roles,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? roles.length,
          selectedId: selectedRoleId,
          onPageChange: onPageChange,
          onSelect: onSelect,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'role-list',
      title: title ?? ac.t('admin.roles.list.title'),
      description: description,
      actions: actions,
      children: [
        AdminTable<Role>(
          ac: ac,
          block: 'role-list',
          rows: roles,
          rowId: (role) => role.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.roles.list.empty'),
          onRowTap: onSelect,
          selectedRowId: selectedRoleId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? roles.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(header: ac.t('admin.roles.list.columns.name'), build: (role) => Text(role.name)),
            AdminColumn(
              header: ac.t('admin.roles.list.columns.description'),
              build: (role) => Text(role.description ?? ''),
            ),
            AdminColumn(
              header: ac.t('admin.common.columns.organization_unit'),
              build: (role) => Text(role.ouHandle ?? role.ouId),
            ),
          ],
        ),
      ],
    );
  }
}

/// Role list that fetches its own pages through the management API.
class RoleList extends StatefulWidget {
  final int limit;
  final ValueChanged<Role>? onSelect;
  final String? selectedRoleId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BaseRoleList.builder].
  final AdminWidgetBuilder<AdminListState<Role>>? builder;

  const RoleList({
    super.key,
    this.limit = 20,
    this.onSelect,
    this.selectedRoleId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<RoleList> createState() => _RoleListState();
}

class _RoleListState extends AdminConnectedState<RoleList> {
  int _offset = 0;
  ResourceQuery<ManagementPage<Role>>? _roles;

  @override
  void bind(ManagementResources resources) {
    _roles = own(resources.rolesQuery(limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(RoleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limit != widget.limit) {
      _offset = 0;
      rebind();
    }
  }

  void _changePage(int offset) {
    setState(() => _offset = offset);
    rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _roles;
    return BaseRoleList(
      roles: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.roles.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.roles.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedRoleId: widget.selectedRoleId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
