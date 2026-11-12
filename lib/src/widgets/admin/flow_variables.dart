// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../management/flow_variables.dart';
import '../../management/management_display.dart';
import '../../models/management/connection.dart';
import '../../models/management/flow_variable.dart';
import '../../models/management/sharing_policy.dart';
import '../../models/preferences.dart';
import '../../state/flow_variables_controller.dart';
import '../../state/management_resources.dart';
import 'admin_render_state.dart';
import 'flow_variable_field.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';

/// Presentational form for the variables a flow declares, each in a [FlowVariableField] card. It
/// is what an organization unit's admin sees when setting their own values for a flow shared with
/// the unit. Holds no data of its own: pass the variables and handle the submission. Use
/// [FlowVariablesForm] to have it load and save them.
class BaseFlowVariables extends StatefulWidget {
  /// The variables, as the flow declares them.
  final List<FlowVariableDefinition> variables;

  /// The connections a connection variable can take.
  final List<ConnectionInstance> connections;

  /// The values the form starts with, over each variable's default. A variable left out starts at
  /// its default.
  final FlowVariableValues? initialValues;

  /// What the unit may do with each variable, as `getFlowOverlayRules` returns it. Without it
  /// every variable is editable, which suits a preview.
  final ResolvedOverlay? overlay;

  /// Called when the form is submitted and valid, with every value and the overrides: the values
  /// of the variables the unit may set that differ from their default. Without it the form has no
  /// save button, which suits a preview.
  final void Function(FlowVariableValues values, FlowVariableValues overrides)? onSubmit;

  /// Called with every value after one changes.
  final ValueChanged<FlowVariableValues>? onChange;
  final VoidCallback? onCancel;

  /// Called when the user asks to create a connection, from the hint under a connection variable.
  /// Without it, the hint does not offer one.
  final VoidCallback? onCreateConnection;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;

  /// Shows the variables without letting them be changed.
  final bool readOnly;

  /// The name of the organization unit the values are set for, used in the notice and the
  /// connection hint.
  final String? ouName;

  /// The name of whoever owns the flow, shown on a variable the unit may not set.
  final String? ownerName;

  /// Shows a notice that the settings apply to the organization unit only.
  final bool showScopeNotice;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the variables, their values and setters,
  /// the rule and choices of each, and the submit action.
  final AdminWidgetBuilder<FlowVariablesFormState>? builder;

