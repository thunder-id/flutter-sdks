// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/group.dart';
import '../../models/management/managed_user.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is Map || value is List) return jsonEncode(value);
  return value.toString();
}

/// Presentational view of one user: attributes and group memberships.
///
/// Delete and edit appear only when [onDelete] / [onUpdate] are set, and never for a read-only
/// user. Delete asks for confirmation first (spec "UI", requirement 6).
class BaseUserDetails extends StatefulWidget {
  final ManagedUser? user;
  final List<MembershipGroup> groups;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;

  /// Attributes never shown, e.g. secrets.
  final Set<String> hiddenAttributes;
  final VoidCallback? onDelete;
  final bool isDeleting;

  /// Called with the user's full attribute set after an edit.
  final ValueChanged<Map<String, dynamic>>? onUpdate;
  final bool isUpdating;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the user, their visible attributes and groups, the loading and error state, and the delete and update callbacks.
  final AdminWidgetBuilder<UserDetailsState>? builder;

  const BaseUserDetails({
    super.key,
    this.user,
    this.groups = const [],
    this.isLoading = false,
    this.error,
    this.hiddenAttributes = const {'password'},
    this.onDelete,
    this.isDeleting = false,
    this.onUpdate,
    this.isUpdating = false,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<BaseUserDetails> createState() => _BaseUserDetailsState();
}

class _BaseUserDetailsState extends State<BaseUserDetails> {
  Map<String, String>? _draft;

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final user = widget.user;
    final builder = widget.builder;
    if (builder != null) {
      final isWritable = user != null && !user.isReadOnly;
      return builder(
        context,
        UserDetailsState(
          user: user,
          displayName: user == null
              ? ''
              : resolveManagedIdentityName(id: user.id, display: user.display, attributes: user.attributes),
          attributes: {
            for (final entry in user?.attributes.entries ?? const <MapEntry<String, dynamic>>[])
              if (!widget.hiddenAttributes.contains(entry.key)) entry.key: entry.value,
          },
          groups: widget.groups,
          isLoading: widget.isLoading,
          error: widget.error,
          isDeleting: widget.isDeleting,
          isUpdating: widget.isUpdating,
          onDelete: isWritable ? widget.onDelete : null,
          onUpdate: isWritable ? widget.onUpdate : null,
        ),
      );
    }
    if (user == null) {
      return AdminSection(
        ac: ac,
        block: 'user-details',
        children: [
          if (widget.isLoading)
            AdminLoading(ac: ac)
          else
            AdminAlert(
              ac: ac,
              block: 'user-details',
              message: widget.error ?? ac.t('admin.common.errors.not_found'),
            ),
        ],
      );
    }

    final displayName = resolveManagedIdentityName(id: user.id, display: user.display, attributes: user.attributes);
    final attributes = user.attributes.entries.where((entry) => !widget.hiddenAttributes.contains(entry.key)).toList();
    final editable = {
      for (final entry in attributes)
        if (entry.value is String) entry.key: entry.value as String,
    };
    final canEdit = widget.onUpdate != null && !user.isReadOnly && editable.isNotEmpty;
    final draft = _draft;

    return AdminSection(
      ac: ac,
      block: 'user-details',
      title: displayName,
      description: ac.t('admin.users.details.subtitle', {'type': user.type}),
      actions: [
        ...widget.actions,
        if (widget.onDelete != null && !user.isReadOnly)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('admin.users.details.delete.action'),
            confirmText: ac.t('admin.users.details.delete.confirm', {'name': displayName}),
            identifier: 'thunderid-action-user-details-delete',
            isLoading: widget.isDeleting,
            onConfirm: widget.onDelete!,
          ),
      ],
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'user-details'),
        Row(
          children: [
            AdminAvatar(name: displayName, size: 48),
            const SizedBox(width: 12),
            Flexible(child: Text(user.ouHandle ?? user.ouId, style: TextStyle(color: ac.colors.textSecondary))),
          ],
        ),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.users.details.attributes'),
          action: canEdit && draft == null
              ? AdminButton(
                  ac: ac,
                  label: ac.t('admin.users.details.edit.action'),
                  identifier: 'thunderid-action-user-details-edit',
                  variant: AdminButtonVariant.outline,
                  onPressed: () => setState(() => _draft = Map.of(editable)),
                )
              : null,
          child: draft != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final name in draft.keys)
                      AdminTextField(
                        key: ValueKey('user-details-$name'),
                        ac: ac,
                        label: name,
                        identifier: 'thunderid-field-user-details-$name',
                        initialValue: draft[name]!,
                        onChanged: (value) => draft[name] = value,
                      ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        AdminButton(
                          ac: ac,
                          label: ac.t('admin.common.actions.cancel'),
                          identifier: 'thunderid-action-user-details-edit-cancel',
                          variant: AdminButtonVariant.text,
                          onPressed: widget.isUpdating ? null : () => setState(() => _draft = null),
                        ),
                        AdminButton(
                          ac: ac,
                          label: ac.t('admin.users.details.edit.save'),
                          identifier: 'thunderid-action-user-details-edit-save',
                          isLoading: widget.isUpdating,
                          onPressed: () {
                            widget.onUpdate?.call({...user.attributes, ...draft});
                            setState(() => _draft = null);
                          },
                        ),
                      ],
                    ),
                  ],
                )
              : attributes.isEmpty
                  ? AdminMuted(ac: ac, text: ac.t('admin.users.details.no_attributes'))
                  : AdminDetailList(
                      ac: ac,
                      items: [for (final entry in attributes) (entry.key, Text(_stringify(entry.value)))],
                    ),
        ),
        AdminPanel(
          ac: ac,
          title: ac.t('admin.users.details.groups'),
          child: AdminChipList(
            ac: ac,
            label: ac.t('admin.users.details.groups'),
            emptyText: ac.t('admin.users.details.no_groups'),
            items: [for (final group in widget.groups) AdminChip(id: group.id, label: group.name)],
          ),
        ),
      ],
    );
  }
}

