// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/default_strings.dart';
import '../../models/flow_models.dart';
import '../thunderid_provider.dart';
import 'flow/flow_form.dart';

/// How a device authorization ended.
enum DeviceGrantResult {
  /// The user approved the device, which now receives its tokens.
  approved,

  /// The flow refused the device, for example because the user declined.
  denied,

  /// The step's time ran out before the user finished.
  expired,

  /// The flow could not be started or continued.
  failed,
}

/// What [BaseDeviceGrant] and [DeviceGrant] hand their `builder`: the flow step the server
/// returned, the values entered so far, and the outcome once there is one.
class DeviceGrantState {
  /// The step the server returned, or `null` before the flow has started and after it has ended.
  final EmbeddedFlowResponse? step;

  /// The step's component tree (`data.meta.components`), when the server describes one.
  final List<Map<String, dynamic>> components;

  /// The step's inputs, such as `user_code`.
  final List<Map<String, dynamic>> inputs;

  /// The step's actions.
  final List<Map<String, dynamic>> actions;

  /// The values entered so far, keyed by input name.
  final Map<String, String> values;

  /// Sets one input's value.
  final void Function(String name, String value) onValueChanged;

  /// Submits the entered values with the given action, or with the step's only action when `null`.
  /// Does nothing while a submission is in flight.
  final void Function([String? actionId]) submit;
  final bool isLoading;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;

  /// The outcome, once the flow has ended.
  final DeviceGrantResult? result;

  const DeviceGrantState({
    required this.step,
    required this.components,
    required this.inputs,
    required this.actions,
    required this.values,
    required this.onValueChanged,
    required this.submit,
    required this.isLoading,
    required this.error,
    required this.result,
  });
}

/// Builds custom UI for a device grant from the state it hands over.
typedef DeviceGrantBuilder = Widget Function(BuildContext context, DeviceGrantState state);

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) item.map((key, value) => MapEntry('$key', value)),
      ]
    : const [];

String _str(Object? value) => value is String ? value : '';

/// The name an input is submitted under.
String _inputName(Map<String, dynamic> input) => [
  input['name'],
  input['identifier'],
  input['ref'],
  input['id'],
].map(_str).firstWhere((value) => value.isNotEmpty, orElse: () => '');

/// The id an action is submitted with.
String _actionId(Map<String, dynamic> action) =>
    [action['ref'], action['id']].map(_str).firstWhere((value) => value.isNotEmpty, orElse: () => '');

/// The names of the inputs a component tree asks for.
Iterable<String> _componentInputNames(List<Map<String, dynamic>> components) sync* {
  for (final component in components) {
    final type = _str(component['type']);
    if (type.endsWith('_INPUT') || type == 'SELECT' || type == 'OU_SELECT') {
      final name = [
        component['ref'],
        component['identifier'],
        component['name'],
        component['id'],
      ].map(_str).firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (name.isNotEmpty) yield name;
    }
    yield* _componentInputNames(_maps(component['components']));
  }
}

/// Translates [key] through the provider's i18n when there is one, else the built-in English.
String _t(BuildContext context, String key) =>
    ThunderIDProvider.maybeOf(context)?.i18n.resolve(key) ?? thunderDefaultStrings[key] ?? key;

/// The user side of device authorization, drawn from the flow step it is given: the code the
/// device shows (prefilled from [initialValues], e.g. a scanned verification URI's `user_code`)
/// and any further step the server returns, tagged `thunderid-field-<name>` and
/// `thunderid-action-<ref>`, then the approved, denied, expired or failed outcome. It makes no
/// request itself: pair it with `ThunderIDClient.verifyDeviceCode`, or use [DeviceGrant].
class BaseDeviceGrant extends StatefulWidget {
  final EmbeddedFlowResponse? step;

  /// Values the step's inputs start with, by input name.
  final Map<String, String> initialValues;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final DeviceGrantResult? result;

