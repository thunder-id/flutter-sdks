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

/// What [BaseProjectDetails] hands its `builder`.
class ProjectDetailsState {
  final Project? project;
  final bool isLoading;
  final String? error;
  final bool isUpdating;
  final bool isDeleting;

  /// Saves the display name and description. `null` when editing is not allowed. The handle cannot
  /// change: send the project's own handle, or none.
  final ValueChanged<UpdateProjectRequest>? onUpdate;

  /// Deletes the project. `null` when deletion is not allowed. A custom UI must ask for
  /// confirmation first.
  final VoidCallback? onDelete;

  const ProjectDetailsState({
    required this.project,
    required this.isLoading,
    required this.error,
    required this.isUpdating,
    required this.isDeleting,
    required this.onUpdate,
    required this.onDelete,
  });
}

/// Presentational view of one project: its handle, display name, description and creation time.
///
/// Editing the display name and description appears only when [onUpdate] is set, and delete only
/// when [onDelete] is set; a delete asks for confirmation first.
class BaseProjectDetails extends StatefulWidget {
  final Project? project;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final bool isUpdating;
  final bool isDeleting;
  final ValueChanged<UpdateProjectRequest>? onUpdate;
  final VoidCallback? onDelete;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the project, the loading and error state,
  /// and the update and delete actions.
  final AdminWidgetBuilder<ProjectDetailsState>? builder;

  const BaseProjectDetails({
    super.key,
    this.project,
    this.isLoading = false,
    this.error,
    this.isUpdating = false,
    this.isDeleting = false,
    this.onUpdate,
    this.onDelete,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<BaseProjectDetails> createState() => _BaseProjectDetailsState();
}

class _BaseProjectDetailsState extends State<BaseProjectDetails> {
  bool _editing = false;
  String _displayName = '';
  String _description = '';

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final project = widget.project;
    final onUpdate = project != null ? widget.onUpdate : null;
    final onDelete = project != null ? widget.onDelete : null;
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        ProjectDetailsState(
          project: project,
          isLoading: widget.isLoading,
          error: widget.error,
          isUpdating: widget.isUpdating,
          isDeleting: widget.isDeleting,
          onUpdate: onUpdate,
          onDelete: onDelete,
        ),
      );
    }
    if (project == null) {
      return AdminSection(
        ac: ac,
        block: 'project-details',
        children: [
          if (widget.isLoading)
            AdminLoading(ac: ac)
          else
            AdminAlert(
              ac: ac,
              block: 'project-details',
              message: widget.error ?? ac.t('admin.common.errors.not_found'),
            ),
        ],
      );
    }

    return AdminSection(
      ac: ac,
      block: 'project-details',
      title: project.displayName,
      description: project.description,
      actions: [
        ...widget.actions,
        if (onUpdate != null && !_editing)
          AdminButton(
            ac: ac,
            label: ac.t('admin.projects.details.edit.action'),
            identifier: 'thunderid-action-project-details-edit',
            variant: AdminButtonVariant.outline,
            onPressed: () => setState(() {
              _displayName = project.displayName;
              _description = project.description ?? '';
              _editing = true;
            }),
          ),
        if (onDelete != null)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('admin.projects.details.delete.action'),
            confirmText: ac.t('admin.projects.details.delete.confirm', {'name': project.displayName}),
            identifier: 'thunderid-action-project-details-delete',
            isLoading: widget.isDeleting,
            onConfirm: onDelete,
          ),
      ],
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'project-details'),
        if (_editing && onUpdate != null)
          _editForm(ac, project, onUpdate)
        else
          AdminPanel(
            ac: ac,
            title: ac.t('admin.projects.details.overview'),
            child: AdminDetailList(
              ac: ac,
              items: [
                (ac.t('admin.projects.fields.handle'), Text(project.handle)),
                (ac.t('admin.projects.fields.display_name'), Text(project.displayName)),
                (ac.t('admin.projects.fields.description'), Text(project.description ?? '')),
                (ac.t('admin.projects.details.created'), Text(formatAdminTimestamp(project.createdAt))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _editForm(AdminContext ac, Project project, ValueChanged<UpdateProjectRequest> onUpdate) {
    final canSave = _displayName.trim().isNotEmpty && !widget.isUpdating;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTextField(
          ac: ac,
          label: ac.t('admin.projects.fields.display_name'),
          identifier: 'thunderid-field-project-details-displayName',
          required: true,
          initialValue: _displayName,
          onChanged: (value) => setState(() => _displayName = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.projects.fields.description'),
          identifier: 'thunderid-field-project-details-description',
          initialValue: _description,
          onChanged: (value) => setState(() => _description = value),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            AdminButton(
              ac: ac,
              label: ac.t('admin.common.actions.cancel'),
              identifier: 'thunderid-action-project-details-cancel',
              variant: AdminButtonVariant.text,
              onPressed: () => setState(() => _editing = false),
            ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.projects.details.edit.save'),
              identifier: 'thunderid-action-project-details-save',
              isLoading: widget.isUpdating,
              onPressed: canSave
                  ? () {
                      onUpdate(
                        UpdateProjectRequest(
                          displayName: _displayName.trim(),
                          description: optionalText(_description),
                          handle: project.handle,
                        ),
                      );
                      setState(() => _editing = false);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Project details that loads the project through the management API.
///
/// Changing data is off by default: set [editable] to offer editing the display name and
/// description, and [deletable] to offer delete (with confirmation). Deleting the current project
/// clears it. Only the control plane serves projects.
class ProjectDetails extends StatefulWidget {
  final String projectId;
  final bool editable;
  final bool deletable;
  final VoidCallback? onDeleted;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseProjectDetails.builder].
  final AdminWidgetBuilder<ProjectDetailsState>? builder;

  const ProjectDetails({
    super.key,
    required this.projectId,
    this.editable = false,
    this.deletable = false,
    this.onDeleted,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<ProjectDetails> createState() => _ProjectDetailsState();
}

class _ProjectDetailsState extends AdminConnectedState<ProjectDetails> {
  ResourceQuery<Project>? _project;
  ResourceMutation<UpdateProjectVariables, Project>? _update;
  ResourceMutation<String, void>? _delete;

  @override
  void bind(ManagementResources resources) {
    _project = own(resources.projectQuery(widget.projectId));
    _update = own(resources.updateProjectMutation());
    _delete = own(
      resources.deleteProjectMutation(
        onSuccess: (_, projectId) {
          if (thunder?.currentProject?.id == projectId) thunder?.setCurrentProject(null);
          widget.onDeleted?.call();
        },
      ),
    );
  }

  @override
  void didUpdateWidget(ProjectDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final update = _update;
    final delete = _delete;
    return BaseProjectDetails(
      project: _project?.data,
      isLoading: _project?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.projects.details.error')
          : toManagementErrorMessage(ac.t, _project?.error, 'admin.projects.details.error') ??
                toManagementErrorMessage(
                  ac.t,
                  update?.error,
                  'admin.projects.details.edit.error',
                  codeKeys: HierarchyErrorKeys.project,
                ) ??
                toManagementErrorMessage(ac.t, delete?.error, 'admin.projects.details.delete.error'),
      isUpdating: update?.isLoading ?? false,
      isDeleting: delete?.isLoading ?? false,
      onUpdate: widget.editable && update != null
          ? (request) => unawaited(update.mutate((projectId: widget.projectId, data: request)))
          : null,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.projectId)) : null,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
