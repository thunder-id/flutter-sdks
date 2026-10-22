// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/agent.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'identity_candidate.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// What [BaseAgentCreate] submits.
class AgentCreateSubmission {
  final String name;
  final String type;
  final String? description;

  const AgentCreateSubmission({required this.name, required this.type, this.description});
}

/// Presentational agent-registration form. Hands the name, type, and description to
/// [onSubmit]; it makes no request itself. Use [AgentCreate] to have it register the agent.
class BaseAgentCreate extends StatefulWidget {
  final List<AdminSelectOption> agentTypes;
  final ValueChanged<AgentCreateSubmission> onSubmit;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the agent types, the name, type and description with their setters, the submit action and the submission state.
  final AdminWidgetBuilder<AgentCreateFormState>? builder;

  const BaseAgentCreate({
    super.key,
    required this.agentTypes,
    required this.onSubmit,
    this.isSubmitting = false,
    this.error,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<BaseAgentCreate> createState() => _BaseAgentCreateState();
}

class _BaseAgentCreateState extends State<BaseAgentCreate> {
  String _name = '';
  String _description = '';
  String? _type;

  String get _resolvedType => _type ?? (widget.agentTypes.isEmpty ? '' : widget.agentTypes.first.value);

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final isValid = _name.trim().isNotEmpty && _resolvedType.isNotEmpty;
    final canSubmit = isValid && !widget.isSubmitting;
    void submit() {
      if (!canSubmit) return;
      widget.onSubmit(
        AgentCreateSubmission(
          name: _name.trim(),
          type: _resolvedType,
          description: _description.trim().isEmpty ? null : _description.trim(),
        ),
      );
    }

    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        AgentCreateFormState(
          agentTypes: widget.agentTypes,
          name: _name,
          onNameChanged: (value) => setState(() => _name = value),
          type: _resolvedType,
          onTypeChanged: (value) => setState(() => _type = value),
          description: _description,
          onDescriptionChanged: (value) => setState(() => _description = value),
          isValid: isValid,
          isSubmitting: widget.isSubmitting,
          error: widget.error,
          submit: submit,
          onCancel: widget.onCancel,
        ),
      );
    }
    return AdminSection(
      ac: ac,
      block: 'agent-create',
      title: widget.title ?? ac.t('admin.agents.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'agent-create'),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.agents.create.fields.name'),
          identifier: 'thunderid-field-agent-create-name',
          required: true,
          onChanged: (value) => setState(() => _name = value),
        ),
        AdminDropdown(
          ac: ac,
          label: ac.t('admin.agents.create.fields.type'),
          identifier: 'thunderid-field-agent-create-type',
          value: _resolvedType,
          options: widget.agentTypes,
          onChanged: (value) => setState(() => _type = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.agents.create.fields.description'),
          identifier: 'thunderid-field-agent-create-description',
          onChanged: (value) => setState(() => _description = value),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (widget.onCancel != null)
              AdminButton(
                ac: ac,
                label: ac.t('admin.common.actions.cancel'),
                identifier: 'thunderid-action-agent-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.agents.create.submit'),
              identifier: 'thunderid-action-agent-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: canSubmit ? submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Agent-registration form that registers the agent through the management API, in [ouId] or
/// the signed-in user's own organization unit when omitted.
class AgentCreate extends StatefulWidget {
  final String? ouId;

  /// The agent's owner, passed through as `owner`.
  final String? owner;
  final ValueChanged<Agent>? onCreated;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseAgentCreate.builder].
  final AdminWidgetBuilder<AgentCreateFormState>? builder;

  const AgentCreate({
    super.key,
    this.ouId,
    this.owner,
    this.onCreated,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<AgentCreate> createState() => _AgentCreateState();
}

class _AgentCreateState extends AdminConnectedState<AgentCreate> {
  ResourceQuery<ManagementPage<AgentType>>? _types;
  ResourceMutation<CreateAgentRequest, Agent>? _create;

  @override
  void bind(ManagementResources resources) {
    _types = own(resources.agentTypesQuery(limit: 100));
    _create = own(resources.createAgentMutation(onSuccess: (agent, _) => widget.onCreated?.call(agent)));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final ouId = widget.ouId ?? thunder?.defaultOuId;
    final create = _create;
    return BaseAgentCreate(
      agentTypes: [
        for (final type in _types?.data?.items ?? const <AgentType>[])
          AdminSelectOption(value: type.handle, label: type.displayName),
      ],
      isSubmitting: create?.isLoading ?? false,
      error: ouId == null
          ? ac.t('admin.common.errors.no_ou')
          : toManagementErrorMessage(ac.t, create?.error, 'admin.agents.create.error'),
      onSubmit: (submission) {
        if (ouId == null || create == null) return;
        unawaited(
          create.mutate(
            CreateAgentRequest(
              name: submission.name,
              type: submission.type,
              description: submission.description,
              ouId: ouId,
              owner: widget.owner,
            ),
          ),
        );
      },
      onCancel: widget.onCancel,
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
