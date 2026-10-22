// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../management/management_display.dart';
import '../../models/management/managed_user.dart';
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

/// The input type of a [UserCreateField].
enum UserCreateFieldType { text, email, password, phone }

/// One attribute field of the user-create form.
class UserCreateField {
  /// The attribute name, e.g. `username`.
  final String name;

  /// The label; defaults to the `admin.users.create.fields.<name>` translation.
  final String? label;
  final bool required;
  final UserCreateFieldType type;

  const UserCreateField({
    required this.name,
    this.label,
    this.required = false,
    this.type = UserCreateFieldType.text,
  });

  /// The fields shown when none are passed.
  static const List<UserCreateField> defaults = [
    UserCreateField(name: 'username', required: true),
    UserCreateField(name: 'email', required: true, type: UserCreateFieldType.email),
    UserCreateField(name: 'given_name'),
    UserCreateField(name: 'family_name'),
    UserCreateField(name: 'password', type: UserCreateFieldType.password),
  ];
}

/// What [BaseUserCreate] submits: the chosen user type and the non-empty attribute values.
class UserCreateSubmission {
  final String type;
  final Map<String, String> attributes;

  const UserCreateSubmission({required this.type, required this.attributes});
}

/// Presentational user-create form. Collects a user type and the [fields], and hands them to
/// [onSubmit]; it makes no request itself. Use [UserCreate] to have it create the user.
class BaseUserCreate extends StatefulWidget {
  final List<AdminSelectOption> userTypes;
  final ValueChanged<UserCreateSubmission> onSubmit;
  final List<UserCreateField> fields;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the user types, the fields, the type and attribute values with their setters, the submit action and the submission state.
  final AdminWidgetBuilder<UserCreateFormState>? builder;

  const BaseUserCreate({
    super.key,
    required this.userTypes,
    required this.onSubmit,
    this.fields = UserCreateField.defaults,
    this.isSubmitting = false,
    this.error,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<BaseUserCreate> createState() => _BaseUserCreateState();
}

class _BaseUserCreateState extends State<BaseUserCreate> {
  String? _type;
  final Map<String, String> _values = {};

  String get _resolvedType => _type ?? (widget.userTypes.isEmpty ? '' : widget.userTypes.first.value);

  bool get _isComplete =>
      _resolvedType.isNotEmpty &&
      widget.fields.every((field) => !field.required || (_values[field.name]?.trim().isNotEmpty ?? false));

  void _submit() {
    if (!_isComplete || widget.isSubmitting) return;
    widget.onSubmit(
      UserCreateSubmission(
        type: _resolvedType,
        attributes: {
          for (final entry in _values.entries)
            if (entry.value.trim().isNotEmpty) entry.key: entry.value,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        UserCreateFormState(
          userTypes: widget.userTypes,
          fields: widget.fields,
          type: _resolvedType,
          onTypeChanged: (value) => setState(() => _type = value),
          values: Map.unmodifiable(_values),
          onValueChanged: (name, value) => setState(() => _values[name] = value),
          isValid: _isComplete,
          isSubmitting: widget.isSubmitting,
          error: widget.error,
          submit: _submit,
          onCancel: widget.onCancel,
        ),
      );
    }
    return AdminSection(
      ac: ac,
      block: 'user-create',
      title: widget.title ?? ac.t('admin.users.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'user-create'),
        AdminDropdown(
          ac: ac,
          label: ac.t('admin.users.create.fields.type'),
          identifier: 'thunderid-field-user-create-type',
          value: _resolvedType,
          options: widget.userTypes,
          onChanged: (value) => setState(() => _type = value),
        ),
        for (final field in widget.fields)
          AdminTextField(
            key: ValueKey('user-create-${field.name}'),
            ac: ac,
            label: field.label ?? ac.t('admin.users.create.fields.${field.name}'),
            identifier: 'thunderid-field-user-create-${field.name}',
            required: field.required,
            obscureText: field.type == UserCreateFieldType.password,
            keyboardType: switch (field.type) {
              UserCreateFieldType.email => TextInputType.emailAddress,
              UserCreateFieldType.phone => TextInputType.phone,
              _ => TextInputType.text,
            },
            onChanged: (value) => setState(() => _values[field.name] = value),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (widget.onCancel != null)
              AdminButton(
                ac: ac,
                label: ac.t('admin.common.actions.cancel'),
                identifier: 'thunderid-action-user-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.users.create.submit'),
              identifier: 'thunderid-action-user-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: _isComplete && !widget.isSubmitting ? _submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// User-create form that creates the user through the management API.
///
/// The user is created in [ouId], or the signed-in user's own organization unit when omitted.
class UserCreate extends StatefulWidget {
  final String? ouId;
  final ValueChanged<ManagedUser>? onCreated;
  final List<UserCreateField> fields;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseUserCreate.builder].
  final AdminWidgetBuilder<UserCreateFormState>? builder;

  const UserCreate({
    super.key,
    this.ouId,
    this.onCreated,
    this.fields = UserCreateField.defaults,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<UserCreate> createState() => _UserCreateState();
}

class _UserCreateState extends AdminConnectedState<UserCreate> {
  ResourceQuery<ManagementPage<ManagedUserType>>? _types;
  ResourceMutation<CreateManagedUserRequest, ManagedUser>? _create;

  @override
  void bind(ManagementResources resources) {
    _types = own(resources.userTypesQuery(limit: 100));
    _create = own(resources.createUserMutation(onSuccess: (user, _) => widget.onCreated?.call(user)));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final ouId = widget.ouId ?? thunder?.defaultOuId;
    final create = _create;
    return BaseUserCreate(
      userTypes: [
        for (final type in _types?.data?.items ?? const <ManagedUserType>[])
          AdminSelectOption(value: type.handle, label: type.displayName ?? type.handle),
      ],
      isSubmitting: create?.isLoading ?? false,
      error: ouId == null
          ? ac.t('admin.common.errors.no_ou')
          : toManagementErrorMessage(ac.t, create?.error, 'admin.users.create.error'),
      onSubmit: (submission) {
        if (ouId == null || create == null) return;
        unawaited(
          create.mutate(
            CreateManagedUserRequest(ouId: ouId, type: submission.type, attributes: submission.attributes),
          ),
        );
      },
      fields: widget.fields,
      onCancel: widget.onCancel,
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
