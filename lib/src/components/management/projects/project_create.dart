// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../api/management/management_display.dart';
import '../../../models/management/project.dart';
import '../../../models/preferences.dart';
import '../../../state/hierarchy_resources.dart';
import '../../../state/management_resources.dart';
import '../../../state/resource_notifiers.dart';
import '../admin_render_state.dart';
import '../internal/admin_connected.dart';
import '../internal/admin_context.dart';
import '../internal/admin_inputs.dart';
import '../internal/admin_parts.dart';
import '../internal/hierarchy_support.dart';

/// What [BaseProjectCreate] hands its `builder`.
class ProjectFormState {
  final String handle;
  final ValueChanged<String> onHandleChanged;
  final String displayName;
  final ValueChanged<String> onDisplayNameChanged;
  final String description;
  final ValueChanged<String> onDescriptionChanged;

  /// Whether the handle follows the rule: lowercase letters, numbers, hyphens and underscores,
  /// starting and ending with a letter or a number.
  final bool isHandleValid;

  /// Whether the handle is valid and a display name is set.
  final bool isValid;
  final bool isSubmitting;
  final String? error;

  /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
  final VoidCallback submit;
  final VoidCallback? onCancel;

  const ProjectFormState({
    required this.handle,
    required this.onHandleChanged,
    required this.displayName,
    required this.onDisplayNameChanged,
    required this.description,
    required this.onDescriptionChanged,
    required this.isHandleValid,
    required this.isValid,
    required this.isSubmitting,
    required this.error,
    required this.submit,
    required this.onCancel,
  });
}

/// Presentational project-create form: handle, display name and description. Hands the request to
/// [onSubmit]; it makes no request itself. Use [ProjectCreate] to have it create the project.
class BaseProjectCreate extends StatefulWidget {
  final ValueChanged<CreateProjectRequest> onSubmit;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the values with their setters, the submit
  /// action and the submission state.
  final AdminWidgetBuilder<ProjectFormState>? builder;

  const BaseProjectCreate({
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
  State<BaseProjectCreate> createState() => _BaseProjectCreateState();
}

class _BaseProjectCreateState extends State<BaseProjectCreate> {
  String _handle = '';
  String _displayName = '';
  String _description = '';

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final handle = _handle.trim();
    final isHandleValid = isValidAdminHandle(handle);
    final isValid = isHandleValid && _displayName.trim().isNotEmpty;
    final canSubmit = isValid && !widget.isSubmitting;
    void submit() {
      if (!canSubmit) return;
      widget.onSubmit(
        CreateProjectRequest(handle: handle, displayName: _displayName.trim(), description: optionalText(_description)),
      );
    }

    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        ProjectFormState(
          handle: _handle,
          onHandleChanged: (value) => setState(() => _handle = value),
          displayName: _displayName,
          onDisplayNameChanged: (value) => setState(() => _displayName = value),
          description: _description,
          onDescriptionChanged: (value) => setState(() => _description = value),
          isHandleValid: isHandleValid,
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
      block: 'project-create',
      title: widget.title ?? ac.t('admin.projects.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'project-create'),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.projects.fields.handle'),
          identifier: 'thunderid-field-project-create-handle',
          required: true,
          hint: ac.t('admin.projects.fields.handle_hint'),
          onChanged: (value) => setState(() => _handle = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.projects.fields.display_name'),
          identifier: 'thunderid-field-project-create-displayName',
          required: true,
          onChanged: (value) => setState(() => _displayName = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.projects.fields.description'),
          identifier: 'thunderid-field-project-create-description',
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
                identifier: 'thunderid-action-project-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.projects.create.submit'),
              identifier: 'thunderid-action-project-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: canSubmit ? submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Project-create form that creates the project through the management API. A handle or id that
/// is already used shows its own translated message. Only the control plane serves projects.
class ProjectCreate extends StatefulWidget {
  final ValueChanged<Project>? onCreated;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseProjectCreate.builder].
  final AdminWidgetBuilder<ProjectFormState>? builder;

  const ProjectCreate({
    super.key,
    this.onCreated,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<ProjectCreate> createState() => _ProjectCreateState();
}

class _ProjectCreateState extends AdminConnectedState<ProjectCreate> {
  ResourceMutation<CreateProjectRequest, Project>? _create;

  @override
  void bind(ManagementResources resources) {
    _create = own(resources.createProjectMutation(onSuccess: (project, _) => widget.onCreated?.call(project)));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final create = _create;
    return BaseProjectCreate(
      isSubmitting: create?.isLoading ?? false,
      error: toManagementErrorMessage(
        ac.t,
        create?.error,
        'admin.projects.create.error',
        codeKeys: HierarchyErrorKeys.project,
      ),
      onSubmit: (request) {
        if (create == null) return;
        unawaited(create.mutate(request));
      },
      onCancel: widget.onCancel,
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
