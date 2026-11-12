// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/administration.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';

/// Which flows [SharedFlowList] lists for an organization unit.
enum SharedFlowOwnership {
  /// The flows shared with the unit.
  shared,

  /// The flows the unit owns.
  owned,

  /// Both.
  all,
}

/// Presentational flow list: renders [flows] (name, handle, type) and reports selection and
/// paging.
class BaseSharedFlowList extends StatelessWidget {
  final List<ManagedFlow> flows;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;

  /// Called with the offset of the page to show. Pagination is hidden when omitted.
  final ValueChanged<int>? onPageChange;

  /// Called when a flow is chosen. Rows are selectable only when set.
  final ValueChanged<ManagedFlow>? onSelect;
  final String? selectedFlowId;

  /// Heading of the list. Pass an empty string to hide it.
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the flows, the loading and error state,
  /// and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<ManagedFlow>>? builder;

  const BaseSharedFlowList({
    super.key,
    required this.flows,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedFlowId,
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
          rows: flows,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? flows.length,
          selectedId: selectedFlowId,
          onPageChange: onPageChange,
          onSelect: onSelect,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'shared-flow-list',
      title: title ?? ac.t('admin.flows.list.title'),
      description: description,
      actions: actions,
      children: [
        AdminTable<ManagedFlow>(
          ac: ac,
          block: 'shared-flow-list',
          rows: flows,
          rowId: (flow) => flow.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('admin.flows.list.empty'),
          onRowTap: onSelect,
          selectedRowId: selectedFlowId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? flows.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(header: ac.t('admin.flows.list.columns.name'), build: (flow) => Text(flow.name)),
            AdminColumn(
              header: ac.t('admin.flows.list.columns.handle'),
              build: (flow) => Text(flow.handle, style: const TextStyle(fontFamily: 'monospace')),
            ),
            AdminColumn(header: ac.t('admin.flows.list.columns.type'), build: (flow) => Text(flow.flowType)),
          ],
        ),
      ],
    );
  }
}

/// Lists the flows shared with the organization unit [ouId], or the ones it owns, or both, a page
/// at a time. Choosing a flow reports it through [onSelect], so the application decides what to
/// open, for example a [FlowVariablesForm] for that flow.
///
/// The server reports whether the unit owns each flow, and a list narrowed by [ownership] filters
/// on it here: it reads the first 100 flows of the unit and pages through the matches. With
/// [SharedFlowOwnership.all], the server pages.
class SharedFlowList extends StatefulWidget {
  final String ouId;

  /// Restricts the list to one flow type (see [FlowTypes]).
  final String? flowType;
  final SharedFlowOwnership ownership;
  final int limit;
  final ValueChanged<ManagedFlow>? onSelect;
  final String? selectedFlowId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BaseSharedFlowList.builder].
  final AdminWidgetBuilder<AdminListState<ManagedFlow>>? builder;

  const SharedFlowList({
    super.key,
    required this.ouId,
    this.flowType,
    this.ownership = SharedFlowOwnership.shared,
    this.limit = 20,
    this.onSelect,
    this.selectedFlowId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<SharedFlowList> createState() => _SharedFlowListState();
}

class _SharedFlowListState extends AdminConnectedState<SharedFlowList> {
  /// The most flows a list narrowed by ownership reads.
  static const int _maxFetch = 100;

  int _offset = 0;
  ResourceQuery<ManagementPage<ManagedFlow>>? _flows;

  bool get _narrowed => widget.ownership != SharedFlowOwnership.all;

  @override
  void bind(ManagementResources resources) {
    _flows = own(
      resources.flowsQuery(
        flowType: widget.flowType,
        ouId: widget.ouId,
        limit: _narrowed ? _maxFetch : widget.limit,
        offset: _narrowed ? 0 : _offset,
      ),
    );
  }

  @override
  void didUpdateWidget(SharedFlowList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ouId != widget.ouId ||
        oldWidget.flowType != widget.flowType ||
        oldWidget.ownership != widget.ownership ||
        oldWidget.limit != widget.limit) {
      _offset = 0;
      rebind();
    }
  }

  void _changePage(int offset) {
    setState(() => _offset = offset);
    if (!_narrowed) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _flows;
    final items = query?.data?.items ?? const <ManagedFlow>[];
    final matching = _narrowed
        ? items
            .where((flow) => flow.isOwnedByOU == (widget.ownership == SharedFlowOwnership.owned))
            .toList(growable: false)
        : items;
    return BaseSharedFlowList(
      flows: _narrowed ? matching.skip(_offset).take(widget.limit).toList(growable: false) : matching,
      totalResults: _narrowed ? matching.length : query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.flows.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.flows.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedFlowId: widget.selectedFlowId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
