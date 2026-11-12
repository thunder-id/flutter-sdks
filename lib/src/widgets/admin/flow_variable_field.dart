// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../management/flow_variables.dart';
import '../../models/management/flow_variable.dart';
import '../../models/preferences.dart';
import 'internal/admin_context.dart';

/// One flow variable as an organization unit's admin sees it, in a card: its label and
/// description, whether it is customized or follows the default, the input its type calls for,
/// and what the default is. A variable the unit may not set is shown as set by its owner.
///
/// The input exposes `thunderid-field-flow-variables-<identifier>` and the card
/// `thunderid-admin-flow-variables-field-<identifier>` to the accessibility tree.
class FlowVariableField extends StatelessWidget {
  final FlowVariableDefinition definition;
  final Object? value;
  final ValueChanged<Object> onChanged;

  /// The value the variable has until the unit sets its own, which a sharing policy may have set.
  final Object? defaultValue;

  /// Whether the unit may set its own value. A variable it may not set is shown as set by
  /// [ownerName].
  final bool editable;
  final bool disabled;

  /// A translated message to show under the input.
  final String? error;

  /// Extra content under the input, such as where the choices come from.
  final Widget? hint;

  /// The choices of a select variable, as `getFlowVariableOptions` returns them.
  final List<FlowVariableOption> options;

  /// Who set the variable, shown while it is not editable.
  final String? ownerName;
  final ThunderIDPreferences? preferences;

  const FlowVariableField({
    super.key,
    required this.definition,
    required this.value,
    required this.onChanged,
    this.defaultValue,
    this.editable = true,
    this.disabled = false,
    this.error,
    this.hint,
    this.options = const [],
    this.ownerName,
    this.preferences,
  });

  String get _identifier => 'thunderid-field-flow-variables-${definition.identifier}';

  bool get _isSelect =>
      definition.type == FlowVariableTypes.select || definition.type == FlowVariableTypes.connectionSelect;

  String _display(AdminContext ac, Object? shown) {
    if (shown == null) return '';
    if (shown is bool) return ac.t(shown ? 'admin.flowVariables.on' : 'admin.flowVariables.off');
    final text = flowVariableValueToString(shown);
    if (!_isSelect) return text;
    for (final option in options) {
      if (option.value == text) return option.label;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, preferences);
    final colors = ac.colors;
    final label = definition.label ?? definition.identifier;
    final isDefault = value == defaultValue;
    final secondary = TextStyle(color: colors.textSecondary, fontSize: 12);
    final block = 'thunderid-admin-flow-variables-field-${definition.identifier}';

    return Semantics(
      identifier: block,
      container: true,
      child: Container(
        key: Key(block),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: editable ? colors.background : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: colors.text)),
                      if (definition.description?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(definition.description!, style: TextStyle(color: colors.textSecondary)),
                        ),
                    ],
                  ),
                ),
                if (editable && !isDefault)
                  Container(
                    key: Key('$block-customized'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.primary),
                    ),
                    child: Text(
                      ac.t('admin.flowVariables.status.customized'),
                      style: TextStyle(color: colors.primary, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (editable) ...[
              _control(ac, label),
              if (hint != null) Padding(padding: const EdgeInsets.only(top: 6), child: hint),
              if (!isDefault && defaultValue != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ac.t('admin.flowVariables.default_hint', {'default': _display(ac, defaultValue)}),
                    style: secondary,
                  ),
                ),
            ] else
              Row(
                children: [
                  ExcludeSemantics(child: Icon(Icons.lock_outline, size: 16, color: colors.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${ac.t('admin.flowVariables.locked', {
                            'owner': ownerName ?? ac.t('admin.flowVariables.owner_fallback'),
                          })} · ${_display(ac, value)}',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                  if (definition.type == FlowVariableTypes.booleanInput) _control(ac, label),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _control(AdminContext ac, String label) {
    final colors = ac.colors;
    final errorText = error;
    Widget withError(Widget control) => errorText == null
        ? control
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              control,
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(errorText, style: TextStyle(color: colors.error, fontSize: 12)),
                ),
              ),
            ],
          );

    switch (definition.type) {
      case FlowVariableTypes.booleanInput:
        return Semantics(
          identifier: _identifier,
          label: label,
          child: SizedBox(
            height: 44,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: Switch(
                key: Key(_identifier),
                value: value == true,
                activeTrackColor: colors.primary,
                onChanged: disabled || !editable ? null : (checked) => onChanged(checked),
              ),
            ),
          ),
        );
      case FlowVariableTypes.select:
      case FlowVariableTypes.connectionSelect:
        return withError(_select(ac, label));
      default:
        return _FlowVariableTextInput(
          ac: ac,
          identifier: _identifier,
          label: label,
          definition: definition,
          value: value,
          enabled: !disabled,
          error: errorText,
          placeholder: defaultValue == null || defaultValue == ''
              ? ac.t('admin.flowVariables.enter_value')
              : _display(ac, defaultValue),
          onChanged: onChanged,
        );
    }
  }

  Widget _select(AdminContext ac, String label) {
    final colors = ac.colors;
    final current = value == null || value == defaultValue ? '' : flowVariableValueToString(value);
    final selected = options.any((option) => option.value == current) ? current : '';
    final placeholder = defaultValue == null || defaultValue == ''
        ? ac.t('admin.flowVariables.select_placeholder')
        : ac.t('admin.flowVariables.use_default', {'default': _display(ac, defaultValue)});

    void select(String? chosen) {
      if (chosen == null) return;
      if (chosen.isEmpty) {
        onChanged(defaultValue ?? '');
        return;
      }
      for (final option in definition.options) {
        if (flowVariableValueToString(option) == chosen) {
          onChanged(option);
          return;
        }
      }
      onChanged(chosen);
    }

    return Semantics(
      identifier: _identifier,
      label: label,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: error == null ? colors.border : colors.error),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: Key(_identifier),
            isExpanded: true,
            value: options.isEmpty ? null : selected,
            dropdownColor: colors.background,
            style: TextStyle(color: colors.text, fontSize: 15),
            hint: Text(
              options.isEmpty ? ac.t('admin.flowVariables.no_options') : placeholder,
              style: TextStyle(color: colors.textSecondary),
            ),
            items: options.isEmpty
                ? const []
                : [
                    DropdownMenuItem<String>(
                      key: Key('$_identifier-option-default'),
                      value: '',
                      child: Text(placeholder),
                    ),
                    for (final option in options)
                      DropdownMenuItem<String>(
                        key: Key('$_identifier-option-${option.value}'),
                        value: option.value,
                        child: Text(option.label),
                      ),
                  ],
            onChanged: disabled || options.isEmpty ? null : select,
          ),
        ),
      ),
    );
  }
}

