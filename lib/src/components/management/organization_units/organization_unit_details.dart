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
import '../internal/admin_connected.dart';
import '../internal/admin_context.dart';
import '../internal/admin_inputs.dart';
import '../internal/admin_parts.dart';
import '../internal/hierarchy_support.dart';

/// The name, handle and description [BaseOrganizationUnitDetails] saves.
class OrganizationUnitEdit {
  final String name;
  final String handle;
  final String? description;

  const OrganizationUnitEdit({required this.name, required this.handle, this.description});

  /// [unit] with these changes, as a full update: the parent and every other setting are kept.
  UpdateOrganizationUnitRequest applyTo(OrganizationUnit unit) => UpdateOrganizationUnitRequest(
    handle: handle,
    name: name,
    description: description,
    parent: unit.parent,
    themeId: unit.themeId,
    layoutId: unit.layoutId,
    authFlowId: unit.authFlowId,
    registrationFlowId: unit.registrationFlowId,
    isRegistrationFlowEnabled: unit.isRegistrationFlowEnabled,
    recoveryFlowId: unit.recoveryFlowId,
    isRecoveryFlowEnabled: unit.isRecoveryFlowEnabled,
    signOutFlowId: unit.signOutFlowId,
    logoUrl: unit.logoUrl,
    tosUri: unit.tosUri,
    policyUri: unit.policyUri,
    cookiePolicyUri: unit.cookiePolicyUri,
  );
}

/// What [BaseOrganizationUnitDetails] hands its `builder`.
class OrganizationUnitDetailsState {
  final OrganizationUnit? unit;

  /// The unit's child units, users, groups and roles, read only.
  final List<BasicOrganizationUnit> children;
  final List<OrganizationUnitUser> users;
  final List<OrganizationUnitGroup> groups;
  final List<OrganizationUnitRole> roles;
  final bool isLoading;
  final String? error;
  final bool isUpdating;
  final bool isDeleting;

  /// Opens a child unit. `null` when children are not selectable.
  final ValueChanged<BasicOrganizationUnit>? onSelectChild;

  /// Saves the name, handle and description. `null` when editing is not allowed.
  final ValueChanged<OrganizationUnitEdit>? onUpdate;

  /// Deletes the unit. `null` when deletion is not allowed. A custom UI must ask for confirmation
  /// first.
  final VoidCallback? onDelete;

  const OrganizationUnitDetailsState({
    required this.unit,
    required this.children,
    required this.users,
    required this.groups,
    required this.roles,
    required this.isLoading,
    required this.error,
    required this.isUpdating,
    required this.isDeleting,
    required this.onSelectChild,
    required this.onUpdate,
    required this.onDelete,
  });
}

/// Presentational view of one organization unit: its overview (name, handle, description, parent),
/// its child units, and the users, groups and roles in it, read only.
///
/// Editing the name, handle and description appears only when [onUpdate] is set, and delete only
/// when [onDelete] is set; a delete asks for confirmation first.
class BaseOrganizationUnitDetails extends StatefulWidget {
  final OrganizationUnit? unit;
  final List<BasicOrganizationUnit> childUnits;
  final List<OrganizationUnitUser> users;
  final List<OrganizationUnitGroup> groups;
  final List<OrganizationUnitRole> roles;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final bool isUpdating;
  final bool isDeleting;
  final ValueChanged<BasicOrganizationUnit>? onSelectChild;
  final ValueChanged<OrganizationUnitEdit>? onUpdate;
  final VoidCallback? onDelete;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the unit, its children, users, groups and
  /// roles, the loading and error state, and the update and delete actions.
  final AdminWidgetBuilder<OrganizationUnitDetailsState>? builder;

