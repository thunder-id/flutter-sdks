// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/role.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// What [BaseRoleCreate] submits.
class RoleCreateSubmission {
  final String name;
  final String? description;

  const RoleCreateSubmission({required this.name, this.description});
}

/// Presentational role-create form. Hands the name and description to [onSubmit]; it makes no
/// request itself. Use [RoleCreate] to have it create the role.
class BaseRoleCreate extends StatefulWidget {
  final ValueChanged<RoleCreateSubmission> onSubmit;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the name and description with their setters, the submit action and the submission state.
  final AdminWidgetBuilder<NamedResourceFormState>? builder;

  const BaseRoleCreate({
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
  State<BaseRoleCreate> createState() => _BaseRoleCreateState();
}

class _BaseRoleCreateState extends State<BaseRoleCreate> {
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
        RoleCreateSubmission(
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
      block: 'role-create',
      title: widget.title ?? ac.t('admin.roles.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'role-create'),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.roles.create.fields.name'),
          identifier: 'thunderid-field-role-create-name',
          required: true,
          onChanged: (value) => setState(() => _name = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.roles.create.fields.description'),
          identifier: 'thunderid-field-role-create-description',
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
                identifier: 'thunderid-action-role-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.roles.create.submit'),
              identifier: 'thunderid-action-role-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: canSubmit ? submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Role-create form that creates the role through the management API, in [ouId] or the
/// signed-in user's own organization unit when omitted.
class RoleCreate extends StatefulWidget {
  final String? ouId;
  final ValueChanged<Role>? onCreated;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseRoleCreate.builder].
  final AdminWidgetBuilder<NamedResourceFormState>? builder;

  const RoleCreate({
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
  State<RoleCreate> createState() => _RoleCreateState();
}

class _RoleCreateState extends AdminConnectedState<RoleCreate> {
  ResourceMutation<CreateRoleRequest, Role>? _create;

  @override
  void bind(ManagementResources resources) {
    _create = own(resources.createRoleMutation(onSuccess: (role, _) => widget.onCreated?.call(role)));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final ouId = widget.ouId ?? thunder?.defaultOuId;
    final create = _create;
    return BaseRoleCreate(
      isSubmitting: create?.isLoading ?? false,
      error: ouId == null
          ? ac.t('admin.common.errors.no_ou')
          : toManagementErrorMessage(ac.t, create?.error, 'admin.roles.create.error'),
      onSubmit: (submission) {
        if (ouId == null || create == null) return;
        unawaited(
          create.mutate(CreateRoleRequest(name: submission.name, description: submission.description, ouId: ouId)),
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
