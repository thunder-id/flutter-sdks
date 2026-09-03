// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/thunderid_i18n.dart';
import '../models/user.dart';
import '../models/user_profile.dart' as model;
import 'thunderid_provider.dart';
import 'user_avatar.dart';

// Attribute names that are always readonly regardless of schema mutability (data contract).
const Set<String> _readonlyFields = {
  'attributes',
  'id',
  'isReadOnly',
  'ouId',
  'username',
  'sub',
};

// Default logical-name -> attribute-path fallback mappings.
const Map<String, List<String>> _defaultAttributeMappings = {
  'email': ['emails', 'email'],
  'firstName': ['name.givenName', 'given_name'],
  'lastName': ['name.familyName', 'family_name'],
  'picture': ['profile', 'profileUrl', 'picture', 'URL'],
  'username': ['userName', 'username', 'user_name'],
};

/// A schema-described profile field merged with its current value, ready to render.
class ProfileField {
  final String name;
  final model.AttributeSchema schema;
  final dynamic rawValue;
  final bool isReadonly;
  final bool isMultiValued;

  const ProfileField({
    required this.name,
    required this.schema,
    required this.rawValue,
    required this.isReadonly,
    required this.isMultiValued,
  });

  /// Human label for the field, falling back to the raw attribute name.
  String get label => schema.displayName ?? schema.description ?? name;
}

/// Every non-credential schema attribute is shown by default.
List<ProfileField> buildProfileFields(
  Map<String, model.AttributeSchema> schema,
  model.UserProfile profile,
) {
  final names = schema.keys
      .where((name) => schema[name]?.credential != true)
      .toList()
    ..sort();
  return names.map((name) {
    final attribute = schema[name]!;
    final rawValue = profile.attributes[name];
    return ProfileField(
      name: name,
      schema: attribute,
      rawValue: rawValue,
      isReadonly: attribute.readOnly == true ||
          attribute.mutability == 'READ_ONLY' ||
          _readonlyFields.contains(name),
      isMultiValued: rawValue is List,
    );
  }).toList();
}

/// Builds a read-only field list directly from JWT/userinfo claims (no schema to save against).
List<ProfileField> buildProfileFieldsFromClaims(User? user) {
  final claims = user?.profileClaims ?? const <String, dynamic>{};
  final formatted = <String, String>{};
  for (final entry in claims.entries) {
    final value = formatClaim(entry.value);
    if (value != null) formatted[entry.key] = value;
  }
  final names = formatted.keys.toList()
    ..sort(
      (a, b) =>
          claimLabel(a).toLowerCase().compareTo(claimLabel(b).toLowerCase()),
    );
  return names
      .map(
        (name) => ProfileField(
          name: name,
          schema: model.AttributeSchema(
            displayName: claimLabel(name),
            readOnly: true,
            type: 'STRING',
          ),
          rawValue: formatted[name],
          isReadonly: true,
          isMultiValued: false,
        ),
      )
      .toList();
}

String? formatClaim(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return value.toString();
  if (value is List) {
    final items = value.map(formatClaim).whereType<String>().toList();
    return items.isEmpty ? null : items.join(', ');
  }
  return null;
}

/// Humanizes a claim key for display: `given_name` -> "Given Name".
String claimLabel(String key) => key
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .split(' ')
    .where((word) => word.isNotEmpty)
    .map((word) => word[0].toUpperCase() + word.substring(1))
    .join(' ');

String claimsDisplayName(User? user) {
  if (user == null) return 'Guest';
  final fullName = [user['given_name'], user['family_name']]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' ');
  if (fullName.isNotEmpty) return fullName;
  return user.displayName ?? user.username ?? user.email ?? 'Guest';
}

/// Validates an edited field value against its schema: required first, then regex.
///
/// Returns an i18n key, or null when the value is acceptable.
String? validateField(model.AttributeSchema schema, String value) {
  final trimmed = value.trim();
  if (schema.required == true && trimmed.isEmpty) {
    return 'userProfile.validation.required';
  }
  final pattern = schema.regex;
  if (pattern != null && pattern.isNotEmpty && trimmed.isNotEmpty) {
    try {
      if (!RegExp(pattern).hasMatch(trimmed)) {
        return 'userProfile.validation.pattern';
      }
    } on FormatException {
      // A pattern this platform cannot compile must not block the save.
    }
  }
  return null;
}

