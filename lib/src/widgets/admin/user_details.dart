// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../models/management/administration.dart';
import '../../models/management/entity_type.dart';
import '../../models/management/group.dart';
import '../../models/management/managed_user.dart';
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
import 'internal/user_attribute_verification_parts.dart';

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is Map || value is List) return jsonEncode(value);
  return value.toString();
}

/// Presentational view of one user: access status, attributes and group memberships.
///
/// Delete and edit appear only when [onDelete] / [onUpdate] are set, and never for a read-only
/// user. Delete asks for confirmation first (spec "UI", requirement 6). The account lifecycle
/// actions in [lifecycleActions] appear only when [onLifecycleAction] is set; they change only
/// runtime state, so they apply to read-only users too. When the server reports the user's
/// verified attributes, each contact attribute with a record, or typed email or mobile in
/// [userSchema], shows Verified or Not verified. With [onSendVerification], an unverified
/// email-typed attribute of a user that is not read-only offers a verification link.
class BaseUserDetails extends StatefulWidget {
  final ManagedUser? user;
  final List<MembershipGroup> groups;

  /// The schema of the user's type. Without it, only attributes the server already reports a
  /// verification record for show a status, and no link can be sent.
  final EntityTypeSchema? userSchema;
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

  /// The account lifecycle actions to offer (suspend, unsuspend, unlock), shown only with
  /// [onLifecycleAction].
  final List<AccountLifecycleAction> lifecycleActions;

  /// Runs an account lifecycle action. Suspending and unsuspending ask for confirmation first,
  /// and a suspension takes an optional operator note.
  final AccountLifecycleCallback? onLifecycleAction;
  final bool isRunningLifecycleAction;

  /// Sends the user a link to verify the given attribute.
  final ValueChanged<String>? onSendVerification;
  final bool isSendingVerification;

  /// What the last sent verification link reported. Its masked destination is shown in a success
  /// message.
  final UserAttributeVerificationResult? sentVerification;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the user, their visible attributes and groups, their verification status, the loading and error state, and the allowed actions.
  final AdminWidgetBuilder<UserDetailsState>? builder;

  const BaseUserDetails({
    super.key,
    this.user,
    this.groups = const [],
    this.userSchema,
    this.isLoading = false,
    this.error,
    this.hiddenAttributes = const {'password'},
    this.onDelete,
    this.isDeleting = false,
    this.onUpdate,
    this.isUpdating = false,
    this.lifecycleActions = const [],
    this.onLifecycleAction,
    this.isRunningLifecycleAction = false,
    this.onSendVerification,
    this.isSendingVerification = false,
    this.sentVerification,
    this.actions = const [],
    this.preferences,
    this.builder,
  });

  @override
  State<BaseUserDetails> createState() => _BaseUserDetailsState();
}

class _BaseUserDetailsState extends State<BaseUserDetails> {
  Map<String, String>? _draft;
  String? _sendingAttribute;

