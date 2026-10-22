// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/group.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// What [BaseGroupCreate] submits.
class GroupCreateSubmission {
  final String name;
  final String? description;

  const GroupCreateSubmission({required this.name, this.description});
}

/// Presentational group-create form. Hands the name and description to [onSubmit]; it makes no
/// request itself. Use [GroupCreate] to have it create the group.
class BaseGroupCreate extends StatefulWidget {
  final ValueChanged<GroupCreateSubmission> onSubmit;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the name and description with their setters, the submit action and the submission state.
  final AdminWidgetBuilder<NamedResourceFormState>? builder;

  const BaseGroupCreate({
    super.key,
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
  State<BaseGroupCreate> createState() => _BaseGroupCreateState();
}

class _BaseGroupCreateState extends State<BaseGroupCreate> {
  String _name = '';
  String _description = '';

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final isValid = _name.trim().isNotEmpty;
    final canSubmit = isValid && !widget.isSubmitting;
    void submit() {
      if (!canSubmit) return;
      widget.onSubmit(
        GroupCreateSubmission(
          name: _name.trim(),
          description: _description.trim().isEmpty ? null : _description.trim(),
        ),
      );
    }

    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        NamedResourceFormState(
          name: _name,
          onNameChanged: (value) => setState(() => _name = value),
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
      block: 'group-create',
      title: widget.title ?? ac.t('admin.groups.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'group-create'),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.groups.create.fields.name'),
          identifier: 'thunderid-field-group-create-name',
          required: true,
          onChanged: (value) => setState(() => _name = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.groups.create.fields.description'),
          identifier: 'thunderid-field-group-create-description',
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
                identifier: 'thunderid-action-group-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.groups.create.submit'),
              identifier: 'thunderid-action-group-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: canSubmit ? submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Group-create form that creates the group through the management API, in [ouId] or the
/// signed-in user's own organization unit when omitted.
class GroupCreate extends StatefulWidget {
  final String? ouId;
  final ValueChanged<Group>? onCreated;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseGroupCreate.builder].
  final AdminWidgetBuilder<NamedResourceFormState>? builder;

  const GroupCreate({
    super.key,
    this.ouId,
    this.onCreated,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<GroupCreate> createState() => _GroupCreateState();
}

class _GroupCreateState extends AdminConnectedState<GroupCreate> {
  ResourceMutation<CreateGroupRequest, Group>? _create;

  @override
  void bind(ManagementResources resources) {
    _create = own(resources.createGroupMutation(onSuccess: (group, _) => widget.onCreated?.call(group)));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final ouId = widget.ouId ?? thunder?.defaultOuId;
    final create = _create;
    return BaseGroupCreate(
      isSubmitting: create?.isLoading ?? false,
      error: ouId == null
          ? ac.t('admin.common.errors.no_ou')
          : toManagementErrorMessage(ac.t, create?.error, 'admin.groups.create.error'),
      onSubmit: (submission) {
        if (ouId == null || create == null) return;
        unawaited(
          create.mutate(CreateGroupRequest(name: submission.name, description: submission.description, ouId: ouId)),
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
