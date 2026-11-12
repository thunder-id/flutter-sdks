// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import '../management/flow_variables.dart';
import '../management/management_transport.dart';
import '../models/management/connection.dart';
import '../models/management/flow_definition.dart';
import '../models/management/flow_variable.dart';
import '../models/management/management_page.dart';
import '../models/management/sharing_policy.dart';
import 'management_resources.dart';
import 'resource_notifiers.dart';

/// Loads the variables a flow declares for an organization unit, the values the unit has set and
/// what it may do with each, and saves the unit's values: the data behind `FlowVariablesForm`, for
/// building the form with any UI. The counterpart of the React SDK's `useFlowVariables`.
///
/// Loads on creation and notifies listeners on every change. The connections a connection
/// variable can take are loaded only when the flow declares such a variable. Dispose it when done.
class FlowVariablesController extends ChangeNotifier {
  final ManagementResources _resources;
  final String flowId;
  final String ouId;
  final ManagementFetcher? _fetcher;
  late final ResourceQuery<FlowDefinition> _flow;
  late final ResourceQuery<FlowVariables> _values;
  late final ResourceQuery<ResolvedOverlay> _overlay;
  late final ResourceMutation<UpdateFlowVariablesVariables, FlowVariables> _save;
  ResourceQuery<ManagementPage<ConnectionInstance>>? _connections;
  List<FlowVariableDefinition> _definitions = const [];
  bool _disposed = false;

  /// [onSaved] is called with the unit's values after a save.
  FlowVariablesController(
    this._resources, {
    required this.flowId,
    required this.ouId,
    ValueChanged<FlowVariableValues>? onSaved,
    ManagementFetcher? fetcher,
  }) : _fetcher = fetcher {
    _flow = _resources.flowVariableDefinitionsQuery(flowId, ouId, fetcher: fetcher)..addListener(_flowChanged);
    _values = _resources.flowVariableValuesQuery(flowId, ouId, fetcher: fetcher)..addListener(_changed);
    _overlay = _resources.flowOverlayRulesQuery(flowId, ouId, fetcher: fetcher)..addListener(_changed);
    _save = _resources.updateFlowVariablesMutation(
      onSuccess: (data, _) => onSaved?.call(data.values),
      fetcher: fetcher,
    )..addListener(_changed);
  }

  /// The flow as the organization unit sees it.
  FlowDefinition? get flow => _flow.data;

  /// The variables the flow declares for the organization unit.
  List<FlowVariableDefinition> get definitions => _definitions;

  /// The values the organization unit has set. A variable it has not set is absent, and its
  /// default applies.
  FlowVariableValues get overrides => _values.data?.values ?? const {};

  /// What the organization unit may do with each variable.
  ResolvedOverlay? get overlay => _overlay.data;

  /// The connections a connection variable can take. Empty until loaded, and when no variable
  /// needs them.
  List<ConnectionInstance> get connections => _connections?.data?.items ?? const [];

  /// Why the variables could not be loaded.
  Object? get error => _flow.error ?? _values.error ?? _overlay.error ?? _connections?.error;

  /// Whether the variables, the unit's values and its rules have all arrived. A form built before
  /// then would be reset when the values land.
  bool get isLoaded => _flow.data != null && _values.data != null && _overlay.data != null;

  bool get isLoading =>
      _flow.isLoading || _values.isLoading || _overlay.isLoading || (_connections?.isLoading ?? false);

  bool get isSaving => _save.isLoading;

  /// Why the last save failed.
  Object? get saveError => _save.error;

  /// Replaces the unit's values with [values]: a variable left out returns to its default.
  /// Resolves with the saved values, or `null` when the save failed (see [saveError]).
  Future<FlowVariables?> save(FlowVariableValues values) =>
      _save.mutate((flowId: flowId, ouId: ouId, values: values));

  void _flowChanged() {
    _definitions = getFlowVariableDefinitions(_flow.data);
    final needsConnections =
        _definitions.any((definition) => definition.type == FlowVariableTypes.connectionSelect);
    if (needsConnections && _connections == null) {
      _connections = _resources.flowVariableConnectionsQuery(ouId, fetcher: _fetcher)..addListener(_changed);
    }
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final notifier in <ChangeNotifier?>[_flow, _values, _overlay, _save, _connections]) {
      notifier
        ?..removeListener(_changed)
        ..removeListener(_flowChanged)
        ..dispose();
    }
    super.dispose();
  }
}
