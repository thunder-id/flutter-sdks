// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/management/connection.dart';
import '../models/management/flow_definition.dart';
import '../models/management/flow_variable.dart';
import '../models/management/sharing_policy.dart';

// Helpers that read and check a flow's variables, for a form that lets an organization unit set
// its own values. None of them makes a request.

const String _variablesNodeType = 'VARIABLES';

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _phonePattern = RegExp(r'^\+?[0-9\s\-()]{6,20}$');
final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// [value] as the string a select stores and a rule carries: `2`, not `2.0`, for a whole number.
String flowVariableValueToString(Object? value) {
  if (value == null) return '';
  if (value is double && value == value.truncateToDouble() && value.isFinite) return value.toInt().toString();
  return value.toString();
}

/// Reads the variables [flow] declares. A flow shared with an organization unit lists them in
/// [FlowDefinition.variables]; a flow the unit owns declares them on its `VARIABLES` node.
/// Returns an empty list without a flow, or when it declares none.
List<FlowVariableDefinition> getFlowVariableDefinitions(FlowDefinition? flow) {
  if (flow == null) return const [];
  final variables = flow.variables;
  if (variables != null) return variables;
  for (final node in flow.nodes) {
    if (node['type'] != _variablesNodeType) continue;
    final inputs = node['inputs'];
    if (inputs is! List) return const [];
    return inputs.map(FlowVariableDefinition.tryParse).whereType<FlowVariableDefinition>().toList(growable: false);
  }
  return const [];
}

String _normalize(String value) => value.toLowerCase().replaceAll('_', '-');

/// Lists what a select variable can take. A [FlowVariableTypes.select] takes the values it
/// declares; a [FlowVariableTypes.connectionSelect] takes the [connections] of its `category` and
/// `connectionTypes`, compared regardless of case and of `_` against `-`. Any other type has none.
///
/// [allowedValues] and [excludedValues] narrow the choices as a sharing policy decides: only the
/// allowed ones (when given), without the excluded ones.
List<FlowVariableOption> getFlowVariableOptions(
  FlowVariableDefinition definition, {
  List<ConnectionInstance> connections = const [],
  List<String>? allowedValues,
  List<String>? excludedValues,
}) {
  bool permitted(FlowVariableOption option) =>
      (allowedValues == null || allowedValues.contains(option.value)) &&
      !(excludedValues ?? const []).contains(option.value);

  if (definition.type == FlowVariableTypes.select) {
    return definition.options
        .map((option) {
          final value = flowVariableValueToString(option);
          return FlowVariableOption(label: value, value: value);
        })
        .where(permitted)
        .toList(growable: false);
  }
  if (definition.type != FlowVariableTypes.connectionSelect) return const [];

  final category = definition.category == null ? null : _normalize(definition.category!);
  final vendors = definition.connectionTypes.map(_normalize).toList(growable: false);
  return connections
      .where(
        (connection) =>
            (category == null || connection.categories.map(_normalize).contains(category)) &&
            (vendors.isEmpty || (connection.type != null && vendors.contains(_normalize(connection.type!.value)))),
      )
      .map((connection) => FlowVariableOption(label: connection.name, value: connection.id))
      .where(permitted)
      .toList(growable: false);
}

/// Reads a value a rule carries, always written as a string, in [definition]'s own type.
Object _toVariableValue(FlowVariableDefinition definition, String raw) {
  switch (definition.type) {
    case FlowVariableTypes.booleanInput:
      return raw == 'true';
    case FlowVariableTypes.numberInput:
      return num.tryParse(raw) ?? raw;
    case FlowVariableTypes.select:
      for (final option in definition.options) {
        if (flowVariableValueToString(option) == raw) return option;
      }
      return raw;
    default:
      return raw;
  }
}

/// Works out what an organization unit may do with [definition], from the [overlay]
/// `getFlowOverlayRules` returns for it. A unit that owns the flow may set every variable. For a
/// flow shared with it, a variable no policy names cannot be edited and keeps the owner's default,
/// or the value the policy pins it to. Without an overlay, such as in a preview, every variable is
/// editable.
ResolvedFlowVariableRule resolveFlowVariableRule(FlowVariableDefinition definition, [ResolvedOverlay? overlay]) {
  if (overlay == null) return ResolvedFlowVariableRule(editable: true, defaultValue: definition.defaultValue);

  final rule = overlay.rules['variables.${definition.identifier}'];
  final pinnedValues = rule?.value;
  final pinned = pinnedValues == null || pinnedValues.isEmpty ? null : pinnedValues.first;
  final owned = overlay.isOwnedByOU ?? false;
  return ResolvedFlowVariableRule(
    editable: owned || rule?.editable == true,
    defaultValue: !owned && pinned != null ? _toVariableValue(definition, pinned) : definition.defaultValue,
    allowedValues: owned ? null : rule?.allowedValues,
    excludedValues: owned ? null : rule?.excludedValues,
  );
}

bool _matches(String pattern, String value) {
  try {
    return RegExp(pattern).hasMatch(value);
  } on FormatException {
    // A pattern Dart cannot compile is the server's to judge.
    return true;
  }
}

/// Checks [value] against [definition]'s type, options and rules, so a form can report what is
/// wrong before the server does. The server validates again on save. Returns `null` when the value
/// is valid.
///
/// Every type but [FlowVariableTypes.booleanInput] requires a value.
FlowVariableValidationError? validateFlowVariableValue(FlowVariableDefinition definition, Object? value) {
  const invalid = FlowVariableValidationError(FlowVariableValidationErrorCode.invalid);
  if (definition.type == FlowVariableTypes.booleanInput) return value == null || value is bool ? null : invalid;
  if (value == null || value == '') {
    return const FlowVariableValidationError(FlowVariableValidationErrorCode.required);
  }

  switch (definition.type) {
    case FlowVariableTypes.numberInput:
      final number = value is num ? value : num.tryParse(value.toString());
      if (number == null || number.isNaN) return invalid;
      if (definition.min != null && number < definition.min!) {
        return const FlowVariableValidationError(FlowVariableValidationErrorCode.min);
      }
      if (definition.max != null && number > definition.max!) {
        return const FlowVariableValidationError(FlowVariableValidationErrorCode.max);
      }
      return null;
    case FlowVariableTypes.select:
      return definition.options.any((option) => flowVariableValueToString(option) == flowVariableValueToString(value))
          ? null
          : const FlowVariableValidationError(FlowVariableValidationErrorCode.notOption);
    case FlowVariableTypes.emailInput:
      return _emailPattern.hasMatch(value.toString()) ? null : invalid;
    case FlowVariableTypes.phoneInput:
      return _phonePattern.hasMatch(value.toString()) ? null : invalid;
    case FlowVariableTypes.dateInput:
      return _datePattern.hasMatch(value.toString()) ? null : invalid;
    case FlowVariableTypes.connectionSelect:
      return value is String ? null : invalid;
    default:
      final text = value.toString();
      for (final rule in definition.validation) {
        final bound = rule.value is num ? rule.value as num : num.tryParse(rule.value.toString());
        if (rule.type == 'minLength' && bound != null && text.length < bound) {
          return FlowVariableValidationError(FlowVariableValidationErrorCode.minLength, rule.message);
        }
        if (rule.type == 'maxLength' && bound != null && text.length > bound) {
          return FlowVariableValidationError(FlowVariableValidationErrorCode.maxLength, rule.message);
        }
        if (rule.type == 'regex' && !_matches(rule.value.toString(), text)) {
          return FlowVariableValidationError(FlowVariableValidationErrorCode.pattern, rule.message);
        }
      }
      return null;
  }
}
