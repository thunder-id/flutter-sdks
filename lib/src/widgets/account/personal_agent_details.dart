// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/agent.dart';
import '../../models/management/application.dart';
import '../../models/personal_agent.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/personal_agent_resources.dart';
import '../../state/resource_notifiers.dart';
import '../admin/admin_render_state.dart';
import '../admin/internal/admin_connected.dart';
import '../admin/internal/admin_context.dart';
import '../admin/internal/admin_inputs.dart';
import '../admin/internal/admin_parts.dart';
import '../admin/internal/user_attribute_verification_parts.dart';
import 'internal/personal_agent_parts.dart';

/// What [BasePersonalAgentDetails] hands its `builder`, so the agent can be shown with any UI. An
/// action is `null` when the app has not turned it on, or when it does not apply to the agent.
class PersonalAgentDetailsState {
  final Agent? agent;

  /// The agent's OAuth settings. `null` when it has no OAuth client.
  final OAuth2Config? oauth;
  final bool isLoading;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;
  final bool isUpdating;
  final bool isDeleting;
  final bool isChangingSuspension;

  /// Replaces the editable part of the agent, and completes with whether it was saved.
  /// [PersonalAgentFormValues] builds the request.
  final Future<bool> Function(UpdateMeAgentRequest request)? onUpdate;

  /// Deletes the agent. Ask for confirmation first.
  final VoidCallback? onDelete;

  /// Places the owner's suspension on the agent. Offered unless the owner already holds it
  /// suspended. Ask for confirmation first.
  final VoidCallback? onSuspend;

  /// Lifts the owner's suspension of the agent. Offered only while the owner holds it suspended.
  final VoidCallback? onUnsuspend;

  const PersonalAgentDetailsState({
    required this.agent,
    required this.oauth,
    required this.isLoading,
    required this.error,
    required this.isUpdating,
    required this.isDeleting,
    required this.isChangingSuspension,
    required this.onUpdate,
    required this.onDelete,
    required this.onSuspend,
    required this.onUnsuspend,
  });
}

/// One of the signed-in user's personal agents with the actions its owner can take, rendered from
/// the data it is given. Editing, deleting and the owner's suspension are each offered only when
/// their handler is set; editing and deleting never for a read-only agent. Suspending and deleting
/// ask for confirmation first. [PersonalAgentDetails] loads the data for you.
class BasePersonalAgentDetails extends StatefulWidget {
  final Agent? agent;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final bool isUpdating;
  final bool isDeleting;
  final bool isChangingSuspension;

  /// Saves the edited agent and completes with whether it was saved. The edit form stays open with
  /// the changes until it completes with `true`.
  final Future<bool> Function(UpdateMeAgentRequest request)? onUpdate;
  final VoidCallback? onDelete;
  final VoidCallback? onSuspend;
  final VoidCallback? onUnsuspend;

  /// Controls rendered next to the agent's name.
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the agent, its OAuth settings, the loading
  /// and error state, and the actions the app has turned on that apply to it.
  final AdminWidgetBuilder<PersonalAgentDetailsState>? builder;