  const BaseFlowVariables({
    super.key,
    required this.variables,
    this.connections = const [],
    this.initialValues,
    this.overlay,
    this.onSubmit,
    this.onChange,
    this.onCancel,
    this.onCreateConnection,
    this.isSubmitting = false,
    this.error,
    this.readOnly = false,
    this.ouName,
    this.ownerName,
    this.showScopeNotice = false,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<BaseFlowVariables> createState() => _BaseFlowVariablesState();
}

class _BaseFlowVariablesState extends State<BaseFlowVariables> {
  late String _signature;
  late FlowVariableValues _values;
  Set<String> _touched = {};
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _signature = _signatureOf(widget);
    _values = _startingValues();
  }

  /// What the starting values depend on, so a new list with the same content keeps what was typed.
  static String _signatureOf(BaseFlowVariables widget) => jsonEncode(
        [
          [
            for (final v in widget.variables)
              [v.identifier, v.type, v.defaultValue, v.options],
          ],
          widget.overlay == null
              ? null
              : [
                  widget.overlay!.isOwnedByOU,
                  {
                    for (final entry in widget.overlay!.rules.entries)
                      entry.key: [
                        entry.value.editable,
                        entry.value.value,
                        entry.value.allowedValues,
                        entry.value.excludedValues,
                      ],
                  },
                ],
          widget.initialValues,
        ],
        toEncodable: (value) => value.toString(),
      );

  ResolvedFlowVariableRule _rule(FlowVariableDefinition definition) =>
      resolveFlowVariableRule(definition, widget.overlay);

  FlowVariableValues _startingValues() {
    final values = <String, Object>{};
    for (final definition in widget.variables) {
      final rule = _rule(definition);
      final Object? initial;
      if (rule.editable) {
        initial = widget.initialValues?[definition.identifier];
      } else {
        initial = null;
      }
      final chosen = initial ?? rule.defaultValue;
      if (chosen != null) values[definition.identifier] = chosen;
    }
    return values;
  }

  @override
  void didUpdateWidget(BaseFlowVariables oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signatureOf(widget);
    if (signature == _signature) return;
    // Only a change to what the form starts from replaces what was typed.
    _signature = signature;
    _values = _startingValues();
    _touched = {};
    _submitted = false;
  }

  List<FlowVariableOption> _options(FlowVariableDefinition definition) {
    final rule = _rule(definition);
    // A variable the unit cannot set shows its pinned value, which a restriction might hide.
    return getFlowVariableOptions(
      definition,
      connections: widget.connections,
      allowedValues: rule.editable ? rule.allowedValues : null,
      excludedValues: rule.editable ? rule.excludedValues : null,
    );
  }

  void _change(String identifier, Object value) {
    setState(() {
      _values = {..._values, identifier: value};
      _touched = {..._touched, identifier};
    });
    widget.onChange?.call(_values);
  }

  void _resetToDefaults() {
    setState(() {
      _values = {};
      for (final definition in widget.variables) {
        final defaultValue = _rule(definition).defaultValue;
        if (defaultValue != null) _values[definition.identifier] = defaultValue;
      }
      _touched = {};
      _submitted = false;
    });
    widget.onChange?.call(_values);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final errors = <String, String>{};
    var isValid = true;
    for (final definition in widget.variables) {
      if (!_rule(definition).editable) continue;
      final problem = validateFlowVariableValue(definition, _values[definition.identifier]);
      if (problem == null) continue;
      isValid = false;
      if (_submitted || _touched.contains(definition.identifier)) {
        errors[definition.identifier] = problem.message ?? ac.t('admin.flowVariables.errors.${problem.code.key}');
      }
    }

    void submit() {
      setState(() => _submitted = true);
      if (!isValid) return;
      final overrides = <String, Object>{};
      for (final definition in widget.variables) {
        final rule = _rule(definition);
        final value = _values[definition.identifier];
        if (rule.editable && value != null && value != rule.defaultValue) overrides[definition.identifier] = value;
      }
      widget.onSubmit?.call(_values, overrides);
    }

    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        FlowVariablesFormState(
          variables: widget.variables,
          values: _values,
          errors: errors,
          getRule: _rule,
          getOptions: _options,
          onChanged: _change,
          resetToDefaults: _resetToDefaults,
          isValid: isValid,
          isSubmitting: widget.isSubmitting,
          error: widget.error,
          submit: submit,
          onCancel: widget.onCancel,
        ),
      );
    }

    final colors = ac.colors;
    final ou = widget.ouName ?? ac.t('admin.flowVariables.ou_fallback');
    final hintStyle = TextStyle(color: colors.textSecondary, fontSize: 12);
    return AdminSection(
      ac: ac,
      block: 'flow-variables',
      title: widget.title,
      description: widget.description,
      children: [
        if (widget.showScopeNotice)
          Semantics(
            identifier: 'thunderid-admin-flow-variables-notice',
            container: true,
            child: Container(
              key: const Key('thunderid-admin-flow-variables-notice'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ac.t('admin.flowVariables.notice_title', {'ou': ou}),
                    style: TextStyle(fontWeight: FontWeight.w600, color: colors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ac.t('admin.flowVariables.notice_body', {'ou': ou}),
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'flow-variables'),
        if (widget.variables.isEmpty) AdminMuted(ac: ac, text: ac.t('admin.flowVariables.empty')),
        for (final (index, definition) in widget.variables.indexed)
          Builder(
            // An identifier can repeat while a flow's variables are edited, so it is not the key alone.
            key: ValueKey('$index-${definition.identifier}'),
            builder: (context) {
              final rule = _rule(definition);
              return FlowVariableField(
                definition: definition,
                value: _values[definition.identifier],
                defaultValue: rule.defaultValue,
                editable: rule.editable,
                disabled: widget.readOnly || widget.isSubmitting,
                error: errors[definition.identifier],
                options: _options(definition),
                ownerName: widget.ownerName,
                preferences: widget.preferences,
                onChanged: (value) => _change(definition.identifier, value),
                hint: definition.type == FlowVariableTypes.connectionSelect && rule.editable
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(ac.t('admin.flowVariables.connections_hint', {'ou': ou}), style: hintStyle),
                          if (widget.onCreateConnection != null)
                            AdminButton(
                              ac: ac,
                              label: ac.t('admin.flowVariables.create_connection'),
                              identifier: 'thunderid-action-flow-variables-create-connection-${definition.identifier}',
                              variant: AdminButtonVariant.text,
                              onPressed: widget.onCreateConnection,
                            ),
                        ],
                      )
                    : null,
              );
            },
          ),
        if (widget.onSubmit != null && !widget.readOnly && widget.variables.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminButton(
                ac: ac,
                label: ac.t('admin.flowVariables.reset_defaults'),
                identifier: 'thunderid-action-flow-variables-reset',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : _resetToDefaults,
              ),
              if (widget.onCancel != null)
                AdminButton(
                  ac: ac,
                  label: ac.t('admin.common.actions.cancel'),
                  identifier: 'thunderid-action-flow-variables-cancel',
                  variant: AdminButtonVariant.text,
                  onPressed: widget.isSubmitting ? null : widget.onCancel,
                ),
              AdminButton(
                ac: ac,
                label: ac.t('admin.flowVariables.submit'),
                identifier: 'thunderid-action-flow-variables-submit',
                isLoading: widget.isSubmitting,
                onPressed: widget.isSubmitting ? null : submit,
              ),
            ],
          ),
      ],
    );
  }
}

