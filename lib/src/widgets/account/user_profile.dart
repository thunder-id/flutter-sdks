// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/thunderid_i18n.dart';
import '../../models/attribute_verification.dart';
import '../../models/user.dart';
import '../../models/user_profile.dart' as model;
import '../internal/account_style.dart';
import '../thunderid_provider.dart';
import 'user_profile_verification.dart';
import 'verify_attribute.dart';

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

  /// A nested-object attribute. Matches the Android/iOS SDKs: such fields render read-only via
  /// a dedicated key:value display and never get an Edit affordance, since the edit page's plain
  /// text field has no way to write a structured value back without corrupting it.
  bool get isComplex => schema.type == 'COMPLEX' && rawValue is Map;
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

/// Finds the schema field, if any, that [mapAttribute]'s `'picture'` candidates would resolve -
/// what the styled [UserProfile]'s avatar edit badge edits, so the two stay in sync with no
/// separate configuration of their own.
ProfileField? _findPictureField(List<ProfileField> fields, Map<String, List<String>> mappings) {
  final candidates = mappings['picture'] ?? _defaultAttributeMappings['picture']!;
  for (final candidate in candidates) {
    for (final field in fields) {
      if (field.name == candidate) return field;
    }
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

/// Renders a COMPLEX field's map value as one `key: value` line per entry, matching the
/// Android/iOS SDKs' dedicated complex-value display.
String stringifyComplexValue(Map<Object?, Object?> rawValue) =>
    rawValue.entries.map((e) => '${e.key}: ${e.value}').join('\n');

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

  /// Resolves once the save attempt settles, success or failure — awaiting it (rather than
  /// firing and forgetting) is what lets a styled edit screen know whether to close itself or
  /// stay open showing [fieldError].
  final Future<void> Function(String name) save;

  /// The attribute whose verification is open, if any: one the user chose to verify, or a changed
  /// email just saved. A builder shows [VerifyAttribute] for it; the profile that reads again then
  /// updates [verificationStatus].
  final String? verifyingField;

  /// Opens verification of an attribute [canVerify] allows.
  final void Function(String name) verify;

  /// Closes the open verification.
  final VoidCallback closeVerification;

  /// Applies the profile a verification read again, so the recorded status shows. Null leaves the
  /// profile as it is.
  final void Function(model.UserProfile? profile) applyVerifiedProfile;

  final Map<String, String> _editedValues;
  final Set<String> _editingFields;
  final Map<String, String> _fieldErrors;
  final Map<String, model.AttributeSchema> _schema;

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
    this.verifyingField,
    this.verify = _ignoreVerify,
    this.closeVerification = _ignoreClose,
    this.applyVerifiedProfile = _ignoreProfile,
    Map<String, model.AttributeSchema> schema = const {},
  })  : _editedValues = editedValues,
        _editingFields = editingFields,
        _fieldErrors = fieldErrors,
        _schema = schema;

  bool isEditing(String name) => _editingFields.contains(name);

  String fieldValue(ProfileField field) =>
      _editedValues[field.name] ?? stringifyFieldValue(field.rawValue);

  String? fieldError(String name) => _fieldErrors[name];

  /// The verification status of [name]'s stored value, or null when none is shown: the server
  /// does not report verification, the attribute is not an `email` or `mobile` property, or its
  /// value is being edited or saved.
  AttributeVerificationStatus? verificationStatus(String name) {
    final field = _field(name);
    if (field == null) return null;
    return verificationStatusOf(
      name: name,
      schemaType: field.schema.type,
      storedValue: field.rawValue,
      verified: profile?.verifiedAttributes,
      isEditing: isEditing(name),
    );
  }

  /// When [name]'s stored value was verified, as the server reports it.
  String? verifiedAt(String name) {
    if (verificationStatus(name) != AttributeVerificationStatus.verified) {
      return null;
    }
    final verified = profile?.verifiedAttributes;
    return verified == null ? null : verified[name]?.verifiedAt;
  }

  /// Whether the user can verify [name] now: its stored value is unverified, it is a verifiable
  /// schema property, the profile is not read-only, and its verification is not already open.
  bool canVerify(String name) =>
      verificationStatus(name) == AttributeVerificationStatus.unverified &&
      verifyingField != name &&
      profile?.isReadOnly != true &&
      AttributeVerification.isVerifiableAttribute(name, _schema);

  ProfileField? _field(String name) {
    for (final field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }
}

void _ignoreVerify(String name) {}

void _ignoreClose() {}

void _ignoreProfile(model.UserProfile? profile) {}