/// Resolves a logical attribute name (firstName, email, picture...) to a value on [profile]
/// by trying each candidate path in [mappings] in order, falling back to the built-in defaults.
String? mapAttribute(
  String key,
  Map<String, List<String>> mappings,
  model.UserProfile profile,
) {
  final candidates = mappings[key] ?? _defaultAttributeMappings[key];
  if (candidates == null) {
    final value = profile.attributes[key];
    return value == null ? null : '$value';
  }
  for (final path in candidates) {
    final resolved = _resolveAttributePath(profile.attributes, path);
    if (resolved != null) return '$resolved';
  }
  return null;
}

/// Combines mapped firstName/lastName into a display name, falling back to username then id.
String computeDisplayName(
  Map<String, List<String>> mappings,
  model.UserProfile profile,
) {
  final fullName = [
    mapAttribute('firstName', mappings, profile),
    mapAttribute('lastName', mappings, profile),
  ].whereType<String>().join(' ').trim();
  if (fullName.isNotEmpty) return fullName;
  return mapAttribute('username', mappings, profile) ?? profile.id;
}

Object? _resolveAttributePath(Map<String, dynamic> attributes, String path) {
  Object? current = attributes;
  for (final segment in path.split('.')) {
    if (current is! Map) return null;
    current = current[segment] as Object?;
  }
  return current;
}

/// Renders a raw field value for display/editing: joins list values, blanks out complex ones.
String stringifyFieldValue(Object? rawValue) {
  if (rawValue == null) return '';
  if (rawValue is List) return rawValue.map((e) => '$e').join(', ');
  if (rawValue is Map) return '';
  return '$rawValue';
}

/// Builds the nested attributes payload segment for a single dot-path field save.
Map<String, dynamic> buildUpdatePayload(
  String name,
  String value,
  bool isMultiValued, {
  String? type,
}) {
  final Object resolved;
  if (isMultiValued) {
    resolved = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  } else if (type == 'BOOLEAN') {
    // Editors hold every value as text; the schema types this one as a JSON
    // boolean, so send a real bool rather than the string 'true'/'false'.
    resolved = value.toLowerCase() == 'true';
  } else {
    resolved = value;
  }
  return _buildNestedMap(name.split('.'), resolved);
}

Map<String, dynamic> _buildNestedMap(List<String> segments, Object value) {
  if (segments.length == 1) return {segments.first: value};
  return {segments.first: _buildNestedMap(segments.sublist(1), value)};
}

/// Recursively merges [overrides] onto [base]. The backend requires every required attribute
/// present in any save, so a single-field edit still carries the rest of the profile along.
Map<String, dynamic> deepMergeAttributes(
  Map<String, dynamic> base,
  Map<String, dynamic> overrides,
) {
  final result = Map<String, dynamic>.from(base);
  overrides.forEach((key, value) {
    final existing = result[key];
    if (existing is Map<String, dynamic> && value is Map<String, dynamic>) {
      result[key] = deepMergeAttributes(existing, value);
    } else {
      result[key] = value;
    }
  });
  return result;
}

/// State exposed to [BaseUserProfile]'s builder.
class UserProfileState {
  final model.UserProfile? profile;
  final List<ProfileField> fields;
  final String displayName;
  final String? email;
  final bool isLoading;
  final String? error;

  final void Function(String name) edit;
  final void Function(String name) cancel;
  final void Function(String name, String value) setFieldValue;
  final void Function(String name) save;

  final Map<String, String> _editedValues;
  final Set<String> _editingFields;
  final Map<String, String> _fieldErrors;
  final Map<String, TextEditingController> _controllers;

  const UserProfileState({
    required this.profile,
    required this.fields,
    required this.displayName,
    required this.email,
    required this.isLoading,
    required this.error,
    required this.edit,
    required this.cancel,
    required this.setFieldValue,
    required this.save,
    required Map<String, String> editedValues,
    required Set<String> editingFields,
    required Map<String, String> fieldErrors,
    required Map<String, TextEditingController> controllers,
  })  : _editedValues = editedValues,
        _editingFields = editingFields,
        _fieldErrors = fieldErrors,
        _controllers = controllers;

  bool isEditing(String name) => _editingFields.contains(name);

  String fieldValue(ProfileField field) =>
      _editedValues[field.name] ?? stringifyFieldValue(field.rawValue);

  String? fieldError(String name) => _fieldErrors[name];

  /// Controller backing [name]'s text input for as long as it is being edited.
  TextEditingController? controllerFor(String name) => _controllers[name];
}

