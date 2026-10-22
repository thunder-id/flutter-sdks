// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../management/management_filter.dart';
import '../../models/management/agent.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'identity_candidate.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';
import 'internal/admin_search_bar.dart';

/// Presentational agent list: renders [agents] and reports selection and paging.
class BaseAgentList extends StatelessWidget {
  final List<Agent> agents;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<Agent>? onSelect;
  final String? selectedAgentId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// The search currently applied, if any. While set, an empty page says nothing matched.
  final AdminSearch? search;

  /// The attributes that can be searched, with translated labels.
  final List<AdminSelectOption> searchAttributes;

  /// Applies a search on the server, or clears it with `null`. The search form shows only when this
  /// and [searchAttributes] are set.
  final ValueChanged<AdminSearch?>? onSearch;

  /// Builds custom UI in place of the default list, from the agents, the loading and error state, and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<Agent>>? builder;

  const BaseAgentList({
    super.key,
    required this.agents,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedAgentId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.search,
    this.searchAttributes = const [],
    this.onSearch,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        AdminListState(
          rows: agents,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? agents.length,
          selectedId: selectedAgentId,
          onPageChange: onPageChange,
          onSelect: onSelect,
          search: search,
          searchAttributes: searchAttributes,
          onSearch: onSearch,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    return AdminSection(
      ac: ac,
      block: 'agent-list',
      title: title ?? ac.t('admin.agents.list.title'),
      description: description,
      actions: actions,
      children: [
        if (onSearch != null && searchAttributes.isNotEmpty)
          AdminSearchBar(
            ac: ac,
            block: 'agent-list',
            attributes: searchAttributes,
            search: search,
            onSearch: onSearch!,
          ),
        AdminTable<Agent>(
          ac: ac,
          block: 'agent-list',
          rows: agents,
          rowId: (agent) => agent.id,
          isLoading: isLoading,
          error: error,
          emptyText: search == null
              ? ac.t('admin.agents.list.empty')
              : ac.t('admin.common.search.no_results', {'value': search!.value}),
          onRowTap: onSelect,
          selectedRowId: selectedAgentId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? agents.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(header: ac.t('admin.agents.list.columns.name'), build: (agent) => Text(agent.name)),
            AdminColumn(header: ac.t('admin.agents.list.columns.type'), build: (agent) => Text(agent.type)),
            AdminColumn(
              header: ac.t('admin.agents.list.columns.client_id'),
              build: (agent) => Text(agent.clientId ?? '', style: const TextStyle(fontFamily: 'monospace')),
            ),
            AdminColumn(
              header: ac.t('admin.common.columns.organization_unit'),
              build: (agent) => Text(agent.ouHandle ?? agent.ouId),
            ),
          ],
        ),
      ],
    );
  }
}

/// Agent list that fetches its own pages through the management API.
class AgentList extends StatefulWidget {
  final int limit;
  final ValueChanged<Agent>? onSelect;
  final String? selectedAgentId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Whether to show a search form. The server matches the whole value of the chosen attribute.
  final bool searchable;

  /// The attributes to offer in the search form. Defaults to the list's own.
  final List<AdminSelectOption>? searchAttributes;

  /// Builds custom UI in place of the default list. See [BaseAgentList.builder].
  final AdminWidgetBuilder<AdminListState<Agent>>? builder;

  const AgentList({
    super.key,
    this.limit = 20,
    this.onSelect,
    this.selectedAgentId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.searchable = true,
    this.searchAttributes,
    this.builder,
  });

  @override
  State<AgentList> createState() => _AgentListState();
}

class _AgentListState extends AdminConnectedState<AgentList> {
  int _offset = 0;
  AdminSearch? _search;
  ResourceQuery<ManagementPage<Agent>>? _agents;

  @override
  void bind(ManagementResources resources) {
    _agents = own(resources.agentsQuery(filter: _searchFilter, limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(AgentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limit != widget.limit) {
      _offset = 0;
      rebind();
    }
  }

  String? get _searchFilter {
    final search = _search;
    return search == null ? null : ManagementFilter.equality(search.attribute, search.value);
  }

  void _applySearch(AdminSearch? search) {
    setState(() {
      _search = search;
      _offset = 0;
    });
    rebind();
  }

  void _changePage(int offset) {
    setState(() => _offset = offset);
    rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _agents;
    return BaseAgentList(
      agents: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.agents.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.agents.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedAgentId: widget.selectedAgentId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      search: _search,
      searchAttributes: widget.searchAttributes ??
          [AdminSelectOption(value: 'name', label: ac.t('admin.agents.list.search.name'))],
      onSearch: widget.searchable ? _applySearch : null,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
