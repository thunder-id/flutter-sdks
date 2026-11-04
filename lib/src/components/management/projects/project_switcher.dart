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
import '../internal/admin_inputs.dart';
import '../internal/admin_parts.dart';

/// What [BaseProjectSwitcher] and [ProjectSwitcher] hand their `builder`.
class ProjectSwitcherState {
  /// The projects on the current page.
  final List<Project> projects;

  /// The id of the current project, or `null` when none is chosen.
  final String? currentId;
  final bool isLoading;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;
  final int limit;
  final int offset;
  final int totalResults;

  /// Shows the page that starts at the given offset. `null` when the list is not paginated.
  final ValueChanged<int>? onPageChange;

  /// Makes a project the current one.
  final ValueChanged<Project> onSelect;

  /// Clears the current project. `null` when clearing is not offered.
  final VoidCallback? onClear;

  const ProjectSwitcherState({
    required this.projects,
    required this.currentId,
    required this.isLoading,
    required this.error,
    required this.limit,
    required this.offset,
    required this.totalResults,
    required this.onPageChange,
    required this.onSelect,
    required this.onClear,
  });
}

/// Presentational project switcher: renders [projects] with the current one marked. Choosing
/// another calls [onSelect]; [onClear], when set, offers to clear the choice.
class BaseProjectSwitcher extends StatelessWidget {
  final List<Project> projects;
  final String? currentId;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<Project> onSelect;
  final VoidCallback? onClear;
  final String? title;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the projects, the current one, the
  /// loading and error state, the paging, [onSelect] and [onClear].
  final AdminWidgetBuilder<ProjectSwitcherState>? builder;

  const BaseProjectSwitcher({
    super.key,
    required this.projects,
    required this.currentId,
    required this.onSelect,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onClear,
    this.title,
    this.preferences,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        ProjectSwitcherState(
          projects: projects,
          currentId: currentId,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? projects.length,
          onPageChange: onPageChange,
          onSelect: onSelect,
          onClear: onClear,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'project-switcher',
      title: title ?? ac.t('admin.projects.list.title'),
      actions: [
        if (onClear != null && currentId != null)
          AdminButton(
            ac: ac,
            label: ac.t('admin.projects.switcher.clear'),
            identifier: 'thunderid-action-project-switcher-clear',
            variant: AdminButtonVariant.text,
            onPressed: onClear,
          ),
      ],
      children: [
        AdminTable<Project>(
          ac: ac,
          block: 'project-switcher',
          rows: projects,
          rowId: (project) => project.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.projects.list.empty'),
          onRowTap: onSelect,
          selectedRowId: currentId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? projects.length,
                  onChange: onPageChange!,
                ),
          trailing: (project) => project.id == currentId
              ? Text(
                  ac.t('admin.projects.switcher.current'),
                  key: Key('thunderid-admin-project-switcher-current-${project.id}'),
                  style: TextStyle(color: ac.colors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                )
              : const SizedBox.shrink(),
          columns: [
            AdminColumn(
              header: ac.t('admin.projects.fields.display_name'),
              build: (project) => Text(project.displayName),
            ),
            AdminColumn(
              header: ac.t('admin.projects.fields.handle'),
              build: (project) => Text(project.handle, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Lists the projects and lets the user pick the current one.
///
/// This is client-side context, not a sign-in: choosing a project sets
/// `ThunderIDState.currentProject` (kept in memory), then calls [onSelect]. A project is not an
/// organization unit: only applications and agents take one. [ApplicationList] and [AgentList]
/// list the current project's applications and agents, and [ApplicationCreate] and [AgentCreate]
/// given no organization unit create in it. Other lists and creates are not affected. Only the
/// control plane serves projects.
class ProjectSwitcher extends StatefulWidget {
  final int limit;

  /// Called with the project once it is the current one.
  final ValueChanged<Project>? onSelect;
  final String? title;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseProjectSwitcher.builder].
  final AdminWidgetBuilder<ProjectSwitcherState>? builder;

  const ProjectSwitcher({super.key, this.limit = 20, this.onSelect, this.title, this.preferences, this.builder});

  @override
  State<ProjectSwitcher> createState() => _ProjectSwitcherState();
}

class _ProjectSwitcherState extends AdminConnectedState<ProjectSwitcher> {
  int _offset = 0;
  ResourceQuery<ManagementPage<Project>>? _projects;

  @override
  void bind(ManagementResources resources) {
    _projects = own(resources.projectsQuery(limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(ProjectSwitcher oldWidget) {
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

  void _select(Project project) {
    thunder?.setCurrentProject(project);
    widget.onSelect?.call(project);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _projects;
    return BaseProjectSwitcher(
      projects: query?.data?.items ?? const [],
      currentId: thunder?.currentProject?.id,
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.projects.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.projects.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: _select,
      onClear: () => thunder?.setCurrentProject(null),
      title: widget.title,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
