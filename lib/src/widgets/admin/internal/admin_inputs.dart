// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../identity_candidate.dart';
import 'admin_context.dart';

// Package-internal (not exported): controls shared by the admin components. Every control is at
// least 44x44 logical pixels and exposes a stable identifier through `Semantics.identifier`
// (and the same value as its widget [Key], for widget tests).

enum AdminButtonVariant { primary, outline, text, danger, dangerOutline, dangerText }

class AdminButton extends StatelessWidget {
  final AdminContext ac;
  final String label;
  final String identifier;
  final VoidCallback? onPressed;
  final AdminButtonVariant variant;
  final bool isLoading;

  /// Overrides the accessible name when [label] alone is ambiguous, e.g. "Remove" in a list.
  final String? semanticLabel;

  const AdminButton({
    super.key,
    required this.ac,
    required this.label,
    required this.identifier,
    required this.onPressed,
    this.variant = AdminButtonVariant.primary,
    this.isLoading = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ac.colors;
    final danger = variant == AdminButtonVariant.danger ||
        variant == AdminButtonVariant.dangerOutline ||
        variant == AdminButtonVariant.dangerText;
    final accent = danger ? colors.error : colors.primary;
    final filled = variant == AdminButtonVariant.primary || variant == AdminButtonVariant.danger;
    final outlined = variant == AdminButtonVariant.outline || variant == AdminButtonVariant.dangerOutline;
    final enabled = onPressed != null && !isLoading;
    final foreground = filled ? (danger ? colors.onError : colors.onPrimary) : accent;

    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => filled
            ? accent.withValues(alpha: states.contains(WidgetState.disabled) ? 0.4 : 1)
            : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) && !filled
            ? foreground.withValues(alpha: 0.4)
            : foreground,
      ),
      side: WidgetStatePropertyAll(outlined ? BorderSide(color: accent) : BorderSide.none),
      elevation: const WidgetStatePropertyAll(0),
    );

    final child = isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
              ),
              const SizedBox(width: 8),
              Text(label, semanticsLabel: semanticLabel),
            ],
          )
        : Text(label, semanticsLabel: semanticLabel);

    return Semantics(
      identifier: identifier,
      child: TextButton(
        key: Key(identifier),
        style: style,
        onPressed: enabled ? onPressed : null,
        child: child,
      ),
    );
  }
}

/// A labelled single-line text input.
class AdminTextField extends StatefulWidget {
  final AdminContext ac;
  final String label;
  final String identifier;
  final ValueChanged<String> onChanged;
  final String initialValue;
  final bool obscureText;
  final bool required;
  final TextInputType? keyboardType;
  final bool enabled;

  /// Called with the text when the keyboard's action button is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Shown inside the field while it is empty.
  final String? hint;

  const AdminTextField({
    super.key,
    required this.ac,
    required this.label,
    required this.identifier,
    required this.onChanged,
    this.initialValue = '',
    this.obscureText = false,
    this.required = false,
    this.keyboardType,
    this.enabled = true,
    this.onSubmitted,
    this.hint,
  });

  @override
  State<AdminTextField> createState() => _AdminTextFieldState();
}

class _AdminTextFieldState extends State<AdminTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.ac.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        identifier: widget.identifier,
        textField: true,
        child: TextField(
          key: Key(widget.identifier),
          controller: _controller,
          enabled: widget.enabled,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          autocorrect: false,
          enableSuggestions: !widget.obscureText,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          textInputAction: widget.onSubmitted == null ? null : TextInputAction.search,
          style: TextStyle(color: colors.text, fontSize: 15),
          decoration: InputDecoration(
            labelText: widget.required ? '${widget.label} *' : widget.label,
            hintText: widget.hint,
            labelStyle: TextStyle(color: colors.textSecondary),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: border(colors.border),
            enabledBorder: border(colors.border),
            focusedBorder: border(colors.primary),
          ),
        ),
      ),
    );
  }
}

/// A labelled select over [options].
class AdminDropdown extends StatelessWidget {
  final AdminContext ac;
  final String label;
  final String identifier;
  final String? value;
  final List<AdminSelectOption> options;
  final ValueChanged<String> onChanged;

  /// Shown when nothing is selected.
  final String? placeholder;

  /// Shown, disabled, when there are no [options].
  final String? emptyText;

  const AdminDropdown({
    super.key,
    required this.ac,
    required this.label,
    required this.identifier,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ac.colors;
    final selected = options.any((option) => option.value == value) ? value : null;
    final hint = options.isEmpty ? emptyText : placeholder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        identifier: identifier,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: colors.textSecondary),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: Key(identifier),
              isExpanded: true,
              value: selected,
              dropdownColor: colors.background,
              // Inherit the surrounding font: DropdownButton uses this style as-is for the selected value.
              style: DefaultTextStyle.of(context).style.copyWith(color: colors.text, fontSize: 15),
              hint: hint == null ? null : Text(hint, style: TextStyle(color: colors.textSecondary)),
              items: [
                for (final option in options)
                  DropdownMenuItem<String>(
                    key: Key('$identifier-option-${option.value}'),
                    value: option.value,
                    child: Text(option.label),
                  ),
              ],
              onChanged: options.isEmpty
                  ? null
                  : (next) {
                      if (next != null) onChanged(next);
                    },
            ),
          ),
        ),
      ),
    );
  }
}

