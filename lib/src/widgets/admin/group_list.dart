// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/group.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';

/// Presentational group list: renders [groups] and reports selection and paging.
class BaseGroupList extends StatelessWidget {
  final List<Group> groups;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<Group>? onSelect;
  final String? selectedGroupId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the groups, the loading and error state, and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<Group>>? builder;

  const BaseGroupList({
    super.key,
    required this.groups,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedGroupId,
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
          rows: groups,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? groups.length,
          selectedId: selectedGroupId,
          onPageChange: onPageChange,
          onSelect: onSelect,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'group-list',
      title: title ?? ac.t('admin.groups.list.title'),
      description: description,
      actions: actions,
      children: [
        AdminTable<Group>(
          ac: ac,
          block: 'group-list',
          rows: groups,
          rowId: (group) => group.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.groups.list.empty'),
          onRowTap: onSelect,
          selectedRowId: selectedGroupId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? groups.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(header: ac.t('admin.groups.list.columns.name'), build: (group) => Text(group.name)),
            AdminColumn(
              header: ac.t('admin.groups.list.columns.description'),
              build: (group) => Text(group.description ?? ''),
            ),
            AdminColumn(
              header: ac.t('admin.common.columns.organization_unit'),
              build: (group) => Text(group.ouHandle ?? group.ouId),
            ),
          ],
        ),
      ],
    );
  }
}

/// Group list that fetches its own pages through the management API.
class GroupList extends StatefulWidget {
  final int limit;
  final ValueChanged<Group>? onSelect;
  final String? selectedGroupId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BaseGroupList.builder].
  final AdminWidgetBuilder<AdminListState<Group>>? builder;

  const GroupList({
    super.key,
    this.limit = 20,
    this.onSelect,
    this.selectedGroupId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<GroupList> createState() => _GroupListState();
}

class _GroupListState extends AdminConnectedState<GroupList> {
  int _offset = 0;
  ResourceQuery<ManagementPage<Group>>? _groups;

  @override
  void bind(ManagementResources resources) {
    _groups = own(resources.groupsQuery(limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(GroupList oldWidget) {
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
    final query = _groups;
    return BaseGroupList(
      groups: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.groups.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.groups.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedGroupId: widget.selectedGroupId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
