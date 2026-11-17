// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// The input a flow variable is edited with, the values of [FlowVariableDefinition.type].
abstract final class FlowVariableTypes {
  static const String textInput = 'TEXT_INPUT';
  static const String emailInput = 'EMAIL_INPUT';
  static const String phoneInput = 'PHONE_INPUT';
  static const String numberInput = 'NUMBER_INPUT';
  static const String dateInput = 'DATE_INPUT';
  static const String booleanInput = 'BOOLEAN_INPUT';
  static const String select = 'SELECT';
  static const String connectionSelect = 'CONNECTION_SELECT';
}

/// The values a flow variable holds: a `String`, a `num` or a `bool`, keyed by the variable's
/// identifier.
typedef FlowVariableValues = Map<String, Object>;

/// A value read from a payload as a variable value: a string, number or boolean, or `null`.
Object? _readValue(Object? value) => value is String || value is num || value is bool ? value : null;

/// A rule a text value has to meet.
class FlowVariableValidationRule {
  /// `regex`, `minLength` or `maxLength`.
  final String type;

  /// The pattern, or the length bound.
  final Object value;

  /// The message shown when the rule fails. A translation key or a literal string.
  final String? message;

  const FlowVariableValidationRule({required this.type, required this.value, this.message});

  factory FlowVariableValidationRule.fromJson(Map<String, dynamic> json) => FlowVariableValidationRule(
        type: readString(json, 'type'),
        value: _readValue(json['value']) ?? '',
        message: readOptionalString(json, 'message'),
      );
}

/// A variable a flow declares, which an organization unit the flow is shared with can set its own
/// value for. A `{{var(identifier)}}` placeholder in the flow reads it.
class FlowVariableDefinition {
  final String identifier;

  /// See [FlowVariableTypes].
  final String type;
  final String? label;
  final String? description;

  /// The value the variable has until another is set.
  final Object? defaultValue;

  /// For a [FlowVariableTypes.select]: the values it can take.
  final List<Object> options;

  /// For a [FlowVariableTypes.numberInput]: the lowest value.
  final num? min;

  /// For a [FlowVariableTypes.numberInput]: the highest value.
  final num? max;

  /// For a [FlowVariableTypes.connectionSelect]: the kind of connection it takes, such as
  /// `IDENTITY_PROVIDER`.
  final String? category;

  /// For a [FlowVariableTypes.connectionSelect]: limits it to these vendors, such as `google`.
  final List<String> connectionTypes;
  final List<FlowVariableValidationRule> validation;

  const FlowVariableDefinition({
    required this.identifier,
    required this.type,
    this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.min,
    this.max,
    this.category,
    this.connectionTypes = const [],
    this.validation = const [],
  });

  /// Reads a definition, or `null` when [json] has no identifier or type.
  static FlowVariableDefinition? tryParse(Object? json) {
    final map = readMap(json);
    final identifier = readOptionalString(map, 'identifier');
    final type = readOptionalString(map, 'type');
    if (identifier == null || type == null) return null;
    return FlowVariableDefinition(
      identifier: identifier,
      type: type,
      label: readOptionalString(map, 'label'),
      description: readOptionalString(map, 'description'),
      defaultValue: _readValue(map['defaultValue']),
      options: readList(map, 'options').map(_readValue).whereType<Object>().toList(growable: false),
      min: map['min'] is num ? map['min'] as num : null,
      max: map['max'] is num ? map['max'] as num : null,
      category: readOptionalString(map, 'category'),
      connectionTypes: readStringList(map, 'connectionTypes'),
      validation: readList(map, 'validation')
          .map((rule) => FlowVariableValidationRule.fromJson(readMap(rule)))
          .toList(growable: false),
    );
  }
}

/// The values an organization unit has set for a flow's variables. A variable it has not set is
/// absent from [values], and the flow's default applies to it.
class FlowVariables {
  final FlowVariableValues values;

  const FlowVariables({this.values = const {}});

  factory FlowVariables.fromJson(Map<String, dynamic> json) => FlowVariables(
        values: {
          for (final entry in readMap(json['values']).entries)
            if (_readValue(entry.value) != null) entry.key: _readValue(entry.value)!,
        },
      );
}

/// Why a value does not fit its variable. Its [key] is the suffix of the
/// `admin.flowVariables.errors.<key>` translation.
enum FlowVariableValidationErrorCode {
  invalid('invalid'),
  max('max'),
  maxLength('max_length'),
  min('min'),
  minLength('min_length'),
  notOption('not_option'),
  pattern('pattern'),
  required('required');

  final String key;

  const FlowVariableValidationErrorCode(this.key);
}

/// Why a value does not fit its variable. [message] is set when the variable's own rule supplies
/// the text.
class FlowVariableValidationError {
  final FlowVariableValidationErrorCode code;
  final String? message;

  const FlowVariableValidationError(this.code, [this.message]);

  @override
  bool operator ==(Object other) =>
      other is FlowVariableValidationError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'FlowVariableValidationError(${code.key})';
}

/// A choice of a [FlowVariableTypes.select] or [FlowVariableTypes.connectionSelect] variable.
class FlowVariableOption {
  final String label;

  /// The value to store, as a string.
  final String value;

  const FlowVariableOption({required this.label, required this.value});

  @override
  bool operator ==(Object other) => other is FlowVariableOption && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// What an organization unit may do with one variable, after the sharing policies that reach it
/// are applied.
class ResolvedFlowVariableRule {
  /// Whether the unit may set its own value.
  final bool editable;

  /// The value the variable has until the unit sets its own, or the value it is pinned to when it
  /// cannot set one.
  final Object? defaultValue;

  /// The values the unit may choose from. `null` means anything the variable accepts.
  final List<String>? allowedValues;

  /// Values taken out of what the unit may choose.
  final List<String>? excludedValues;

  const ResolvedFlowVariableRule({
    required this.editable,
    this.defaultValue,
    this.allowedValues,
    this.excludedValues,
  });
}