/// Editable, schema-driven user profile. Renders an avatar header followed by one row per
/// schema field; tapping a row's Edit link pushes a full-screen edit page for that field.
///
/// Deliberately not built on Material widgets beyond primitives like `TextField`/`InkWell`: see
/// `internal/account_style.dart` for why.
///
/// A stored email address or mobile number shows its verification status, as the server reports
/// it, and an unverified one a Verify action that opens [VerifyAttribute] under the row, running the
/// flow named by [verificationFlowHandle]. Saving a changed email opens it by itself.
class UserProfile extends StatelessWidget {
  final Map<String, List<String>> attributeMapping;
  final VoidCallback? onSaved;
  final VoidCallback? onError;
  final String verificationFlowHandle;

  const UserProfile({
    super.key,
    this.attributeMapping = const {},
    this.onSaved,
    this.onError,
    this.verificationFlowHandle = AttributeVerification.defaultFlowHandle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final i18n = ThunderIDProvider.of(context).i18n;
    return BaseUserProfile(
      attributeMapping: attributeMapping,
      onSaved: onSaved,
      onError: onError,
      builder: (context, state) {
        if (state.isLoading && state.profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = state.error;
        if (error != null) {
          return Text(error, style: TextStyle(color: colors.error, fontSize: 13));
        }
        final pictureField = _findPictureField(state.fields, attributeMapping);
        // Every schema field is shown, including read-only ones like username - they just get
        // no Edit link, matching the Android/iOS SDKs rather than disappearing entirely. The
        // picture field, if any, is edited through the avatar's own badge instead of appearing
        // a second time as a plain URL row.
        final visibleFields = state.fields.where((f) => f != pictureField).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.displayName.isNotEmpty) ...[
              Center(
                child: Column(
                  children: [
                    ThunderAccountAvatar(
                      onEdit: pictureField == null
                          ? null
                          : () => _openFieldEditor(context, state, pictureField, i18n),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.displayName,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                    ),
                    if (state.email != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          state.email!,
                          style: TextStyle(fontSize: 13, color: colors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (visibleFields.isNotEmpty) ...[
              for (final field in visibleFields) ...[
                ThunderAccountRow(
                  label: field.label,
                  value: _fieldDisplayValue(field),
                  editLabel: i18n.resolve('userProfile.edit'),
                  showDivider: field != visibleFields.last &&
                      state.verifyingField != field.name,
                  onEdit: field.isReadonly || field.isComplex
                      ? null
                      : () => _openFieldEditor(context, state, field, i18n),
                  detail: _verificationDetail(state, field, i18n),
                ),
                if (state.verifyingField == field.name)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    // BaseUserProfile's VerifiedProfileSink takes the profile it reads again.
                    child: VerifyAttribute(
                      key: ValueKey('verify-${field.name}'),
                      attribute: field.name,
                      flowHandle: verificationFlowHandle,
                      attributeDisplayName: field.label,
                      onDone: state.closeVerification,
                      onCancel: state.closeVerification,
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }

  /// The status badge and, for an unverified value, the Verify link, under a row's stored value.
  Widget? _verificationDetail(
    UserProfileState state,
    ProfileField field,
    ThunderIDI18n i18n,
  ) {
    final status = state.verificationStatus(field.name);
    if (status == null) return null;
    final canVerify = state.canVerify(field.name);
    final identifier = 'thunderid-verify-${field.name}';
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        VerificationStatusBadge(
          status: status,
          verifiedAt: state.verifiedAt(field.name),
          i18n: i18n,
          identifier: 'thunderid-verification-status-${field.name}',
        ),
        if (canVerify)
          Semantics(
            identifier: identifier,
            button: true,
            child: InkWell(
              key: Key(identifier),
              onTap: () => state.verify(field.name),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  widthFactor: 1,
                  child: Text(
                    i18n.resolve('userProfile.verification.verify'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _fieldDisplayValue(ProfileField field) {
    final value =
        field.isComplex ? stringifyComplexValue(field.rawValue as Map) : stringifyFieldValue(field.rawValue);
    return value.isEmpty ? '-' : value;
  }

  void _openFieldEditor(
    BuildContext context,
    UserProfileState state,
    ProfileField field,
    ThunderIDI18n i18n,
  ) {
    state.edit(field.name);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, animation, secondaryAnimation) => _ProfileFieldEditPage(
          field: field,
          state: state,
          i18n: i18n,
        ),
      ),
    );
  }
}

class _ProfileFieldEditPage extends StatefulWidget {
  final ProfileField field;
  final UserProfileState state;
  final ThunderIDI18n i18n;

  const _ProfileFieldEditPage({required this.field, required this.state, required this.i18n});

  @override
  State<_ProfileFieldEditPage> createState() => _ProfileFieldEditPageState();
}

class _ProfileFieldEditPageState extends State<_ProfileFieldEditPage> {
  // Owned locally rather than by BaseUserProfile's state, and disposed in this State's own
  // dispose(). A PageRouteBuilder's popped page stays mounted (and can keep rebuilding, e.g. on
  // every frame of its own exit transition) for a stretch after Navigator.pop() is called, not
  // just until that call returns - a controller owned elsewhere and disposed as soon as pop()
  // was called raced that transition and could be disposed while this page's TextField was
  // still actively using it (a "TextEditingController used after being disposed" crash).
  // Flutter guarantees dispose() below only runs once this page's Element is actually removed,
  // which is what makes this version safe.
  late final TextEditingController _controller =
      TextEditingController(text: widget.state.fieldValue(widget.field));
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.state.save(widget.field.name);
    if (!mounted) return;
    setState(() => _saving = false);
    // A save that fails leaves isEditing(field.name) true with fieldError set, so the page
    // stays open showing the error; only a successful save (which clears editingFields) pops.
    if (!widget.state.isEditing(widget.field.name)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final state = widget.state;
    return ThunderAccountEditPage(
      title: field.label,
      description: widget.i18n.resolve('userProfile.editDescription'),
      cancelLabel: widget.i18n.resolve('userProfile.cancel'),
      saveLabel: widget.i18n.resolve('userProfile.save'),
      cancelIdentifier: 'thunderid-action-cancelProfileField',
      saveIdentifier: 'thunderid-action-saveProfileField',
      backLabel: widget.i18n.resolve('userProfile.title'),
      onCancel: () {
        state.cancel(field.name);
        Navigator.of(context).pop();
      },
      onSave: _saving ? null : _save,
      errorText: state.fieldError(field.name),
      child: field.schema.type == 'BOOLEAN'
          ? Align(
              alignment: Alignment.centerLeft,
              child: Switch(
                value: state.fieldValue(field) == 'true',
                onChanged: (on) => state.setFieldValue(field.name, on ? 'true' : 'false'),
              ),
            )
          : ThunderAccountField(
              label: field.label,
              identifier: 'thunderid-field-profile-${field.name}',
              controller: _controller,
              onChanged: (value) => state.setFieldValue(field.name, value),
            ),
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
  String? _verifyingField;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
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
    setState(() {
      // A verification describes the stored value, so editing it closes the verification.
      if (_verifyingField == name) _verifyingField = null;
      _editedValues[name] = stringifyFieldValue(field.rawValue);
      _editingFields.add(name);
      _fieldErrors.remove(name);
    });
  }

  void _cancelField(String name) {
    setState(() {
      _editingFields.remove(name);
      _editedValues.remove(name);
      _fieldErrors.remove(name);
    });
  }

  Future<void> _saveField(String name) async {
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
    await _performSave(name, field, value);
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
      final opensVerification = shouldVerifyAfterSave(
        name: name,
        schema: _schema,
        previousValue: field.rawValue,
        saved: updated,
      );
      _applyProfile(updated);
      setState(() {
        _editingFields.remove(name);
        _editedValues.remove(name);
        if (opensVerification) {
          _verifyingField = name;
        } else if (_verifyingField == name) {
          _verifyingField = null;
        }
      });
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _fieldErrors[name] = ThunderIDProvider.of(context)
            .i18n
            .resolve('userProfile.error.save'),
      );
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
          save: _ignoreNameAsync,
          editedValues: const {},
          editingFields: const {},
          fieldErrors: const {},
        ),
      );
    }
    // A VerifyAttribute the builder shows hands the profile it reads again here, so the status updates.
    return VerifiedProfileSink(
      onProfileRead: _applyVerifiedProfile,
      child: widget.builder(
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
          verifyingField: _verifyingField,
          verify: _verify,
          closeVerification: _closeVerification,
          applyVerifiedProfile: _applyVerifiedProfile,
          schema: _schema,
        ),
      ),
    );
  }

  void _verify(String name) {
    final field = _fieldByName(name);
    if (field == null ||
        _profile?.isReadOnly == true ||
        verificationStatusOf(
              name: name,
              schemaType: field.schema.type,
              storedValue: field.rawValue,
              verified: _profile?.verifiedAttributes,
              isEditing: _editingFields.contains(name),
            ) !=
            AttributeVerificationStatus.unverified ||
        !AttributeVerification.isVerifiableAttribute(name, _schema)) {
      return;
    }
    setState(() => _verifyingField = name);
  }

  void _closeVerification() {
    setState(() => _verifyingField = null);
  }

  void _applyVerifiedProfile(model.UserProfile? profile) {
    if (profile != null && mounted) _applyProfile(profile);
  }

  void _setFieldValue(String name, String value) {
    setState(() => _editedValues[name] = value);
  }

  static void _ignoreName(String name) {}

  static Future<void> _ignoreNameAsync(String name) async {}

  static void _ignoreNameAndValue(String name, String value) {}
}