/// User details that loads the user and their groups through the management API.
///
/// Changing data is off by default: set [deletable] to offer delete (with confirmation) and
/// [editable] to offer editing the user's string attributes.
class UserDetails extends StatefulWidget {
  final String userId;
  final bool deletable;
  final bool editable;
  final VoidCallback? onDeleted;
  final Set<String> hiddenAttributes;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseUserDetails.builder].
  final AdminWidgetBuilder<UserDetailsState>? builder;

  const UserDetails({
    super.key,
    required this.userId,
    this.deletable = false,
    this.editable = false,
    this.onDeleted,
    this.hiddenAttributes = const {'password'},
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<UserDetails> createState() => _UserDetailsState();
}

class _UserDetailsState extends AdminConnectedState<UserDetails> {
  ResourceQuery<ManagedUser>? _user;
  ResourceQuery<ManagementPage<MembershipGroup>>? _groups;
  ResourceMutation<String, void>? _delete;
  ResourceMutation<UpdateUserVariables, ManagedUser>? _update;

  @override
  void bind(ManagementResources resources) {
    _user = own(resources.userQuery(widget.userId));
    _groups = own(resources.userGroupsQuery(widget.userId, limit: 100));
    _delete = own(resources.deleteUserMutation(onSuccess: (_, __) => widget.onDeleted?.call()));
    _update = own(resources.updateUserMutation());
  }

  @override
  void didUpdateWidget(UserDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final user = _user?.data;
    final delete = _delete;
    final update = _update;
    return BaseUserDetails(
      user: user,
      groups: _groups?.data?.items ?? const [],
      isLoading: _user?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.users.details.error')
          : toManagementErrorMessage(ac.t, _user?.error, 'admin.users.details.error') ??
              toManagementErrorMessage(ac.t, delete?.error, 'admin.users.details.delete.error') ??
              toManagementErrorMessage(ac.t, update?.error, 'admin.users.details.edit.error'),
      isDeleting: delete?.isLoading ?? false,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.userId)) : null,
      isUpdating: update?.isLoading ?? false,
      onUpdate: widget.editable && update != null && user != null
          ? (attributes) => unawaited(
                update.mutate(
                  (
                    userId: widget.userId,
                    data: UpdateManagedUserRequest(attributes: attributes, ouId: user.ouId, type: user.type),
                  ),
                ),
              )
          : null,
      hiddenAttributes: widget.hiddenAttributes,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