  const BasePersonalAgentDetails({
    super.key,
    this.agent,
    this.isLoading = false,
    this.error,
    this.isUpdating = false,
    this.isDeleting = false,
    this.isChangingSuspension = false,
    this.onUpdate,
    this.onDelete,
    this.onSuspend,
    this.onUnsuspend,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<BasePersonalAgentDetails> createState() => _BasePersonalAgentDetailsState();
}

/// An open edit form, and the agent it was opened for.
typedef _Draft = ({String agentId, PersonalAgentFormValues values});

class _BasePersonalAgentDetailsState extends State<BasePersonalAgentDetails> {
  static const String _block = 'personal-agent-details';

  /// The draft remembers which agent it was opened for, so switching the agent closes the form
  /// instead of saving one agent's values onto another. Switching also discards it, so coming back
  /// to an agent starts from its stored values.
  _Draft? _draft;
  PersonalAgentConfirmation? _confirmation;

  @override
  void didUpdateWidget(BasePersonalAgentDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A draft and a pending confirmation belong to the agent they were opened for.
    if (oldWidget.agent?.id != widget.agent?.id) {
      _draft = null;
      _confirmation = null;
    }
  }

  /// Keeps the changes until the update succeeds, so a failed save can be corrected and retried.
  Future<void> _save(
    Future<bool> Function(UpdateMeAgentRequest request) update,
    UpdateMeAgentRequest request,
    String agentId,
  ) async {
    final saved = await update(request);
    if (saved && mounted && _draft?.agentId == agentId) setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final isWritable = agent != null && !agent.isReadOnly;
    final suspension = agent == null ? null : MeAgentSuspensionAction.available(agent.status);
    final update = isWritable ? widget.onUpdate : null;
    final delete = isWritable ? widget.onDelete : null;
    final suspend = suspension == MeAgentSuspensionAction.suspend ? widget.onSuspend : null;
    final unsuspend = suspension == MeAgentSuspensionAction.unsuspend ? widget.onUnsuspend : null;
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        PersonalAgentDetailsState(
          agent: agent,
          oauth: agent?.oauthConfig,
          isLoading: widget.isLoading,
          error: widget.error,
          isUpdating: widget.isUpdating,
          isDeleting: widget.isDeleting,
          isChangingSuspension: widget.isChangingSuspension,
          onUpdate: update,
          onDelete: delete,
          onSuspend: suspend,
          onUnsuspend: unsuspend,
        ),
      );
    }
    final ac = AdminContext.of(context, widget.preferences);
    if (agent == null) {
      return AdminSection(
        ac: ac,
        block: _block,
        children: [
          if (widget.isLoading)
            AdminLoading(ac: ac)
          else
            AdminAlert(ac: ac, block: _block, message: widget.error ?? ac.t('admin.common.errors.not_found')),
        ],
      );
    }
    final draft = _draft?.agentId == agent.id ? _draft : null;
    final confirmation = _confirmation;
    final headerActions = [
      ...widget.actions,
      if (confirmation == null && update != null && draft == null)
        AdminButton(
          ac: ac,
          label: ac.t('user.agents.edit.action'),
          identifier: 'thunderid-action-$_block-edit',
          variant: AdminButtonVariant.text,
          onPressed: () => setState(
            () => _draft = (agentId: agent.id, values: PersonalAgentFormValues.fromAgent(agent)),
          ),
        ),
      if (confirmation == null && (suspend != null || unsuspend != null || delete != null))
        PersonalAgentActionMenu(
          ac: ac,
          isBusy: widget.isChangingSuspension || widget.isDeleting,
          onUnsuspend: unsuspend,
          onSuspend: suspend == null ? null : () => setState(() => _confirmation = PersonalAgentConfirmation.suspend),
          onDelete: delete == null ? null : () => setState(() => _confirmation = PersonalAgentConfirmation.delete),
        ),
    ];
    return AdminSection(
      ac: ac,
      block: _block,
      children: [
        PersonalAgentHeader(ac: ac, title: agent.name, description: agent.description, actions: headerActions),
        if (confirmation != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PersonalAgentConfirmBar(
              ac: ac,
              confirmation: confirmation,
              name: agent.name,
              onCancel: () => setState(() => _confirmation = null),
              onConfirm: () {
                setState(() => _confirmation = null);
                (confirmation == PersonalAgentConfirmation.suspend ? suspend : delete)?.call();
              },
            ),
          ),
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: _block),
        for (final (index, notice) in personalAgentSuspensionNotices(ac, agent).indexed)
          AdminNotice(ac: ac, message: notice, identifier: 'thunderid-admin-$_block-suspension-$index'),
        if (draft != null && update != null)
          PersonalAgentEditForm(
            key: ValueKey('$_block-edit-${agent.id}'),
            ac: ac,
            values: draft.values,
            onChanged: (values) => setState(() => _draft = (agentId: agent.id, values: values)),
            isUpdating: widget.isUpdating,
            onCancel: () => setState(() => _draft = null),
            onSave: (values) => unawaited(_save(update, values.updateRequest(agent), agent.id)),
          )
        else ...[
          AdminPanel(
            ac: ac,
            title: ac.t('user.agents.details.overview'),
            child: AdminDetailList(
              ac: ac,
              items: [for (final (label, value) in personalAgentOverview(ac, agent)) (label, Text(value))],
            ),
          ),
          AdminPanel(
            ac: ac,
            title: ac.t('user.agents.details.attributes'),
            child: switch (personalAgentAttributes(agent)) {
              final attributes when attributes.isEmpty => AdminMuted(ac: ac, text: ac.t('user.agents.details.none')),
              final attributes => AdminDetailList(
                  ac: ac,
                  items: [for (final (label, value) in attributes) (label, Text(value))],
                ),
            },
          ),
        ],
      ],
    );
  }
}