/// Editable, schema-driven user profile.
class UserProfile extends StatelessWidget {
  final Map<String, List<String>> attributeMapping;
  final VoidCallback? onSaved;
  final VoidCallback? onError;

  const UserProfile({
    super.key,
    this.attributeMapping = const {},
    this.onSaved,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final i18n = ThunderIDProvider.of(context).i18n;
    return BaseUserProfile(
      attributeMapping: attributeMapping,
      onSaved: onSaved,
      onError: onError,
      builder: (ctx, state) {
        if (state.isLoading && state.profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = state.error;
        if (error != null) {
          return Text(error, style: TextStyle(color: cs.error, fontSize: 13));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.displayName.isNotEmpty) ...[
              Column(
                children: [
                  const UserAvatar(size: 64),
                  const SizedBox(height: 8),
                  Text(state.displayName, style: tt.titleMedium),
                  if (state.email != null)
                    Text(
                      state.email!,
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            for (final field in state.fields) ...[
              _ProfileFieldRow(field: field, state: state, i18n: i18n),
              if (field != state.fields.last)
                Divider(height: 1, color: cs.outlineVariant),
            ],
          ],
        );
      },
    );
  }
}

class _ProfileFieldRow extends StatelessWidget {
  final ProfileField field;
  final UserProfileState state;
  final ThunderIDI18n i18n;

  const _ProfileFieldRow({
    required this.field,
    required this.state,
    required this.i18n,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEditing = state.isEditing(field.name);
    final isComplex = field.schema.type == 'COMPLEX' && field.rawValue is Map;
    final error = state.fieldError(field.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: isComplex
                    ? _ComplexValue(value: field.rawValue as Map)
                    : isEditing && !field.isReadonly
                        ? _FieldEditor(field: field, state: state)
                        : Text(
                            stringifyFieldValue(field.rawValue).isEmpty
                                ? '-'
                                : stringifyFieldValue(field.rawValue),
                            style: tt.bodyMedium,
                          ),
              ),
              if (isEditing && !field.isReadonly) ...[
                IconButton(
                  onPressed: () => state.save(field.name),
                  icon: const Icon(Icons.check),
                  tooltip: i18n.resolve('userProfile.save'),
                ),
                IconButton(
                  onPressed: () => state.cancel(field.name),
                  icon: const Icon(Icons.close),
                  tooltip: i18n.resolve('userProfile.cancel'),
                ),
              ] else if (!field.isReadonly && !isComplex)
                IconButton(
                  onPressed: () => state.edit(field.name),
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: i18n.resolve('userProfile.edit'),
                ),
            ],
          ),
          if (error != null)
            Text(error, style: tt.bodySmall?.copyWith(color: cs.error)),
        ],
      ),
    );
  }
}

class _FieldEditor extends StatelessWidget {
  final ProfileField field;
  final UserProfileState state;

  const _FieldEditor({required this.field, required this.state});

  @override
  Widget build(BuildContext context) {
    if (field.schema.type == 'BOOLEAN') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: field.label,
          child: Switch(
            value: state.fieldValue(field) == 'true',
            onChanged: (on) =>
                state.setFieldValue(field.name, on ? 'true' : 'false'),
          ),
        ),
      );
    }
    return Semantics(
      label: field.label,
      child: TextField(
        controller: state.controllerFor(field.name),
        onChanged: (value) => state.setFieldValue(field.name, value),
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
}

class _ComplexValue extends StatelessWidget {
  final Map<dynamic, dynamic> value;

  const _ComplexValue({required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in keys)
          Text('$key: ${value[key]}', style: tt.bodySmall),
      ],
    );
  }
}

/// Unstyled base variant (spec §8.3).
class BaseUserProfile extends StatefulWidget {
  final Map<String, List<String>> attributeMapping;
  final VoidCallback? onSaved;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, UserProfileState state) builder;

  const BaseUserProfile({
    super.key,
    required this.builder,
    this.attributeMapping = const {},
    this.onSaved,
    this.onError,
  });

  @override
  State<BaseUserProfile> createState() => _BaseUserProfileState();
}

class _BaseUserProfileState extends State<BaseUserProfile> {
  model.UserProfile? _profile;
  Map<String, model.AttributeSchema> _schema = const {};
  List<ProfileField> _fields = const [];
  String _displayName = '';
  String? _email;
  bool _isLoading = false;
  String? _error;

