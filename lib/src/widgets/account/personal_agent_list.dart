// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/access_status.dart';
import '../../models/management/agent.dart';
import '../../models/management/management_page.dart';
import '../../models/personal_agent.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import '../admin/admin_render_state.dart';
import '../admin/internal/account_lifecycle_parts.dart';
import '../admin/internal/admin_connected.dart';
import '../admin/internal/admin_context.dart';
import '../admin/internal/admin_inputs.dart';
import '../admin/internal/admin_parts.dart';
import '../admin/internal/user_attribute_verification_parts.dart';

/// What [BasePersonalAgentList] hands its `builder`, so the agents can be shown with any UI.
class PersonalAgentListState {
  final List<Agent> agents;
  final bool isLoading;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;
  final int limit;
  final int offset;

  /// The total on the server, or the number of agents given when it is unknown.
  final int totalResults;
  final String? selectedAgentId;

  /// Shows the page that starts at the given offset. `null` when the list is not paginated.
  final ValueChanged<int>? onPageChange;

  /// Chooses an agent. `null` when agents are not selectable.
  final ValueChanged<Agent>? onSelect;

  /// Why suspending every agent failed, translated.
  final String? actionError;
  final bool isSuspendingAll;

  /// Places the owner's suspension on every agent. `null` when the app has not turned it on, or
  /// when there is no agent to suspend. Ask for confirmation first.
  final VoidCallback? onSuspendAll;

  /// How many agents the last suspend-all suspended, once it has run.
  final int? suspendedCount;

  const PersonalAgentListState({
    required this.agents,
    required this.isLoading,
    required this.error,
    required this.limit,
    required this.offset,
    required this.totalResults,
    required this.selectedAgentId,
    required this.onPageChange,
    required this.onSelect,
    required this.actionError,
    required this.isSuspendingAll,
    required this.onSuspendAll,
    required this.suspendedCount,
  });
}

/// The signed-in user's personal agents, rendered from the data it is given. Suspending every agent
/// is offered only when [onSuspendAll] is set, and asks for confirmation first.
/// [PersonalAgentList] loads the data for you.
class BasePersonalAgentList extends StatelessWidget {
  final List<Agent> agents;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final String? title;
  final String? description;
  final int limit;
  final int offset;
  final int? totalResults;
  final String? selectedAgentId;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<Agent>? onSelect;

  /// An already-translated message for a failed suspend-all.
  final String? actionError;
  final bool isSuspendingAll;
  final VoidCallback? onSuspendAll;

  /// How many agents the last suspend-all suspended, shown as a notice once it has run.
  final int? suspendedCount;

  /// Controls rendered next to the title.
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list, from the agents, the loading and error state,
  /// the paging and selection callbacks, and the suspend-all action when the app turned it on.
  final AdminWidgetBuilder<PersonalAgentListState>? builder;

  const BasePersonalAgentList({
    super.key,
    required this.agents,
    this.isLoading = false,
    this.error,
    this.title,
    this.description,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.selectedAgentId,
    this.onPageChange,
    this.onSelect,
    this.actionError,
    this.isSuspendingAll = false,
    this.onSuspendAll,
    this.suspendedCount,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  static const String _block = 'personal-agent-list';

  @override
  Widget build(BuildContext context) {
    final suspendAll = agents.isEmpty ? null : onSuspendAll;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        PersonalAgentListState(
          agents: agents,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? agents.length,
          selectedAgentId: selectedAgentId,
          onPageChange: onPageChange,
          onSelect: onSelect,
          actionError: actionError,
          isSuspendingAll: isSuspendingAll,
          onSuspendAll: suspendAll,
          suspendedCount: suspendedCount,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    final count = suspendedCount;
    return AdminSection(
      ac: ac,
      block: _block,
      title: title ?? ac.t('user.agents.title'),
      description: description ?? ac.t('user.agents.description'),
      actions: [
        ...actions,
        if (suspendAll != null)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('user.agents.suspend_all.action'),
            confirmText: ac.t('user.agents.suspend_all.confirm'),
            identifier: 'thunderid-action-$_block-suspendAll',
            isLoading: isSuspendingAll,
            onConfirm: suspendAll,
          ),
      ],
      children: [
        if (actionError != null) AdminAlert(ac: ac, message: actionError!, block: _block),
        if (count != null)
          AdminNotice(
            ac: ac,
            message: ac.t('user.agents.suspend_all.done', {'count': '$count'}),
            identifier: 'thunderid-admin-$_block-suspended',
          ),
        AdminTable<Agent>(
          ac: ac,
          block: _block,
          rows: agents,
          rowId: (agent) => agent.id,
          isLoading: isLoading,
          error: error,
          emptyText: ac.t('user.agents.list.empty'),
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
            AdminColumn(header: ac.t('user.agents.list.columns.name'), build: (agent) => Text(agent.name)),
            AdminColumn(
              header: ac.t('user.agents.list.columns.status'),
              build: (agent) => Align(
                alignment: Alignment.centerLeft,
                child: AdminAccessStatusLabel(ac: ac, status: agent.status?.value ?? AccessStatusValue.active),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The signed-in user's personal agents, loaded through `/users/me/agents`.
///
/// Suspending every agent at once is off by default: set [suspendable] to offer it. It asks for
/// confirmation first.
class PersonalAgentList extends StatefulWidget {
  final int limit;
  final String? title;
  final String? description;
  final String? selectedAgentId;
  final ValueChanged<Agent>? onSelect;

  /// Lets the user place their own suspension on all their personal agents at once.
  final bool suspendable;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default list. See [BasePersonalAgentList.builder].
  final AdminWidgetBuilder<PersonalAgentListState>? builder;

  const PersonalAgentList({
    super.key,
    this.limit = 20,
    this.title,
    this.description,
    this.selectedAgentId,
    this.onSelect,
    this.suspendable = false,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<PersonalAgentList> createState() => _PersonalAgentListState();
}

class _PersonalAgentListState extends AdminConnectedState<PersonalAgentList> {
  int _offset = 0;
  ResourceQuery<ManagementPage<Agent>>? _agents;
  ResourceMutation<void, SuspendAllMeAgentsResponse>? _suspendAll;

  @override
  void bind(ManagementResources resources) {
    final personal = thunder!.personalAgentResources;
    _agents = own(personal.meAgentsQuery(kind: AgentKind.personal, limit: widget.limit, offset: _offset));
    _suspendAll = own(personal.suspendAllMeAgentsMutation());
  }

  @override
  void didUpdateWidget(PersonalAgentList oldWidget) {
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
    final query = _agents;
    final suspendAll = _suspendAll;
    return BasePersonalAgentList(
      agents: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('user.agents.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'user.agents.list.error'),
      title: widget.title,
      description: widget.description,
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedAgentId: widget.selectedAgentId,
      actionError: toManagementErrorMessage(ac.t, suspendAll?.error, 'user.agents.action.error'),
      isSuspendingAll: suspendAll?.isLoading ?? false,
      onSuspendAll: widget.suspendable && suspendAll != null ? () => unawaited(suspendAll.mutate(null)) : null,
      suspendedCount: suspendAll?.data?.suspendedCount,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
