// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../../api/management/management_display.dart';
import '../../../models/management/management_page.dart';
import '../../../models/management/organization_unit.dart';
import '../../../models/preferences.dart';
import '../../../state/hierarchy_resources.dart';
import '../../../state/management_resources.dart';
import '../../../state/resource_notifiers.dart';
import '../admin_render_state.dart';
import '../internal/admin_connected.dart';
import '../internal/admin_context.dart';
import '../internal/admin_parts.dart';

/// Presentational organization unit list: renders [units] and reports selection and paging.
class BaseOrganizationUnitList extends StatelessWidget {
  final List<BasicOrganizationUnit> units;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<BasicOrganizationUnit>? onSelect;
  final String? selectedUnitId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the units, the loading and error state,
  /// and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<BasicOrganizationUnit>>? builder;

  const BaseOrganizationUnitList({
    super.key,
    required this.units,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedUnitId,
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
          rows: units,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? units.length,
          selectedId: selectedUnitId,
          onPageChange: onPageChange,
          onSelect: onSelect,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'organization-unit-list',
      title: title ?? ac.t('admin.organization_units.list.title'),
      description: description,
      actions: actions,
      children: [
        AdminTable<BasicOrganizationUnit>(
          ac: ac,
          block: 'organization-unit-list',
          rows: units,
          rowId: (unit) => unit.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.organization_units.list.empty'),
          onRowTap: onSelect,
          selectedRowId: selectedUnitId,
          paging: onPageChange == null
              ? null
              : AdminPaging(limit: limit, offset: offset, total: totalResults ?? units.length, onChange: onPageChange!),
          columns: [
            AdminColumn(header: ac.t('admin.organization_units.fields.name'), build: (unit) => Text(unit.name)),
            AdminColumn(
              header: ac.t('admin.organization_units.fields.handle'),
              build: (unit) => Text(unit.handle, style: const TextStyle(fontFamily: 'monospace')),
            ),
            AdminColumn(
              header: ac.t('admin.organization_units.fields.description'),
              build: (unit) => Text(unit.description ?? ''),
            ),
          ],
        ),
      ],
    );
  }
}

/// Organization unit list that fetches its own pages through the management API: the root units,
/// or the children of [parentId] when it is given.
class OrganizationUnitList extends StatefulWidget {
  /// Lists the children of this unit instead of the root units.
  final String? parentId;
  final int limit;
  final ValueChanged<BasicOrganizationUnit>? onSelect;
  final String? selectedUnitId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BaseOrganizationUnitList.builder].
  final AdminWidgetBuilder<AdminListState<BasicOrganizationUnit>>? builder;

  const OrganizationUnitList({
    super.key,
    this.parentId,
    this.limit = 20,
    this.onSelect,
    this.selectedUnitId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<OrganizationUnitList> createState() => _OrganizationUnitListState();
}

class _OrganizationUnitListState extends AdminConnectedState<OrganizationUnitList> {
  int _offset = 0;
  ResourceQuery<ManagementPage<BasicOrganizationUnit>>? _units;

  @override
  void bind(ManagementResources resources) {
    _units = own(resources.organizationUnitsQuery(parentId: widget.parentId, limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(OrganizationUnitList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limit != widget.limit || oldWidget.parentId != widget.parentId) {
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
    final query = _units;
    return BaseOrganizationUnitList(
      units: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.organization_units.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.organization_units.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedUnitId: widget.selectedUnitId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
