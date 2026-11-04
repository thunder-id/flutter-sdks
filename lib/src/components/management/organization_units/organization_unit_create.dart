// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../api/management/management_display.dart';
import '../../../models/management/management_page.dart';
import '../../../models/management/organization_unit.dart';
import '../../../models/preferences.dart';
import '../../../state/hierarchy_resources.dart';
import '../../../state/management_resources.dart';
import '../../../state/resource_notifiers.dart';
import '../admin_render_state.dart';
import '../identity_candidate.dart';
import '../internal/admin_connected.dart';
import '../internal/admin_context.dart';
import '../internal/admin_inputs.dart';
import '../internal/admin_parts.dart';
import '../internal/hierarchy_support.dart';

/// What [BaseOrganizationUnitCreate] hands its `builder`.
class OrganizationUnitFormState {
  final String name;
  final ValueChanged<String> onNameChanged;
  final String handle;
  final ValueChanged<String> onHandleChanged;
  final String description;
  final ValueChanged<String> onDescriptionChanged;

  /// The chosen parent's id, or `null` for a root unit.
  final String? parent;

  /// Chooses the parent, or a root unit with `null`. `null` when the parent is fixed.
  final ValueChanged<String?>? onParentChanged;

  /// The units that can be chosen as the parent.
  final List<AdminSelectOption> parents;

  /// Whether the handle follows the rule: lowercase letters, numbers, hyphens and underscores,
  /// starting and ending with a letter or a number.
  final bool isHandleValid;

  /// Whether a name is set and the handle is valid.
  final bool isValid;
  final bool isSubmitting;
  final String? error;

  /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
  final VoidCallback submit;
  final VoidCallback? onCancel;

  const OrganizationUnitFormState({
    required this.name,
    required this.onNameChanged,
    required this.handle,
    required this.onHandleChanged,
    required this.description,
    required this.onDescriptionChanged,
    required this.parent,
    required this.onParentChanged,
    required this.parents,
    required this.isHandleValid,
    required this.isValid,
    required this.isSubmitting,
    required this.error,
    required this.submit,
    required this.onCancel,
  });
}

/// Presentational organization-unit-create form: name, handle, description and parent. With
/// [parentId] the parent is fixed; otherwise it is picked from [parents], and may be left empty for
/// a root unit. Hands the request to [onSubmit]; it makes no request itself. Use
/// [OrganizationUnitCreate] to have it create the unit.
class BaseOrganizationUnitCreate extends StatefulWidget {
  final ValueChanged<CreateOrganizationUnitRequest> onSubmit;

  /// The fixed parent. When set, no parent is offered to pick.
  final String? parentId;

  /// The units to offer as the parent when [parentId] is not set.
  final List<AdminSelectOption> parents;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the values with their setters, the parents
  /// to choose from, the submit action and the submission state.
  final AdminWidgetBuilder<OrganizationUnitFormState>? builder;

  const BaseOrganizationUnitCreate({
    super.key,
    required this.onSubmit,
    this.parentId,
    this.parents = const [],
    this.isSubmitting = false,
    this.error,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<BaseOrganizationUnitCreate> createState() => _BaseOrganizationUnitCreateState();
}

class _BaseOrganizationUnitCreateState extends State<BaseOrganizationUnitCreate> {
  String _name = '';
  String _handle = '';
  String _description = '';
  String? _parent;

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final parent = widget.parentId ?? _parent;
    final handle = _handle.trim();
    final isHandleValid = isValidAdminHandle(handle);
    final isValid = _name.trim().isNotEmpty && isHandleValid;
    final canSubmit = isValid && !widget.isSubmitting;
    void submit() {
      if (!canSubmit) return;
      widget.onSubmit(
        CreateOrganizationUnitRequest(
          handle: handle,
          name: _name.trim(),
          description: optionalText(_description),
          parent: parent,
        ),
      );
    }

    final onParentChanged = widget.parentId == null
        ? (String? value) => setState(() => _parent = optionalText(value ?? ''))
        : null;
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        OrganizationUnitFormState(
          name: _name,
          onNameChanged: (value) => setState(() => _name = value),
          handle: _handle,
          onHandleChanged: (value) => setState(() => _handle = value),
          description: _description,
          onDescriptionChanged: (value) => setState(() => _description = value),
          parent: parent,
          onParentChanged: onParentChanged,
          parents: widget.parents,
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
      block: 'organization-unit-create',
      title: widget.title ?? ac.t('admin.organization_units.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'organization-unit-create'),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.organization_units.fields.name'),
          identifier: 'thunderid-field-organization-unit-create-name',
          required: true,
          onChanged: (value) => setState(() => _name = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.organization_units.fields.handle'),
          identifier: 'thunderid-field-organization-unit-create-handle',
          required: true,
          hint: ac.t('admin.projects.fields.handle_hint'),
          onChanged: (value) => setState(() => _handle = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.organization_units.fields.description'),
          identifier: 'thunderid-field-organization-unit-create-description',
          onChanged: (value) => setState(() => _description = value),
        ),
        if (onParentChanged != null)
          AdminDropdown(
            ac: ac,
            label: ac.t('admin.organization_units.fields.parent'),
            identifier: 'thunderid-field-organization-unit-create-parent',
            value: parent ?? '',
            options: [
              AdminSelectOption(value: '', label: ac.t('admin.organization_units.fields.no_parent')),
              ...widget.parents,
            ],
            onChanged: onParentChanged,
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (widget.onCancel != null)
              AdminButton(
                ac: ac,
                label: ac.t('admin.common.actions.cancel'),
                identifier: 'thunderid-action-organization-unit-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.organization_units.create.submit'),
              identifier: 'thunderid-action-organization-unit-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: canSubmit ? submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Organization-unit-create form that creates the unit through the management API, under
/// [parentId] when given; otherwise the parent is picked from the root units, or left empty for a
/// new root unit. A name or handle already used among the siblings shows its own translated
/// message.
class OrganizationUnitCreate extends StatefulWidget {
  final String? parentId;
  final ValueChanged<OrganizationUnit>? onCreated;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseOrganizationUnitCreate.builder].
  final AdminWidgetBuilder<OrganizationUnitFormState>? builder;

  const OrganizationUnitCreate({
    super.key,
    this.parentId,
    this.onCreated,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<OrganizationUnitCreate> createState() => _OrganizationUnitCreateState();
}

class _OrganizationUnitCreateState extends AdminConnectedState<OrganizationUnitCreate> {
  ResourceQuery<ManagementPage<BasicOrganizationUnit>>? _roots;
  ResourceMutation<CreateOrganizationUnitRequest, OrganizationUnit>? _create;

  @override
  void bind(ManagementResources resources) {
    _roots = own(resources.organizationUnitsQuery(limit: 100, enabled: widget.parentId == null));
    _create = own(resources.createOrganizationUnitMutation(onSuccess: (unit, _) => widget.onCreated?.call(unit)));
  }

  @override
  void didUpdateWidget(OrganizationUnitCreate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentId != widget.parentId) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final create = _create;
    return BaseOrganizationUnitCreate(
      parentId: widget.parentId,
      parents: [
        for (final unit in _roots?.data?.items ?? const <BasicOrganizationUnit>[])
          AdminSelectOption(value: unit.id, label: unit.name),
      ],
      isSubmitting: create?.isLoading ?? false,
      error: toManagementErrorMessage(
        ac.t,
        create?.error,
        'admin.organization_units.create.error',
        codeKeys: HierarchyErrorKeys.organizationUnit,
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
