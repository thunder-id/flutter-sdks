// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../../api/management/management_display.dart';
import '../../../models/management/management_page.dart';
import '../../../models/management/project.dart';
import '../../../models/preferences.dart';
import '../../../state/hierarchy_resources.dart';
import '../../../state/management_resources.dart';
import '../../../state/resource_notifiers.dart';
import '../admin_render_state.dart';
import '../internal/admin_connected.dart';
import '../internal/admin_context.dart';
import '../internal/admin_parts.dart';
import '../internal/hierarchy_support.dart';

/// Presentational project list: renders [projects] and reports selection and paging.
class BaseProjectList extends StatelessWidget {
  final List<Project> projects;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<Project>? onSelect;
  final String? selectedProjectId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the projects, the loading and error state,
  /// and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<Project>>? builder;

  const BaseProjectList({
    super.key,
    required this.projects,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedProjectId,
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
          rows: projects,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? projects.length,
          selectedId: selectedProjectId,
          onPageChange: onPageChange,
          onSelect: onSelect,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'project-list',
      title: title ?? ac.t('admin.projects.list.title'),
      description: description,
      actions: actions,
      children: [
        AdminTable<Project>(
          ac: ac,
          block: 'project-list',
          rows: projects,
          rowId: (project) => project.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.projects.list.empty'),
          onRowTap: onSelect,
          selectedRowId: selectedProjectId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? projects.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(
              header: ac.t('admin.projects.fields.display_name'),
              build: (project) => Text(project.displayName),
            ),
            AdminColumn(
              header: ac.t('admin.projects.fields.handle'),
              build: (project) => Text(project.handle, style: const TextStyle(fontFamily: 'monospace')),
            ),
            AdminColumn(
              header: ac.t('admin.projects.details.created'),
              build: (project) => Text(formatAdminTimestamp(project.createdAt)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Project list that fetches its own pages through the management API. Only the control plane
/// serves projects.
class ProjectList extends StatefulWidget {
  final int limit;
  final ValueChanged<Project>? onSelect;
  final String? selectedProjectId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BaseProjectList.builder].
  final AdminWidgetBuilder<AdminListState<Project>>? builder;

  const ProjectList({
    super.key,
    this.limit = 20,
    this.onSelect,
    this.selectedProjectId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<ProjectList> createState() => _ProjectListState();
}

class _ProjectListState extends AdminConnectedState<ProjectList> {
  int _offset = 0;
  ResourceQuery<ManagementPage<Project>>? _projects;

  @override
  void bind(ManagementResources resources) {
    _projects = own(resources.projectsQuery(limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(ProjectList oldWidget) {
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
    final query = _projects;
    return BaseProjectList(
      projects: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.projects.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.projects.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedProjectId: widget.selectedProjectId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