  /// Sends a link for one of [sendable]; `null` while saving or sending.
  ValueChanged<String>? _sendAction(Set<String> sendable) {
    final onSend = widget.onSendVerification;
    if (sendable.isEmpty || widget.isUpdating || widget.isSendingVerification || onSend == null) return null;
    return (name) {
      if (!sendable.contains(name)) return;
      setState(() => _sendingAttribute = name);
      onSend(name);
    };
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final user = widget.user;
    final builder = widget.builder;
    final verifiable = adminVerifiableAttributes(user, widget.userSchema, widget.hiddenAttributes);
    final sendable = adminSendableAttributes(
      user,
      widget.userSchema,
      verifiable,
      canSend: widget.onSendVerification != null,
    );
    final sendAction = _sendAction(sendable);
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
          lifecycleActions: widget.onLifecycleAction != null && user != null ? widget.lifecycleActions : const [],
          onLifecycleAction: user != null ? widget.onLifecycleAction : null,
          isRunningLifecycleAction: widget.isRunningLifecycleAction,
          verifiableAttributes: verifiable,
          verifiedAttributes: user?.verifiedAttributes,
          sendableAttributes: sendable,
          onSendVerification: sendAction,
          isSendingVerification: widget.isSendingVerification,
          sentVerification: widget.sentVerification,
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
    final onLifecycleAction = widget.onLifecycleAction;
    final status = user.status?.value;
    final sent = widget.sentVerification;

    return AdminSection(
      ac: ac,
      block: 'user-details',
      title: displayName,
      description: ac.t('admin.users.details.subtitle', {'type': user.type}),
      actions: [
        ...widget.actions,
        if (onLifecycleAction != null && widget.lifecycleActions.isNotEmpty)
          AdminLifecycleButtons(
            ac: ac,
            actions: widget.lifecycleActions,
            name: displayName,
            block: 'user-details',
            onAction: onLifecycleAction,
            isRunning: widget.isRunningLifecycleAction,
            collectsOperatorNote: true,
          ),
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
        if (widget.error != null)
          AdminAlert(ac: ac, message: widget.error!, block: 'user-details')
        else if (sent != null && sent.emailSent == false)
          AdminAlert(ac: ac, message: ac.t('admin.users.details.verification.error'), block: 'user-details')
        else if (sent != null)
          AdminNotice(
            ac: ac,
            message: verificationSentMessage(ac, sent),
            identifier: 'thunderid-admin-user-details-verification-sent',
          ),
        Row(
          children: [
            AdminAvatar(name: displayName, size: 48),
            const SizedBox(width: 12),
            Flexible(child: Text(user.ouHandle ?? user.ouId, style: TextStyle(color: ac.colors.textSecondary))),
            if (status != null) ...[
              const SizedBox(width: 12),
              Semantics(
                label: ac.t('admin.common.columns.status'),
                child: AdminAccessStatusLabel(ac: ac, status: status),
              ),
            ],
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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in attributes)
                          if (verifiable.contains(entry.key))
                            AdminAttributeVerificationRow(
                              ac: ac,
                              block: 'user-details',
                              name: entry.key,
                              value: _stringify(entry.value),
                              isVerified: user.verifiedAttributes?[entry.key] != null,
                              isSending: widget.isSendingVerification && _sendingAttribute == entry.key,
                              isUpdating: widget.isUpdating || widget.isSendingVerification,
                              onSend: sendable.contains(entry.key) ? () => sendAction?.call(entry.key) : null,
                            )
                          else
                            AdminDetailList(ac: ac, items: [(entry.key, Text(_stringify(entry.value)))]),
                      ],
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
/// Changing data is off by default: set [deletable] to offer delete (with confirmation),
/// [editable] to offer editing the user's string attributes, [lifecycleActions] to offer
/// suspend, unsuspend and unlock, and [attributeVerification] to offer sending a verification link.
class UserDetails extends StatefulWidget {
  final String userId;
  final bool deletable;
  final bool editable;

  /// Whether the user can be suspended, unsuspended and unlocked from this view. Each action runs
  /// through its administration flow and is offered only when the user's status allows it and
  /// the server configures that flow. The configured flows are read only while this is on, and
  /// reading them needs a token that may read the server configuration.
  final bool lifecycleActions;

  /// Whether a verification link can be sent to the user's unverified email from this view. It
  /// runs the server's administrator-initiated verification flow, the user finishes from the
  /// link, and the user is read again afterwards. It is offered only when the server configures
  /// that flow (`adminAttributeVerificationFlow`), for an unverified attribute typed email in the
  /// user's type. The handle and the user type are read only while this is on; reading the handle
  /// needs a token that may read the server configuration.
  final bool attributeVerification;

  /// How the delete runs. [AdministrationMode.flow] runs the user deletion flow the server
  /// configures, which revokes the user's grants and ends their sessions before the record goes.
  final AdministrationMode administrationMode;
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
    this.lifecycleActions = false,
    this.attributeVerification = false,
    this.administrationMode = AdministrationMode.native,
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
  AdminLifecycleBinding? _lifecycle;
  ResourceMutation<SendUserAttributeVerificationVariables, UserAttributeVerificationResult>? _verification;
  ResourceQuery<Map<String, String>>? _verificationHandle;
  ResourceQuery<ManagedUserTypeDetails?>? _userType;
  String? _userTypeHandle;

  @override
  void bind(ManagementResources resources) {
    _userType = null;
    _userTypeHandle = null;
    _user = own(resources.userQuery(widget.userId))..addListener(_syncUserType);
    _groups = own(resources.userGroupsQuery(widget.userId, limit: 100));
    _delete = own(
      resources.deleteUserMutation(
        administrationMode: widget.administrationMode,
        onSuccess: (_, __) => widget.onDeleted?.call(),
      ),
    );
    _update = own(resources.updateUserMutation());
    _verification = own(resources.sendUserAttributeVerificationMutation());
    _verificationHandle = own(
      resources.adminAttributeVerificationHandleQuery(enabled: widget.attributeVerification),
    );
    _lifecycle = AdminLifecycleBinding(
      resources,
      AccountLifecycleSubjectKind.user,
      enabled: widget.lifecycleActions,
      own: own,
    );
  }

  /// Reads the user's type by handle when it changes, while verification is on.
  void _syncUserType() {
    final resources = this.resources;
    final handle = verificationUserTypeHandle(_user?.data, attributeVerification: widget.attributeVerification);
    if (resources == null || handle == _userTypeHandle) return;
    release(_userType);
    _userTypeHandle = handle;
    _userType = handle == null ? null : own(resources.userTypeByHandleQuery(handle));
  }

  @override
  void didUpdateWidget(UserDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.lifecycleActions != widget.lifecycleActions ||
        oldWidget.attributeVerification != widget.attributeVerification ||
        oldWidget.administrationMode != widget.administrationMode) {
      rebind();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final user = _user?.data;
    final delete = _delete;
    final update = _update;
    final lifecycle = _lifecycle;
    final verification = _verification;
    final verificationHandle = adminVerificationFlowHandle(
      enabled: widget.attributeVerification,
      configuredFlows: _verificationHandle?.data,
    );
    final userType = _userType?.data;
    final isUpdating = (update?.isLoading ?? false) || (_user?.isLoading ?? false);
    return BaseUserDetails(
      user: user,
      groups: _groups?.data?.items ?? const [],
      userSchema: userType != null && userType.handle == user?.type ? userType.schema : null,
      isLoading: _user?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.users.details.error')
          : toManagementErrorMessage(ac.t, _user?.error, 'admin.users.details.error') ??
              toManagementErrorMessage(ac.t, delete?.error, 'admin.users.details.delete.error') ??
              toManagementErrorMessage(ac.t, update?.error, 'admin.users.details.edit.error') ??
              toManagementErrorMessage(ac.t, verification?.error, 'admin.users.details.verification.error') ??
              lifecycle?.error(ac) ??
              toManagementErrorMessage(
                ac.t,
                _verificationHandle?.error ?? _userType?.error,
                'admin.users.details.verification.load_error',
              ),
      isDeleting: delete?.isLoading ?? false,
      onDelete: widget.deletable && delete != null ? () => unawaited(delete.mutate(widget.userId)) : null,
      isUpdating: isUpdating,
      onUpdate: widget.editable && update != null && user != null
          ? (attributes) {
              if (update.isLoading || (verification?.isLoading ?? false)) return;
              verification?.reset();
              unawaited(
                update.mutate(
                  (
                    userId: widget.userId,
                    data: UpdateManagedUserRequest(attributes: attributes, ouId: user.ouId, type: user.type),
                  ),
                ),
              );
            }
          : null,
      lifecycleActions: lifecycle?.actions(user?.status?.value) ?? const [],
      onLifecycleAction: lifecycle?.handler(widget.userId),
      isRunningLifecycleAction: lifecycle?.isRunning ?? false,
      isSendingVerification: verification?.isLoading ?? false,
      sentVerification: verification?.data,
      onSendVerification: verification != null && verificationHandle != null
          ? (attribute) {
              if (isUpdating || verification.isLoading) return;
              verification.reset();
              unawaited(verification.mutate((userId: widget.userId, attribute: attribute, handle: verificationHandle)));
            }
          : null,
      hiddenAttributes: widget.hiddenAttributes,
      actions: widget.actions,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