  /// Called with the chosen action (or `null` for the step's only one) and the entered values.
  final void Function(String? actionId, Map<String, String> inputs) onSubmit;

  /// The application whose flow runs, used to translate the step's server-described labels.
  final String? applicationId;

  /// Builds custom UI in place of the default view, from the step, the entered values, the submit
  /// action, and the loading, error and outcome state.
  final DeviceGrantBuilder? builder;

  const BaseDeviceGrant({
    super.key,
    required this.onSubmit,
    this.step,
    this.initialValues = const {},
    this.isLoading = false,
    this.error,
    this.result,
    this.applicationId,
    this.builder,
  });

  @override
  State<BaseDeviceGrant> createState() => _BaseDeviceGrantState();
}

class _BaseDeviceGrantState extends State<BaseDeviceGrant> {
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  String? _stepKey;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _components {
    final meta = widget.step?.data?['meta'];
    return meta is Map ? _maps(meta['components']) : const [];
  }

  List<Map<String, dynamic>> get _inputs => _maps(widget.step?.data?['inputs']);

  List<Map<String, dynamic>> get _actions => _maps(widget.step?.data?['actions']);

  /// Starts the entered values over when the server moves to another step.
  void _syncStep() {
    final names = {..._inputs.map(_inputName), ..._componentInputNames(_components)}..remove('');
    final key = '${widget.step?.flowId}|${widget.step?.stepId}|${names.join(',')}|${_actions.map(_actionId).join(',')}';
    if (key == _stepKey) return;
    _stepKey = key;
    _values
      ..clear()
      ..addAll({for (final name in names) name: widget.initialValues[name] ?? ''});
    // The previous step's fields still hold these until this frame is built.
    final stale = List.of(_controllers.values);
    _controllers.clear();
    if (stale.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in stale) {
          controller.dispose();
        }
      });
    }
  }

  /// The action to submit: the one asked for when the step has it, else the step's only action.
  String? _resolveAction(String? actionId) {
    final ids = _actions.map(_actionId).where((id) => id.isNotEmpty).toList();
    if (actionId != null && ids.contains(actionId)) return actionId;
    return ids.length == 1 ? ids.single : null;
  }

  void _submit([String? actionId]) {
    if (widget.isLoading) return;
    widget.onSubmit(_resolveAction(actionId), Map.of(_values));
  }

  @override
  Widget build(BuildContext context) {
    _syncStep();
    final state = DeviceGrantState(
      step: widget.step,
      components: _components,
      inputs: _inputs,
      actions: _actions,
      values: Map.unmodifiable(_values),
      onValueChanged: (name, value) => setState(() => _values[name] = value),
      submit: _submit,
      isLoading: widget.isLoading,
      error: widget.error,
      result: widget.result,
    );
    final builder = widget.builder;
    if (builder != null) return builder(context, state);
    final result = widget.result;
    if (result != null) return _ResultCard(result: result, message: widget.error);
    return Semantics(
      identifier: 'thunderid-device-grant',
      container: true,
      child: Column(
        key: const Key('thunderid-device-grant'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.components.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                header: true,
                child: Text(_t(context, 'deviceGrant.title'), style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
          if (widget.error != null) _ErrorText(message: widget.error!),
          if (state.components.isNotEmpty)
            FlowForm(
              key: ValueKey(_stepKey),
              applicationId: widget.applicationId ?? '',
              currentStep: widget.step,
              isLoading: widget.isLoading,
              error: null,
              initialValues: widget.initialValues,
              submitLabel: _t(context, 'deviceGrant.submit'),
              submit: (actionId, inputs) async {
                if (widget.isLoading) return;
                widget.onSubmit(_resolveAction(actionId), inputs);
              },
            )
          else
            ..._flatStep(context, state),
        ],
      ),
    );
  }

  List<Widget> _flatStep(BuildContext context, DeviceGrantState state) {
    if (state.isLoading && state.inputs.isEmpty) {
      return [
        Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(_t(context, 'deviceGrant.loading')),
          ],
        ),
      ];
    }
    return [
      if (state.inputs.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_t(context, 'deviceGrant.description'))),
      for (final input in state.inputs)
        if (_inputName(input).isNotEmpty) _field(context, _inputName(input), _str(input['type'])),
      if (state.actions.isEmpty && state.inputs.isNotEmpty)
        _button('submit', _t(context, 'deviceGrant.submit'), () => _submit())
      else
        for (final action in state.actions)
          _button(
            _actionId(action),
            _str(action['label']).isNotEmpty ? _str(action['label']) : _t(context, 'deviceGrant.submit'),
            () => _submit(_actionId(action)),
          ),
    ];
  }

  Widget _field(BuildContext context, String name, String type) {
    final controller = _controllers.putIfAbsent(name, () => TextEditingController(text: _values[name] ?? ''));
    final label = name == 'user_code' ? _t(context, 'deviceGrant.userCode') : name;
    final isPassword = type.toUpperCase().contains('PASSWORD');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        identifier: 'thunderid-field-$name',
        textField: true,
        child: TextField(
          key: Key('thunderid-field-$name'),
          controller: controller,
          enabled: !widget.isLoading,
          obscureText: isPassword,
          autocorrect: false,
          textCapitalization: name == 'user_code' ? TextCapitalization.characters : TextCapitalization.none,
          onChanged: (value) => _values[name] = value,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _button(String id, String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      identifier: 'thunderid-action-$id',
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: FilledButton(
          key: Key('thunderid-action-$id'),
          onPressed: widget.isLoading ? null : onPressed,
          child: widget.isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label),
        ),
      ),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  final String message;

  const _ErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'thunderid-device-grant-error',
      liveRegion: true,
      child: Container(
        key: const Key('thunderid-device-grant-error'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(8)),
        child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final DeviceGrantResult result;
  final String? message;

  const _ResultCard({required this.result, this.message});

  @override
  Widget build(BuildContext context) {
    final (title, description, icon) = switch (result) {
      DeviceGrantResult.approved => (
        'deviceGrant.messages.complete',
        'deviceGrant.messages.completeDescription',
        Icons.check_circle_outline,
      ),
      DeviceGrantResult.denied => (
        'deviceGrant.messages.denied',
        'deviceGrant.messages.deniedDescription',
        Icons.block,
      ),
      DeviceGrantResult.expired => (
        'deviceGrant.messages.expired',
        'deviceGrant.messages.expiredDescription',
        Icons.timer_off_outlined,
      ),
      DeviceGrantResult.failed => (
        'deviceGrant.messages.failed',
        'deviceGrant.messages.failedDescription',
        Icons.error_outline,
      ),
    };
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'thunderid-device-grant-result',
      liveRegion: true,
      container: true,
      child: Column(
        key: Key('thunderid-device-grant-result-${result.name}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: result == DeviceGrantResult.approved ? colors.primary : colors.error),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(_t(context, title), style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          Text(message ?? _t(context, description), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Runs the application's `DEVICE_GRANT` flow so the signed-in user can approve a device.
///
/// It submits [userCode] (e.g. the `user_code` of a scanned verification URI) when given,
/// otherwise asks for the code the device shows, renders every further step the server returns,
/// and shows whether the device was approved or denied, or the step expired. [applicationId]
/// defaults to `ThunderIDConfig.applicationId`. Server error text is never shown: a code that is
/// wrong or no longer usable, and a flow that cannot start or continue, get translated messages.
class DeviceGrant extends StatefulWidget {
  /// The application whose `DEVICE_GRANT` flow runs. Defaults to the configured one.
  final String? applicationId;

  /// The code the device shows, when the app already has it.
  final String? userCode;

  /// Called with the outcome once the flow has ended.
  final ValueChanged<DeviceGrantResult>? onComplete;

  /// Called with a translated message when the flow cannot be started or continued.
  final ValueChanged<String>? onError;

  /// Builds custom UI in place of the default view. See [BaseDeviceGrant.builder].
  final DeviceGrantBuilder? builder;

  const DeviceGrant({super.key, this.applicationId, this.userCode, this.onComplete, this.onError, this.builder});

  /// The server's code for a user code that is wrong or no longer usable. The step asks again.
  static const String invalidCodeError = 'FET-1131';

  @override
  State<DeviceGrant> createState() => _DeviceGrantState();
}

class _DeviceGrantState extends State<DeviceGrant> {
  EmbeddedFlowResponse? _step;
  bool _isLoading = true;
  String? _error;
  DeviceGrantResult? _result;
  Timer? _expiry;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final thunder = ThunderIDProvider.of(context);
    if (!_started && thunder.initialized) {
      _started = true;
      Future.microtask(
        () => _run(
          'deviceGrant.errors.start',
          () => thunder.client.verifyDeviceCode(userCode: widget.userCode, applicationId: widget.applicationId),
        ),
      );
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Future<void> _submit(String? actionId, Map<String, String> inputs) async {
    final step = _step;
    final flowId = step?.flowId;
    if (step == null || flowId == null || _isLoading) return;
    await _run(
      'deviceGrant.errors.continue',
      () => ThunderIDProvider.of(context).client.verifyDeviceCode(
        flowId: flowId,
        actionId: actionId,
        inputs: inputs,
        challengeToken: step.challengeToken,
      ),
    );
  }

  Future<void> _run(String failureKey, Future<EmbeddedFlowResponse> Function() call) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await call();
      if (mounted) _apply(response);
    } catch (_) {
      if (!mounted) return;
      _finish(DeviceGrantResult.failed, _t(context, failureKey));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _apply(EmbeddedFlowResponse response) {
    _expiry?.cancel();
    switch (response.flowStatus) {
      case FlowStatus.complete:
        _finish(DeviceGrantResult.approved, null);
      case FlowStatus.error:
        _finish(DeviceGrantResult.denied, null);
      case FlowStatus.promptOnly:
        setState(() {
          _step = response;
          _result = null;
          if (response.errorCode == DeviceGrant.invalidCodeError) {
            _error = _t(context, 'deviceGrant.errors.invalidCode');
          } else if (response.errorCode != null || response.failureReason != null) {
            _error = _t(context, 'deviceGrant.errors.continue');
          }
        });
        _scheduleExpiry(response);
    }
  }

  void _finish(DeviceGrantResult result, String? message) {
    setState(() {
      _step = null;
      _result = result;
      _error = message;
    });
    if (result == DeviceGrantResult.failed) {
      widget.onError?.call(message ?? _t(context, 'deviceGrant.messages.failed'));
    } else {
      widget.onComplete?.call(result);
    }
  }

  /// Ends the flow as expired when the step's `stepTimeout` (epoch milliseconds) passes first.
  void _scheduleExpiry(EmbeddedFlowResponse response) {
    final raw = response.additionalData?['stepTimeout'];
    final milliseconds = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (milliseconds == null || milliseconds <= 0) return;
    final delay = DateTime.fromMillisecondsSinceEpoch(milliseconds).difference(DateTime.now());
    final flowId = response.flowId;
    _expiry = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted || _step?.flowId != flowId || _result != null) return;
      _finish(DeviceGrantResult.expired, null);
    });
  }

  @override
  Widget build(BuildContext context) => BaseDeviceGrant(
    step: _step,
    initialValues: {if (widget.userCode != null) 'user_code': widget.userCode!},
    isLoading: _isLoading,
    error: _error,
    result: _result,
    applicationId: widget.applicationId,
    onSubmit: (actionId, inputs) => unawaited(_submit(actionId, inputs)),
    builder: widget.builder,
  );
}