/// Lets an organization unit's admin set their own values for the variables a flow declares. It
/// loads the variables the flow shares with the unit [ouId], the values the unit has set, and what
/// it may do with each, shows them as a form, and saves the values that differ from their
/// defaults. Build the same with any UI through [builder], or drive it yourself with a
/// [FlowVariablesController].
class FlowVariablesForm extends StatefulWidget {
  final String flowId;

  /// The organization unit the values belong to.
  final String ouId;

  /// Called with the unit's values after they are saved.
  final ValueChanged<FlowVariableValues>? onSaved;
  final VoidCallback? onCancel;

  /// See [BaseFlowVariables.onCreateConnection].
  final VoidCallback? onCreateConnection;

  /// See [BaseFlowVariables.readOnly].
  final bool readOnly;

  /// See [BaseFlowVariables.ouName].
  final String? ouName;

  /// See [BaseFlowVariables.ownerName].
  final String? ownerName;

  /// See [BaseFlowVariables.showScopeNotice].
  final bool showScopeNotice;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseFlowVariables.builder].
  final AdminWidgetBuilder<FlowVariablesFormState>? builder;

  const FlowVariablesForm({
    super.key,
    required this.flowId,
    required this.ouId,
    this.onSaved,
    this.onCancel,
    this.onCreateConnection,
    this.readOnly = false,
    this.ouName,
    this.ownerName,
    this.showScopeNotice = false,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<FlowVariablesForm> createState() => _ConnectedFlowVariablesFormState();
}

class _ConnectedFlowVariablesFormState extends AdminConnectedState<FlowVariablesForm> {
  FlowVariablesController? _controller;

  @override
  void bind(ManagementResources resources) {
    _controller = own(
      FlowVariablesController(
        resources,
        flowId: widget.flowId,
        ouId: widget.ouId,
        onSaved: (values) => widget.onSaved?.call(values),
      ),
    );
  }

  @override
  void didUpdateWidget(FlowVariablesForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flowId != widget.flowId || oldWidget.ouId != widget.ouId) rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final controller = _controller;
    if (!providerFailed && (controller == null || (!controller.isLoaded && controller.error == null))) {
      return AdminSection(ac: ac, block: 'flow-variables', children: [AdminLoading(ac: ac)]);
    }
    final loadError = controller?.error;
    final String? error;
    if (providerFailed) {
      error = ac.t('admin.flowVariables.load_error');
    } else if (loadError != null) {
      error = toManagementErrorMessage(ac.t, loadError, 'admin.flowVariables.load_error');
    } else {
      error = toManagementErrorMessage(ac.t, controller?.saveError, 'admin.flowVariables.error');
    }
    return BaseFlowVariables(
      variables: controller?.definitions ?? const [],
      connections: controller?.connections ?? const [],
      initialValues: controller?.overrides,
      overlay: controller?.overlay,
      isSubmitting: controller?.isSaving ?? false,
      error: error,
      onSubmit: controller == null ? null : (_, overrides) => unawaited(controller.save(overrides)),
      onCancel: widget.onCancel,
      onCreateConnection: widget.onCreateConnection,
      readOnly: widget.readOnly,
      ouName: widget.ouName,
      ownerName: widget.ownerName,
      showScopeNotice: widget.showScopeNotice,
      title: widget.title ?? ac.t('admin.flowVariables.title'),
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