  final _editedValues = <String, String>{};
  final _editingFields = <String>{};
  final _fieldErrors = <String, String>{};
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final thunder = ThunderIDProvider.of(context);
    if (!thunder.fetchUserProfileEnabled) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Both requests are in flight before either is awaited. Future.wait attaches a
      // handler to each, so a failure on one does not escape as an unhandled exception
      // while the other is still pending; it rethrows the first error for the catch below.
      final results = await Future.wait<Object>([
        thunder.client.getUserSchema(),
        thunder.client.getUserProfile(),
      ]);
      if (!mounted) return;
      _schema = results[0] as Map<String, model.AttributeSchema>;
      _applyProfile(results[1] as model.UserProfile);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyProfile(model.UserProfile profile) {
    setState(() {
      _profile = profile;
      _fields = buildProfileFields(_schema, profile);
      _displayName = computeDisplayName(widget.attributeMapping, profile);
      _email = mapAttribute('email', widget.attributeMapping, profile);
    });
    // Reflect a save immediately, without waiting for the next refresh.
    ThunderIDProvider.of(context).mergeUserProfile(profile);
  }

  ProfileField? _fieldByName(String name) {
    for (final field in _fields) {
      if (field.name == name) return field;
    }
    return null;
  }

  void _editField(String name) {
    final field = _fieldByName(name);
    if (field == null) return;
    final initial = stringifyFieldValue(field.rawValue);
    setState(() {
      _editedValues[name] = initial;
      _editingFields.add(name);
      _fieldErrors.remove(name);
      _controllers.remove(name)?.dispose();
      _controllers[name] = TextEditingController(text: initial);
    });
  }

  void _cancelField(String name) {
    setState(() {
      _editingFields.remove(name);
      _editedValues.remove(name);
      _fieldErrors.remove(name);
      _controllers.remove(name)?.dispose();
    });
  }

  void _saveField(String name) {
    final field = _fieldByName(name);
    if (field == null) return;
    final value = _editedValues[name] ?? stringifyFieldValue(field.rawValue);
    final validationKey = validateField(field.schema, value);
    if (validationKey != null) {
      final message = ThunderIDProvider.of(context).i18n.resolve(validationKey);
      setState(() => _fieldErrors[name] = message);
      return;
    }
    setState(() => _fieldErrors.remove(name));
    unawaited(_performSave(name, field, value));
  }

  Future<void> _performSave(
    String name,
    ProfileField field,
    String value,
  ) async {
    setState(() => _isLoading = true);
    try {
      final client = ThunderIDProvider.of(context).client;
      final fieldPayload = buildUpdatePayload(
        name,
        value,
        field.isMultiValued,
        type: field.schema.type,
      );
      final payload = deepMergeAttributes(
        _profile?.attributes ?? const {},
        fieldPayload,
      );
      final updated = await client.updateUserProfile(payload);
      if (!mounted) return;
      _applyProfile(updated);
      setState(() {
        _editingFields.remove(name);
        _editedValues.remove(name);
        _controllers.remove(name)?.dispose();
      });
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _fieldErrors[name] = e.toString());
      widget.onError?.call();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thunder = ThunderIDProvider.of(context);
    // Without /users/me there is no schema to validate against and no endpoint to save
    // to, so the claims view is derived fresh on every build and stays read-only.
    if (!thunder.fetchUserProfileEnabled) {
      final user = thunder.user;
      return widget.builder(
        context,
        UserProfileState(
          profile: null,
          fields: buildProfileFieldsFromClaims(user),
          displayName: claimsDisplayName(user),
          email: user?.email,
          isLoading: false,
          error: null,
          edit: _ignoreName,
          cancel: _ignoreName,
          setFieldValue: _ignoreNameAndValue,
          save: _ignoreName,
          editedValues: const {},
          editingFields: const {},
          fieldErrors: const {},
          controllers: const {},
        ),
      );
    }
    return widget.builder(
      context,
      UserProfileState(
        profile: _profile,
        fields: _fields,
        displayName: _displayName,
        email: _email,
        isLoading: _isLoading,
        error: _error,
        edit: _editField,
        cancel: _cancelField,
        setFieldValue: _setFieldValue,
        save: _saveField,
        editedValues: _editedValues,
        editingFields: _editingFields,
        fieldErrors: _fieldErrors,
        controllers: _controllers,
      ),
    );
  }

  void _setFieldValue(String name, String value) {
    setState(() => _editedValues[name] = value);
  }

  static void _ignoreName(String name) {}

  static void _ignoreNameAndValue(String name, String value) {}
}
