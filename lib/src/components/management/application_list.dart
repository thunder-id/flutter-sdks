// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../api/management/management_display.dart';
import '../../models/management/application.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';
import 'internal/application_form.dart';

/// Presentational application list: renders [applications] (name, client ID, type, status) and
/// reports selection and paging. The server offers no search on applications, so there is none.
class BaseApplicationList extends StatelessWidget {
  final List<BasicApplication> applications;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<BasicApplication>? onSelect;
  final String? selectedApplicationId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the applications, the loading and error state, and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<BasicApplication>>? builder;

  const BaseApplicationList({
    super.key,
    required this.applications,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedApplicationId,
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
          rows: applications,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? applications.length,
          selectedId: selectedApplicationId,
          onPageChange: onPageChange,
          onSelect: onSelect,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'application-list',
      title: title ?? ac.t('admin.applications.list.title'),
      description: description,
      actions: actions,
      children: [
        AdminTable<BasicApplication>(
          ac: ac,
          block: 'application-list',
          rows: applications,
          rowId: (application) => application.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.applications.list.empty'),
          onRowTap: onSelect,
          selectedRowId: selectedApplicationId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? applications.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(
              header: ac.t('admin.applications.list.columns.name'),
              build: (application) => Text(application.name),
            ),
            AdminColumn(
              header: ac.t('admin.applications.list.columns.client_id'),
              build: (application) =>
                  Text(application.clientId ?? '', style: const TextStyle(fontFamily: 'monospace')),
            ),
            AdminColumn(
              header: ac.t('admin.applications.list.columns.type'),
              build: (application) => Text(application.template ?? applicationTypeLabel(ac, application.type)),
            ),
            AdminColumn(
              header: ac.t('admin.applications.list.columns.status'),
              build: (application) => Text(applicationStatusLabel(ac, application.status)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Application list that fetches its own pages through the management API.
///
/// The server guards applications with the root `system` permission; without it the list shows
/// the translated forbidden message. Check it up front with
/// `ThunderIDProvider.of(context).grantedPermissions()` and `can('system')` to decide whether to
/// show the list at all.
///
/// With [projectId], or else the current project (`ThunderIDState.currentProject`, set by a
/// [ProjectSwitcher]), it lists that project's applications: the ones its root organization unit
/// owns, followed by the ones shared into it.
class ApplicationList extends StatefulWidget {
  final int limit;

  /// Lists this project's applications. Defaults to the current project when one is chosen;
  /// otherwise every application is listed.
  final String? projectId;
  final ValueChanged<BasicApplication>? onSelect;
  final String? selectedApplicationId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BaseApplicationList.builder].
  final AdminWidgetBuilder<AdminListState<BasicApplication>>? builder;

  const ApplicationList({
    super.key,
    this.limit = 20,
    this.projectId,
    this.onSelect,
    this.selectedApplicationId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<ApplicationList> createState() => _ApplicationListState();
}

class _ApplicationListState extends AdminConnectedState<ApplicationList> {
  int _offset = 0;
  ResourceQuery<ManagementPage<BasicApplication>>? _applications;
  String? _boundProjectId;

  /// The project scoping the list: the one passed, else the current one.
  String? get _projectId => widget.projectId ?? thunder?.currentProject?.id;

  @override
  void bind(ManagementResources resources) {
    _boundProjectId = _projectId;
    _applications = own(
      resources.applicationsQuery(projectId: _boundProjectId, limit: widget.limit, offset: _offset),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (resources != null && _projectId != _boundProjectId) _restart();
  }

  @override
  void didUpdateWidget(ApplicationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limit != widget.limit || _projectId != _boundProjectId) _restart();
  }

  void _restart() {
    _offset = 0;
    rebind();
  }

  void _changePage(int offset) {
    setState(() => _offset = offset);
    rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _applications;
    return BaseApplicationList(
      applications: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.applications.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.applications.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedApplicationId: widget.selectedApplicationId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