/// One of the signed-in user's personal agents, loaded through `/users/me/agents`.
///
/// Editing, deleting and suspending are each off by default: set [editable] to let the user edit
/// the agent's name, attributes, description, redirect URIs and grant types, [deletable] to let
/// them delete it, and [suspendable] to let them place or lift their own suspension of it.
/// Suspending and deleting ask for confirmation first.
class PersonalAgentDetails extends StatefulWidget {
  final String agentId;
  final bool editable;
  final bool deletable;
  final bool suspendable;

  /// Called once the agent is deleted, for example to navigate away.
  final VoidCallback? onDeleted;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BasePersonalAgentDetails.builder].
  final AdminWidgetBuilder<PersonalAgentDetailsState>? builder;

  const PersonalAgentDetails({
    super.key,
    required this.agentId,
    this.editable = false,
    this.deletable = false,
    this.suspendable = false,
    this.onDeleted,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<PersonalAgentDetails> createState() => _PersonalAgentDetailsState();
}

class _PersonalAgentDetailsState extends AdminConnectedState<PersonalAgentDetails> {
  ResourceQuery<Agent>? _agent;
  ResourceMutation<UpdateMeAgentVariables, Agent>? _update;
  ResourceMutation<String, void>? _delete;
  ResourceMutation<MeAgentSuspensionVariables, void>? _suspension;

  /// The agent this widget deleted, shown as gone from then on rather than as the last record read.
  String? _deletedId;

  @override
  void bind(ManagementResources resources) {
    final personal = thunder!.personalAgentResources;
    _agent = own(personal.meAgentQuery(widget.agentId));
    _update = own(personal.updateMeAgentMutation());
    _delete = own(
      personal.deleteMeAgentMutation(
        onSuccess: (_, agentId) {
          if (!mounted) return;
          setState(() => _deletedId = agentId);
          if (agentId == widget.agentId) widget.onDeleted?.call();
        },
      ),
    );
    _suspension = own(personal.meAgentSuspensionMutation());
  }

  @override
  void didUpdateWidget(PersonalAgentDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentId != widget.agentId) rebind();
  }

  VoidCallback? _changeSuspension(MeAgentSuspensionAction action) {
    final suspension = _suspension;
    if (!widget.suspendable || suspension == null) return null;
    return () => unawaited(suspension.mutate((agentId: widget.agentId, action: action)));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final update = _update;
    final delete = _delete;
    final suspension = _suspension;
    if (_deletedId == widget.agentId) {
      return BasePersonalAgentDetails(
        error: ac.t('admin.common.errors.not_found'),
        actions: widget.actions,
        preferences: widget.preferences,
        builder: widget.builder,
      );
    }
    return BasePersonalAgentDetails(
      agent: _agent?.data,
      isLoading: _agent?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('user.agents.details.error')
          : toManagementErrorMessage(ac.t, _agent?.error, 'user.agents.details.error') ??
              toManagementErrorMessage(
                ac.t,
                update?.error ?? delete?.error ?? suspension?.error,
                'user.agents.action.error',
              ),
      isUpdating: update?.isLoading ?? false,
      isDeleting: delete?.isLoading ?? false,
      isChangingSuspension: suspension?.isLoading ?? false,
      onUpdate: widget.editable && update != null
          ? (request) async => await update.mutate((agentId: widget.agentId, data: request)) != null
          : null,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.agentId)) : null,
      onSuspend: _changeSuspension(MeAgentSuspensionAction.suspend),
      onUnsuspend: _changeSuspension(MeAgentSuspensionAction.unsuspend),
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