/// A destructive action that asks for confirmation inline before it runs (spec "UI",
/// requirement 6: a delete MUST ask for confirmation).
class AdminConfirmButton extends StatefulWidget {
  final AdminContext ac;
  final String label;
  final String confirmText;
  final String identifier;
  final VoidCallback onConfirm;
  final bool isLoading;

  const AdminConfirmButton({
    super.key,
    required this.ac,
    required this.label,
    required this.confirmText,
    required this.identifier,
    required this.onConfirm,
    this.isLoading = false,
  });

  @override
  State<AdminConfirmButton> createState() => _AdminConfirmButtonState();
}

class _AdminConfirmButtonState extends State<AdminConfirmButton> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final ac = widget.ac;
    if (!_confirming && !widget.isLoading) {
      return AdminButton(
        ac: ac,
        label: widget.label,
        identifier: widget.identifier,
        variant: AdminButtonVariant.dangerOutline,
        onPressed: () => setState(() => _confirming = true),
      );
    }
    return Semantics(
      container: true,
      label: widget.confirmText,
      liveRegion: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(widget.confirmText, style: TextStyle(color: ac.colors.text)),
          AdminButton(
            ac: ac,
            label: ac.t('admin.common.actions.cancel'),
            identifier: '${widget.identifier}-cancel',
            variant: AdminButtonVariant.text,
            onPressed: widget.isLoading ? null : () => setState(() => _confirming = false),
          ),
          AdminButton(
            ac: ac,
            label: ac.t('admin.common.actions.confirm'),
            identifier: '${widget.identifier}-confirm',
            variant: AdminButtonVariant.danger,
            isLoading: widget.isLoading,
            onPressed: () {
              setState(() => _confirming = false);
              widget.onConfirm();
            },
          ),
        ],
      ),
    );
  }
}

/// Picks an identity type, then an identity of that type, and adds it.
class AdminIdentityPicker<T> extends StatefulWidget {
  final AdminContext ac;
  final String block;
  final String addLabel;
  final List<(T, String)> types;
  final Map<T, List<IdentityCandidate>> candidates;
  final Set<String> excludedIds;
  final bool isSubmitting;
  final void Function(T type, String id) onAdd;
  final String Function(T type) typeValue;

  const AdminIdentityPicker({
    super.key,
    required this.ac,
    required this.block,
    required this.addLabel,
    required this.types,
    required this.candidates,
    required this.onAdd,
    required this.typeValue,
    this.excludedIds = const {},
    this.isSubmitting = false,
  });

  @override
  State<AdminIdentityPicker<T>> createState() => _AdminIdentityPickerState<T>();
}

class _AdminIdentityPickerState<T> extends State<AdminIdentityPicker<T>> {
  T? _type;
  String? _identityId;

  @override
  Widget build(BuildContext context) {
    final ac = widget.ac;
    if (widget.types.isEmpty) return const SizedBox.shrink();
    final type = _type ?? widget.types.first.$1;
    final options = (widget.candidates[type] ?? const <IdentityCandidate>[])
        .where((candidate) => !widget.excludedIds.contains(candidate.id))
        .map((candidate) => AdminSelectOption(value: candidate.id, label: candidate.label))
        .toList();
    final identityId = options.any((option) => option.value == _identityId) ? _identityId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminDropdown(
          ac: ac,
          label: ac.t('admin.common.fields.identity_type'),
          identifier: 'thunderid-field-${widget.block}-identityType',
          value: widget.typeValue(type),
          options: [
            for (final (value, label) in widget.types)
              AdminSelectOption(value: widget.typeValue(value), label: label),
          ],
          onChanged: (next) => setState(() {
            _type = widget.types.firstWhere((entry) => widget.typeValue(entry.$1) == next).$1;
            _identityId = null;
          }),
        ),
        AdminDropdown(
          ac: ac,
          label: ac.t('admin.common.fields.identity'),
          identifier: 'thunderid-field-${widget.block}-identity',
          value: identityId,
          options: options,
          placeholder: ac.t('admin.common.fields.identity_placeholder'),
          emptyText: ac.t('admin.common.fields.identity_empty'),
          onChanged: (next) => setState(() => _identityId = next),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AdminButton(
            ac: ac,
            label: widget.addLabel,
            identifier: 'thunderid-action-${widget.block}-add',
            isLoading: widget.isSubmitting,
            onPressed: identityId == null
                ? null
                : () {
                    widget.onAdd(type, identityId);
                    setState(() => _identityId = null);
                  },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The trailing "Remove" control of a membership row.
class AdminRemoveButton extends StatelessWidget {
  final AdminContext ac;
  final String identifier;
  final String semanticLabel;
  final VoidCallback? onPressed;

  const AdminRemoveButton({
    super.key,
    required this.ac,
    required this.identifier,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => AdminButton(
        ac: ac,
        label: ac.t('admin.common.actions.remove'),
        identifier: identifier,
        semanticLabel: semanticLabel,
        variant: AdminButtonVariant.dangerText,
        onPressed: onPressed,
      );
}