/// A text, email, phone, number or date input that keeps what is typed while the value it reports
/// matches, and shows the new value when it is replaced from outside, such as on a reset.
class _FlowVariableTextInput extends StatefulWidget {
  final AdminContext ac;
  final String identifier;
  final String label;
  final FlowVariableDefinition definition;
  final Object? value;
  final bool enabled;
  final String? error;
  final String placeholder;
  final ValueChanged<Object> onChanged;

  const _FlowVariableTextInput({
    required this.ac,
    required this.identifier,
    required this.label,
    required this.definition,
    required this.value,
    required this.enabled,
    required this.error,
    required this.placeholder,
    required this.onChanged,
  });

  @override
  State<_FlowVariableTextInput> createState() => _FlowVariableTextInputState();
}

class _FlowVariableTextInputState extends State<_FlowVariableTextInput> {
  late final TextEditingController _controller = TextEditingController(text: _text(widget.value));

  bool get _isNumber => widget.definition.type == FlowVariableTypes.numberInput;

  String _text(Object? value) => value == null ? '' : flowVariableValueToString(value);

  /// What [raw] reports: a number for a number input when it parses, else the text.
  Object _parse(String raw) => _isNumber && raw.isNotEmpty ? (num.tryParse(raw) ?? raw) : raw;

  @override
  void didUpdateWidget(_FlowVariableTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value ?? '';
    if (_parse(_controller.text) != value) _controller.text = _text(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextInputType get _keyboard => switch (widget.definition.type) {
        FlowVariableTypes.emailInput => TextInputType.emailAddress,
        FlowVariableTypes.phoneInput => TextInputType.phone,
        FlowVariableTypes.numberInput => const TextInputType.numberWithOptions(signed: true, decimal: true),
        FlowVariableTypes.dateInput => TextInputType.datetime,
        _ => TextInputType.text,
      };

  @override
  Widget build(BuildContext context) {
    final colors = widget.ac.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color),
        );
    return Semantics(
      identifier: widget.identifier,
      textField: true,
      label: widget.label,
      child: TextField(
        key: Key(widget.identifier),
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: _keyboard,
        autocorrect: false,
        onChanged: (raw) => widget.onChanged(_parse(raw)),
        style: TextStyle(color: colors.text, fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle: TextStyle(color: colors.textSecondary),
          errorText: widget.error,
          errorStyle: TextStyle(color: colors.error),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: border(colors.border),
          enabledBorder: border(colors.border),
          focusedBorder: border(colors.primary),
          errorBorder: border(colors.error),
          focusedErrorBorder: border(colors.error),
        ),
      ),
    );
  }
}
