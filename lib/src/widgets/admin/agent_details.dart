// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../management/management_display.dart';
import '../../models/management/administration.dart';
import '../../models/management/agent.dart';
import '../../models/management/group.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/account_lifecycle_parts.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// Presentational view of one agent: overview, group memberships, and roles.
///
/// Delete appears only when [onDelete] is set, and never for a read-only agent. It asks for
/// confirmation first (spec "UI", requirement 6). The account lifecycle actions in
/// [lifecycleActions] appear only when [onLifecycleAction] is set; they change only runtime
/// state, so they apply to read-only agents too.
class BaseAgentDetails extends StatelessWidget {
  final Agent? agent;
  final List<MembershipGroup> groups;

  /// Names of the roles assigned to the agent.
  final List<String> roles;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onDelete;
  final bool isDeleting;

  /// The account lifecycle actions to offer (suspend, unsuspend, unlock), shown only with
  /// [onLifecycleAction].
  final List<AccountLifecycleAction> lifecycleActions;

  /// Runs an account lifecycle action. Suspending and unsuspending ask for confirmation first,
  /// and a suspension takes an optional operator note.
  final AccountLifecycleCallback? onLifecycleAction;
  final bool isRunningLifecycleAction;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the agent, its groups and roles, the loading and error state, and the delete and lifecycle callbacks.
  final AdminWidgetBuilder<AgentDetailsState>? builder;

  const BaseAgentDetails({
    super.key,
    this.agent,
    this.groups = const [],
    this.roles = const [],
    this.isLoading = false,
    this.error,
    this.onDelete,
    this.isDeleting = false,
    this.lifecycleActions = const [],
    this.onLifecycleAction,
    this.isRunningLifecycleAction = false,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, preferences);
    final agent = this.agent;
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        AgentDetailsState(
          agent: agent,
          groups: groups,
          roles: roles,
          isLoading: isLoading,
          error: error,
          isDeleting: isDeleting,
          onDelete: agent != null && !agent.isReadOnly ? onDelete : null,
          lifecycleActions: onLifecycleAction != null && agent != null ? lifecycleActions : const [],
          onLifecycleAction: agent != null ? onLifecycleAction : null,
          isRunningLifecycleAction: isRunningLifecycleAction,
        ),
      );
    }
    if (agent == null) {
      return AdminSection(
        ac: ac,
        block: 'agent-details',
        children: [
          if (isLoading)
            AdminLoading(ac: ac)
          else
            AdminAlert(ac: ac, block: 'agent-details', message: error ?? ac.t('admin.common.errors.not_found')),
        ],
      );
    }

    final clientId = agent.clientId;
    final status = agent.status?.value;
    final onLifecycle = onLifecycleAction;
    return AdminSection(
      ac: ac,
      block: 'agent-details',
      title: agent.name,
      description: agent.description,
      actions: [
        ...actions,
        if (onLifecycle != null && lifecycleActions.isNotEmpty)
          AdminLifecycleButtons(
            ac: ac,
            actions: lifecycleActions,
            name: agent.name,
            block: 'agent-details',
            onAction: onLifecycle,
            isRunning: isRunningLifecycleAction,
            collectsOperatorNote: true,
          ),
        if (onDelete != null && !agent.isReadOnly)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('admin.agents.details.delete.action'),
            confirmText: ac.t('admin.agents.details.delete.confirm', {'name': agent.name}),
            identifier: 'thunderid-action-agent-details-delete',
            isLoading: isDeleting,
            onConfirm: onDelete!,
          ),
      ],
      children: [
        if (error != null) AdminAlert(ac: ac, message: error!, block: 'agent-details'),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.agents.details.overview'),
          child: AdminDetailList(
            ac: ac,
            items: [
              (ac.t('admin.agents.details.type'), Text(agent.type)),
              (ac.t('admin.agents.details.owner'), Text(agent.owner ?? ac.t('admin.agents.details.no_owner'))),
              (ac.t('admin.common.columns.organization_unit'), Text(agent.ouHandle ?? agent.ouId)),
              if (status != null)
                (
                  ac.t('admin.common.columns.status'),
                  Align(alignment: Alignment.centerLeft, child: AdminAccessStatusLabel(ac: ac, status: status)),
                ),
              if (clientId != null)
                (
                  ac.t('admin.agents.list.columns.client_id'),
                  Row(
                    children: [
                      Flexible(
                        child: SelectableText(clientId, style: const TextStyle(fontFamily: 'monospace')),
                      ),
                      AdminButton(
                        ac: ac,
                        label: ac.t('elements.display.copyable_text.copy'),
                        identifier: 'thunderid-action-agent-details-copyClientId',
                        variant: AdminButtonVariant.text,
                        onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: clientId))),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.agents.details.groups'),
          child: AdminChipList(
            ac: ac,
            label: ac.t('admin.agents.details.groups'),
            emptyText: ac.t('admin.agents.details.no_groups'),
            items: [for (final group in groups) AdminChip(id: group.id, label: group.name)],
          ),
        ),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.agents.details.roles'),
          child: AdminChipList(
            ac: ac,
            label: ac.t('admin.agents.details.roles'),
            emptyText: ac.t('admin.agents.details.no_roles'),
            items: [for (final role in roles) AdminChip(id: role, label: role)],
          ),
        ),
      ],
    );
  }
}

