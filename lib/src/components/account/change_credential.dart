// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../i18n/thunderid_i18n.dart';
import '../../models/thunderid_error.dart';
import '../internal/account_style.dart';
import '../thunderid_provider.dart';

/// The form field a credential-update failure belongs to.
enum CredentialField {
  /// The new value failed a server-side check.
  newValue,

  /// The failure has no single field to blame; show it at form level.
  form,
}

/// The derived state a change-credential form needs to render and gate submission.
///
/// Mirrors the Android/iOS SDKs: there is deliberately no current-value field, since the
/// self-service write path does not verify the account's existing value today.
class CredentialFormEvaluation {
  final bool confirmMatches;
  final bool meetsPolicy;
  final bool isValid;
  final bool patternChecked;
  final bool patternPassed;

  const CredentialFormEvaluation({
    required this.confirmMatches,
    required this.meetsPolicy,
    required this.isValid,
    required this.patternChecked,
    required this.patternPassed,
  });
}

/// Evaluates a change-credential form against an optional regex policy.
///
/// An uncompilable pattern is treated as passing, matching the Android/iOS SDKs: the client
/// stays lenient so a misconfigured schema can't lock a user out of their own credential change.
CredentialFormEvaluation evaluateCredentialForm(
  String newValue,
  String confirm,
  String? regex,
) {
  final patternChecked = regex != null && regex.isNotEmpty;
  var patternPassed = true;
  if (patternChecked) {
    try {
      patternPassed = RegExp(regex).hasMatch(newValue);
    } on FormatException {
      patternPassed = true;
    }
  }
  final meetsPolicy = !patternChecked || patternPassed;
  final confirmMatches = newValue == confirm;
  final isValid = newValue.isNotEmpty && confirm.isNotEmpty && meetsPolicy && confirmMatches;
  return CredentialFormEvaluation(
    confirmMatches: confirmMatches,
    meetsPolicy: meetsPolicy,
    isValid: isValid,
    patternChecked: patternChecked,
    patternPassed: patternPassed,
  );
}

/// Maps a failure from the credential write path onto the field that caused it. `invalidInput`
/// is the new value failing a server-side check.
CredentialField mapCredentialError(ThunderIDErrorCode code) =>
    code == ThunderIDErrorCode.invalidInput ? CredentialField.newValue : CredentialField.form;

/// Substitutes `{credential}`/`{credentialLower}` into a translation template.
String substituteCredential(String template, String displayName) => template
    .replaceAll('{credential}', displayName)
    .replaceAll('{credentialLower}', displayName.toLowerCase());

/// Resolves and substitutes a change-credential i18n key in one call.
String translateCredential(ThunderIDI18n i18n, String displayName, String key) =>
    substituteCredential(i18n.resolve(key), displayName);

/// Title-cases a credential name for use as its default display name, e.g. `pin` -> `Pin`.
String titleCaseCredential(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

/// State handed to [BaseChangeCredential]'s builder.
///
/// Reads live off its owning [_BaseChangeCredentialState] through getters, rather than
/// capturing values once at construction. A holder built before the underlying values change -
/// notably a full-screen edit page pushed via `Navigator.push`, which lives outside this
/// widget's own rebuild scope and so is never rebuilt by its `setState` calls - would otherwise
/// keep displaying the values (and `evaluation`, and therefore whether submitting is even
/// allowed) from the moment it was pushed, not the moment the user finished typing.
class ChangeCredentialState {
  final _BaseChangeCredentialState _owner;

  const ChangeCredentialState._(this._owner);

  String get credentialDisplayName => _owner._displayName;
  String get newValue => _owner._newValue;
  String get confirmValue => _owner._confirmValue;
  String? get error => _owner._error;
  bool get loading => _owner._loading;
  bool get success => _owner._success;
  bool get unavailable => _owner._unavailable;

  CredentialFormEvaluation get evaluation =>
      evaluateCredentialForm(_owner._newValue, _owner._confirmValue, _owner._regex);

  String? fieldError(CredentialField field) => _owner._fieldErrors[field];

  void onNewValueChanged(String value) => _owner._setNewValue(value);
  void onConfirmValueChanged(String value) => _owner._setConfirmValue(value);

  /// Resolves once the submission settles, success or failure. Read [success]/[error]/
  /// [fieldError] afterward (not this call's return value) for the outcome.
  Future<void> submit() => _owner._submit();

  /// Clears the typed values on Cancel, matching the Android/iOS SDKs. Field/form errors are
  /// deliberately left as-is here - both sibling SDKs only clear those at the start of the next
  /// submit, not on cancel.
  void resetValues() => _owner._resetValues();
}

/// Headless change-credential form (unstyled variant). Fetches the schema-derived policy for
/// [attribute], holds the network call and error routing, and hands its [ChangeCredentialState]
/// to [builder], mirroring the [BaseUserProfile] split.
class BaseChangeCredential extends StatefulWidget {
  final String attribute;
  final String? credentialDisplayName;
  final String? policyRegex;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, ChangeCredentialState state) builder;

  const BaseChangeCredential({
    super.key,
    this.attribute = 'password',
    this.credentialDisplayName,
    this.policyRegex,
    this.onSuccess,
    this.onError,
    required this.builder,
  });

  @override
  State<BaseChangeCredential> createState() => _BaseChangeCredentialState();
}