  const BaseOrganizationUnitDetails({
    super.key,
    this.unit,
    this.childUnits = const [],
    this.users = const [],
    this.groups = const [],
    this.roles = const [],
    this.isLoading = false,
    this.error,
    this.isUpdating = false,
    this.isDeleting = false,
    this.onSelectChild,
    this.onUpdate,
    this.onDelete,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<BaseOrganizationUnitDetails> createState() => _BaseOrganizationUnitDetailsState();
}

class _BaseOrganizationUnitDetailsState extends State<BaseOrganizationUnitDetails> {
  static const _block = 'organization-unit-details';
  static const _prefix = 'admin.organization_units';
  bool _editing = false;
  String _name = '';
  String _handle = '';
  String _description = '';

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final unit = widget.unit;
    final onUpdate = unit != null ? widget.onUpdate : null;
    final onDelete = unit != null ? widget.onDelete : null;
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        OrganizationUnitDetailsState(
          unit: unit,
          children: widget.childUnits,
          users: widget.users,
          groups: widget.groups,
          roles: widget.roles,
          isLoading: widget.isLoading,
          error: widget.error,
          isUpdating: widget.isUpdating,
          isDeleting: widget.isDeleting,
          onSelectChild: widget.onSelectChild,
          onUpdate: onUpdate,
          onDelete: onDelete,
        ),
      );
    }
    if (unit == null) {
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

    return AdminSection(
      ac: ac,
      block: _block,
      title: unit.name,
      description: unit.description,
      actions: [
        ...widget.actions,
        if (onUpdate != null && !_editing)
          AdminButton(
            ac: ac,
            label: ac.t('$_prefix.details.edit.action'),
            identifier: 'thunderid-action-organization-unit-details-edit',
            variant: AdminButtonVariant.outline,
            onPressed: () => setState(() {
              _name = unit.name;
              _handle = unit.handle;
              _description = unit.description ?? '';
              _editing = true;
            }),
          ),
        if (onDelete != null)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('$_prefix.details.delete.action'),
            confirmText: ac.t('$_prefix.details.delete.confirm', {'name': unit.name}),
            identifier: 'thunderid-action-organization-unit-details-delete',
            isLoading: widget.isDeleting,
            onConfirm: onDelete,
          ),
      ],
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: _block),
        if (_editing && onUpdate != null)
          _editForm(ac, onUpdate)
        else
          AdminPanel(
            ac: ac,
            title: ac.t('$_prefix.details.overview'),
            child: AdminDetailList(
              ac: ac,
              items: [
                (ac.t('$_prefix.fields.name'), Text(unit.name)),
                (ac.t('$_prefix.fields.handle'), Text(unit.handle)),
                (ac.t('$_prefix.fields.description'), Text(unit.description ?? '')),
                (ac.t('$_prefix.fields.parent'), Text(unit.parent ?? ac.t('$_prefix.fields.no_parent'))),
              ],
            ),
          ),
        AdminPanel(
          ac: ac,
          title: ac.t('$_prefix.details.children'),
          child: AdminTable<BasicOrganizationUnit>(
            ac: ac,
            block: '$_block-children',
            rows: widget.childUnits,
            rowId: (child) => child.id,
            emptyText: ac.t('$_prefix.details.no_children'),
            onRowTap: widget.onSelectChild,
            columns: [
              AdminColumn(header: ac.t('$_prefix.fields.name'), build: (child) => Text(child.name)),
              AdminColumn(header: ac.t('$_prefix.fields.handle'), build: (child) => Text(child.handle)),
            ],
          ),
        ),
        _members(ac, 'users', [
          for (final user in widget.users) AdminChip(id: user.id, label: user.display ?? user.id),
        ]),
        _members(ac, 'groups', [for (final group in widget.groups) AdminChip(id: group.id, label: group.name)]),
        _members(ac, 'roles', [for (final role in widget.roles) AdminChip(id: role.id, label: role.name)]),
      ],
    );
  }

  Widget _members(AdminContext ac, String kind, List<AdminChip> items) => AdminPanel(
    key: Key('thunderid-admin-$_block-$kind'),
    ac: ac,
    title: ac.t('$_prefix.details.$kind'),
    child: AdminChipList(
      ac: ac,
      label: ac.t('$_prefix.details.$kind'),
      emptyText: ac.t('$_prefix.details.no_$kind'),
      items: items,
    ),
  );

  Widget _editForm(AdminContext ac, ValueChanged<OrganizationUnitEdit> onUpdate) {
    final handle = _handle.trim();
    final canSave = _name.trim().isNotEmpty && isValidAdminHandle(handle) && !widget.isUpdating;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTextField(
          ac: ac,
          label: ac.t('$_prefix.fields.name'),
          identifier: 'thunderid-field-organization-unit-details-name',
          required: true,
          initialValue: _name,
          onChanged: (value) => setState(() => _name = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('$_prefix.fields.handle'),
          identifier: 'thunderid-field-organization-unit-details-handle',
          required: true,
          initialValue: _handle,
          onChanged: (value) => setState(() => _handle = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('$_prefix.fields.description'),
          identifier: 'thunderid-field-organization-unit-details-description',
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
              identifier: 'thunderid-action-organization-unit-details-cancel',
              variant: AdminButtonVariant.text,
              onPressed: () => setState(() => _editing = false),
            ),
            AdminButton(
              ac: ac,
              label: ac.t('$_prefix.details.edit.save'),
              identifier: 'thunderid-action-organization-unit-details-save',
              isLoading: widget.isUpdating,
              onPressed: canSave
                  ? () {
                      onUpdate(
                        OrganizationUnitEdit(
                          name: _name.trim(),
                          handle: handle,
                          description: optionalText(_description),
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

/// Organization unit details that loads the unit through the management API, with its child
/// units and the users, groups and roles in it (read only).
///
/// Changing data is off by default: set [editable] to offer editing the name, handle and
/// description, and [deletable] to offer delete (with confirmation). The server refuses to delete
/// a unit that still has child units or other resources; that refusal shows its own translated
/// message.
class OrganizationUnitDetails extends StatefulWidget {
  final String organizationUnitId;

  /// The page size of the child units, users, groups and roles.
  final int limit;
  final bool editable;
  final bool deletable;
  final ValueChanged<BasicOrganizationUnit>? onSelectChild;
  final VoidCallback? onDeleted;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseOrganizationUnitDetails.builder].
  final AdminWidgetBuilder<OrganizationUnitDetailsState>? builder;

  const OrganizationUnitDetails({
    super.key,
    required this.organizationUnitId,
    this.limit = 20,
    this.editable = false,
    this.deletable = false,
    this.onSelectChild,
    this.onDeleted,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<OrganizationUnitDetails> createState() => _OrganizationUnitDetailsState();
}

class _OrganizationUnitDetailsState extends AdminConnectedState<OrganizationUnitDetails> {
  ResourceQuery<OrganizationUnit>? _unit;
  ResourceQuery<ManagementPage<BasicOrganizationUnit>>? _children;
  ResourceQuery<ManagementPage<OrganizationUnitUser>>? _users;
  ResourceQuery<ManagementPage<OrganizationUnitGroup>>? _groups;
  ResourceQuery<ManagementPage<OrganizationUnitRole>>? _roles;
  ResourceMutation<UpdateOrganizationUnitVariables, OrganizationUnit>? _update;
  ResourceMutation<String, void>? _delete;

  @override
  void bind(ManagementResources resources) {
    final id = widget.organizationUnitId;
    final limit = widget.limit;
    _unit = own(resources.organizationUnitQuery(id));
    _children = own(resources.organizationUnitsQuery(parentId: id, limit: limit));
    _users = own(resources.organizationUnitUsersQuery(id, limit: limit));
    _groups = own(resources.organizationUnitGroupsQuery(id, limit: limit));
    _roles = own(resources.organizationUnitRolesQuery(id, limit: limit));
    _update = own(resources.updateOrganizationUnitMutation());
    _delete = own(resources.deleteOrganizationUnitMutation(onSuccess: (_, __) => widget.onDeleted?.call()));
  }

  @override
  void didUpdateWidget(OrganizationUnitDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationUnitId != widget.organizationUnitId || oldWidget.limit != widget.limit) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    const prefix = 'admin.organization_units';
    final unit = _unit?.data;
    final update = _update;
    final delete = _delete;
    return BaseOrganizationUnitDetails(
      unit: unit,
      childUnits: _children?.data?.items ?? const [],
      users: _users?.data?.items ?? const [],
      groups: _groups?.data?.items ?? const [],
      roles: _roles?.data?.items ?? const [],
      isLoading: _unit?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('$prefix.details.error')
          : toManagementErrorMessage(ac.t, _unit?.error, '$prefix.details.error') ??
                toManagementErrorMessage(
                  ac.t,
                  update?.error,
                  '$prefix.details.edit.error',
                  codeKeys: HierarchyErrorKeys.organizationUnit,
                ) ??
                toManagementErrorMessage(
                  ac.t,
                  delete?.error,
                  '$prefix.details.delete.error',
                  codeKeys: HierarchyErrorKeys.organizationUnitDelete,
                ),
      isUpdating: update?.isLoading ?? false,
      isDeleting: delete?.isLoading ?? false,
      onSelectChild: widget.onSelectChild,
      onUpdate: widget.editable && update != null && unit != null
          ? (edit) => unawaited(update.mutate((ouId: widget.organizationUnitId, data: edit.applyTo(unit))))
          : null,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.organizationUnitId)) : null,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