/// Agent details that loads the agent, its groups, and its roles through the management API.
///
/// Changing data is off by default: set [deletable] to offer delete (with confirmation) and
/// [lifecycleActions] to offer suspend, unsuspend and unlock.
class AgentDetails extends StatefulWidget {
  final String agentId;
  final bool deletable;

  /// Whether the agent can be suspended, unsuspended and unlocked from this view. Each action
  /// runs through its administration flow and is offered only when the agent's status allows it
  /// and the server configures that flow. The configured flows are read only while this is on,
  /// and reading them needs a token that may read the server configuration.
  final bool lifecycleActions;
  final VoidCallback? onDeleted;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseAgentDetails.builder].
  final AdminWidgetBuilder<AgentDetailsState>? builder;

  const AgentDetails({
    super.key,
    required this.agentId,
    this.deletable = false,
    this.lifecycleActions = false,
    this.onDeleted,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<AgentDetails> createState() => _AgentDetailsState();
}

class _AgentDetailsState extends AdminConnectedState<AgentDetails> {
  ResourceQuery<Agent>? _agent;
  ResourceQuery<ManagementPage<MembershipGroup>>? _groups;
  ResourceQuery<ManagementPage<String>>? _roles;
  ResourceMutation<String, void>? _delete;
  AdminLifecycleBinding? _lifecycle;

  @override
  void bind(ManagementResources resources) {
    _agent = own(resources.agentQuery(widget.agentId));
    _groups = own(resources.agentGroupsQuery(widget.agentId, limit: 100));
    _roles = own(resources.agentRolesQuery(widget.agentId, limit: 100));
    _delete = own(resources.deleteAgentMutation(onSuccess: (_, __) => widget.onDeleted?.call()));
    _lifecycle = AdminLifecycleBinding(
      resources,
      AccountLifecycleSubjectKind.agent,
      enabled: widget.lifecycleActions,
      own: own,
    );
  }

  @override
  void didUpdateWidget(AgentDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentId != widget.agentId || oldWidget.lifecycleActions != widget.lifecycleActions) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final delete = _delete;
    final lifecycle = _lifecycle;
    final agent = _agent?.data;
    return BaseAgentDetails(
      agent: agent,
      groups: _groups?.data?.items ?? const [],
      roles: _roles?.data?.items ?? const [],
      isLoading: _agent?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.agents.details.error')
          : toManagementErrorMessage(ac.t, _agent?.error, 'admin.agents.details.error') ??
              toManagementErrorMessage(ac.t, delete?.error, 'admin.agents.details.delete.error') ??
              lifecycle?.error(ac),
      isDeleting: delete?.isLoading ?? false,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.agentId)) : null,
      lifecycleActions: lifecycle?.actions(agent?.status?.value) ?? const [],
      onLifecycleAction: lifecycle?.handler(widget.agentId),
      isRunningLifecycleAction: lifecycle?.isRunning ?? false,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