class _BaseChangeCredentialState extends State<BaseChangeCredential> {
  late String _displayName = widget.credentialDisplayName ?? titleCaseCredential(widget.attribute);
  String _newValue = '';
  String _confirmValue = '';
  String? _error;
  bool _loading = false;
  bool _success = false;
  bool _unavailable = false;
  String? _regex;
  final Map<CredentialField, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPolicy);
  }

  Future<void> _loadPolicy() async {
    if (!mounted) return;
    final thunder = ThunderIDProvider.of(context);
    try {
      final schema = await thunder.client.getUserSchema();
      final entry = schema[widget.attribute];
      if (!mounted) return;
      setState(() {
        _regex = widget.policyRegex ?? entry?.regex;
        _unavailable = entry?.credential != true;
        if (widget.credentialDisplayName == null && entry?.displayName != null) {
          _displayName = entry!.displayName!;
        }
      });
    } catch (_) {
      // A schema fetch failure leaves the form usable with no policy to check against, matching
      // Android/iOS: an unreachable schema shouldn't block a credential change outright.
    }
  }

  Future<void> _submit() async {
    final evaluation = evaluateCredentialForm(_newValue, _confirmValue, _regex);
    if (!evaluation.isValid || _loading || _unavailable) return;
    final thunder = ThunderIDProvider.of(context);
    setState(() {
      _error = null;
      _fieldErrors.clear();
      _success = false;
      _loading = true;
    });
    try {
      await thunder.client.updateUserCredentials(attribute: widget.attribute, newValue: _newValue);
      if (!mounted) return;
      setState(() {
        _newValue = '';
        _confirmValue = '';
        _success = true;
      });
      widget.onSuccess?.call();
    } on IAMException catch (e) {
      if (!mounted) return;
      setState(() => _applyError(thunder.i18n, e.code));
      widget.onError?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = translateCredential(thunder.i18n, _displayName, 'changeCredential.generic.error');
      });
      widget.onError?.call();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyError(ThunderIDI18n i18n, ThunderIDErrorCode code) {
    final message = translateCredential(i18n, _displayName, 'changeCredential.generic.error');
    if (mapCredentialError(code) == CredentialField.newValue) {
      _fieldErrors[CredentialField.newValue] = message;
    } else {
      _error = message;
    }
  }

  void _setNewValue(String value) => setState(() => _newValue = value);
  void _setConfirmValue(String value) => setState(() => _confirmValue = value);

  void _resetValues() => setState(() {
        _newValue = '';
        _confirmValue = '';
      });

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, ChangeCredentialState._(this));
  }
}

/// Styled change-credential row (spec §8.3 styled variant), presented the same way as a
/// [UserProfile] field row. Tapping its Update link pushes a full-screen form collecting the
/// new value and its confirmation.
///
/// The display name always comes from the schema's `displayName` for [attribute] (falling back
/// to the title-cased attribute name). Rename it from the ThunderID console rather than
/// overriding it in code: this widget has no parameter for that, so the schema stays the single
/// source of truth.
class ChangeCredential extends StatelessWidget {
  final String attribute;
  final VoidCallback? onSuccess;

  /// Whether to draw the row's bottom divider, matching [UserProfile]'s field rows. Set to
  /// `false` on the last credential row in a list to avoid a trailing divider.
  final bool showDivider;

  const ChangeCredential({
    super.key,
    this.attribute = 'password',
    this.onSuccess,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = ThunderIDProvider.of(context).i18n;
    return BaseChangeCredential(
      attribute: attribute,
      onSuccess: onSuccess,
      builder: (context, state) {
        return ThunderAccountRow(
          label: state.credentialDisplayName,
          value: state.unavailable ? i18n.resolve('changeCredential.unavailable.description') : '',
          editLabel: i18n.resolve('changeCredential.update'),
          showDivider: showDivider,
          identifier: 'thunderid-action-openCredential-$attribute',
          onEdit: state.unavailable ? null : () => _openEditor(context, state, i18n),
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context, ChangeCredentialState state, ThunderIDI18n i18n) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _ChangeCredentialEditPage(state: state, i18n: i18n),
      ),
    );
  }
}

class _ChangeCredentialEditPage extends StatefulWidget {
  final ChangeCredentialState state;
  final ThunderIDI18n i18n;

  const _ChangeCredentialEditPage({required this.state, required this.i18n});

  @override
  State<_ChangeCredentialEditPage> createState() => _ChangeCredentialEditPageState();
}

class _ChangeCredentialEditPageState extends State<_ChangeCredentialEditPage> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await widget.state.submit();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (widget.state.success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = widget.i18n;
    final state = widget.state;
    final evaluation = state.evaluation;
    final newInvalid = state.newValue.isNotEmpty && evaluation.patternChecked && !evaluation.patternPassed;
    final confirmMismatch = state.confirmValue.isNotEmpty && !evaluation.confirmMatches;

    final fieldError = newInvalid
        ? (state.fieldError(CredentialField.newValue) ??
            translateCredential(i18n, state.credentialDisplayName, 'changeCredential.requirements.pattern'))
        : confirmMismatch
            ? translateCredential(i18n, state.credentialDisplayName, 'changeCredential.mismatch.error')
            : state.fieldError(CredentialField.newValue);

    return ThunderAccountEditPage(
      title: translateCredential(i18n, state.credentialDisplayName, 'changeCredential.heading'),
      description: translateCredential(i18n, state.credentialDisplayName, 'changeCredential.description'),
      cancelLabel: i18n.resolve('userProfile.cancel'),
      saveLabel: i18n.resolve('userProfile.save'),
      backLabel: i18n.resolve('changeCredential.section'),
      cancelIdentifier: 'thunderid-action-cancelCredential',
      saveIdentifier: 'thunderid-action-submitCredential',
      onCancel: () {
        state.resetValues();
        Navigator.of(context).pop();
      },
      onSave: evaluation.isValid && !_submitting ? _submit : null,
      errorText: state.error ?? fieldError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThunderAccountField(
            label:
                translateCredential(i18n, state.credentialDisplayName, 'changeCredential.new.label'),
            identifier: 'thunderid-field-newCredential',
            obscureText: true,
            // state.onNewValueChanged updates BaseChangeCredential's own state, which lives
            // outside this page's rebuild scope (it was reached via Navigator.push, not as a
            // descendant), so its setState alone would not repaint this page. The extra
            // setState(() {}) is what makes the Save button's enabled state, and the mismatch/
            // pattern hints below, actually track each keystroke here.
            onChanged: (value) {
              state.onNewValueChanged(value);
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          ThunderAccountField(
            label: translateCredential(
              i18n,
              state.credentialDisplayName,
              'changeCredential.confirm.label',
            ),
            identifier: 'thunderid-field-confirmCredential',
            obscureText: true,
            onChanged: (value) {
              state.onConfirmValueChanged(value);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
