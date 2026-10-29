// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../flow_template_resolver.dart';
import '../../models/attribute_verification.dart';
import '../../models/flow_models.dart';
import '../../models/thunderid_error.dart';
import '../../models/user_profile.dart';
import '../auth/flow/flow_form.dart';
import '../thunderid_provider.dart';

/// Where a verification is: starting, showing a step, recorded by the server, or refused.
enum VerifyAttributePhase { loading, active, complete, failed }

/// State handed to the `builder` of [BaseVerifyAttribute] and [VerifyAttribute].
class VerifyAttributeState {
  final VerifyAttributePhase phase;

  /// The step to render, without the headings that became [title] and [subtitle], and with the
  /// `additionalData` of the step that sent the code when a rejected code returns none.
  final EmbeddedFlowResponse? currentStep;

  /// Changes with every step the server returns. Key the form with it, so typed values reset.
  final int stepCount;

  final String title;

  /// The flow's own prompt, or a generic one when the flow has none and no destination is known.
  final String? subtitle;

  /// The masked destination the code or link was sent to, when the flow reports it.
  final String? destination;

  /// [destination] in a sentence, shown in addition to [subtitle].
  final String? destinationMessage;

  /// The step has nothing to enter or submit: it waits for a link the user opens outside the app.
  final bool isAwaitingLink;

  final bool isLoading;
  final String? loadingActionId;

  /// The message to show: a rejected code, a missing code, or a refusal.
  final String? error;

  /// The flow metadata labels resolve from.
  final Map<String, dynamic> meta;

  /// The attribute's label, from the user schema.
  final String attributeDisplayName;

  /// The names of the step's inputs, the keys of [values].
  final List<String> inputNames;

  /// The values typed for the current step, keyed by input name. Cleared with every new step.
  final Map<String, String> values;

  /// Sets one input's value.
  final void Function(String name, String value) onValueChanged;

  /// Submits a step's action with [inputs], or with [values] when none are given. A required input
  /// that is empty is reported through [error] without a request.
  final Future<void> Function(String actionId, [Map<String, String>? inputs])
      submit;

  /// The action that submits the step's code, or null when the step has none.
  final String? submitActionId;

  /// Submits a `RESEND` action with no inputs and without validation.
  final Future<void> Function(String actionId) resend;

  /// The step's `RESEND` action, for [resend], or null when the step has none.
  final String? resendActionId;

  /// Re-reads the profile after the user opened the link, once; nothing polls.
  final Future<void> Function() done;

  /// Closes the panel, or null when the app passes no `onCancel`.
  final VoidCallback? onCancel;

  /// The translated message once the server recorded the verification; null until then.
  final String? successMessage;

  const VerifyAttributeState({
    required this.phase,
    required this.currentStep,
    required this.stepCount,
    required this.title,
    required this.subtitle,
    required this.destination,
    required this.destinationMessage,
    required this.isAwaitingLink,
    required this.isLoading,
    required this.loadingActionId,
    required this.error,
    required this.meta,
    required this.attributeDisplayName,
    required this.inputNames,
    required this.values,
    required this.onValueChanged,
    required this.submit,
    required this.submitActionId,
    required this.resend,
    required this.resendActionId,
    required this.done,
    required this.onCancel,
    required this.successMessage,
  });
}

/// Verifies one of the signed-in user's attributes, such as their email address, by running a
/// self attribute verification flow, named by [flowHandle]. The flow picks the email or mobile path
/// from the attribute's type, sends a code or a link to the stored value, and the component renders
/// the steps it describes. Once the server records the verification, and when the user selects
/// Done after a link, it re-reads the profile so [ThunderIDState.user] shows the new status.
///
/// It waits for the user schema, and refuses an attribute the schema does not declare as an `email`
/// or `mobile` property without a request. Starting sends a message, so each showing starts one
/// verification and never retries it: give each attribute its own [Key].
///
/// With profile fetching off ([ThunderIDConfig.fetchUserProfile] false, or sign-in on a backend),
/// the profile is not read again after `COMPLETE` or on Done, so a status shown elsewhere is not
/// refreshed.
class VerifyAttribute extends StatelessWidget {
  final String attribute;
  final String flowHandle;
  final String? attributeDisplayName;

  /// Called once the server has recorded the verification and the profile was read again.
  final VoidCallback? onComplete;

  /// Called when the user selects Done after a link was sent and the profile was read again.
  final VoidCallback? onDone;

  /// Called when the attribute cannot be verified, the server refuses
  /// ([ThunderIDErrorCode.verificationFailed]), or a request fails.
  final ValueChanged<IAMException>? onError;

  /// Closes the panel. The Cancel (or Close) action is shown only when this is set.
  final VoidCallback? onCancel;

  /// Builds custom UI in place of the default panel, from the step's inputs, values and setter,
  /// submit and resend, where the code went, loading, error and completion. See
  /// [BaseVerifyAttribute.builder].
  final Widget Function(BuildContext context, VerifyAttributeState state)?
      builder;

  const VerifyAttribute({
    super.key,
    required this.attribute,
    this.flowHandle = AttributeVerification.defaultFlowHandle,
    this.attributeDisplayName,
    this.onComplete,
    this.onDone,
    this.onError,
    this.onCancel,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return BaseVerifyAttribute(
      attribute: attribute,
      flowHandle: flowHandle,
      attributeDisplayName: attributeDisplayName,
      onComplete: onComplete,
      onDone: onDone,
      onError: onError,
      onCancel: onCancel,
      builder: builder ?? _panel,
    );
  }

  /// The default UI.
  Widget _panel(BuildContext context, VerifyAttributeState state) {
    final i18n = ThunderIDProvider.of(context).i18n;
    final theme = Theme.of(context);
    final active = state.phase == VerifyAttributePhase.active;
    final cancel = state.onCancel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.phase == VerifyAttributePhase.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (active) ...[
          Text(
            state.title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (state.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(state.subtitle!, style: theme.textTheme.bodyMedium),
            ),
          if (state.destinationMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                state.destinationMessage!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (state.error != null) _Notice(message: state.error!, isError: true),
        if (state.successMessage != null)
          _Notice(message: state.successMessage!, isError: false),
        if (active && !state.isAwaitingLink)
          FlowForm(
            key: ValueKey(state.stepCount),
            applicationId: '',
            currentStep: state.currentStep,
            isLoading: state.isLoading,
            loadingActionId: state.loadingActionId,
            error: null,
            meta: state.meta,
            submit: state.submit,
            resend: state.resend,
            submitLabel: i18n.resolve('verifyAttribute.submit'),
          ),
        if ((active && state.isAwaitingLink) || cancel != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                if (active && state.isAwaitingLink)
                  Semantics(
                    identifier: 'thunderid-action-verificationDone',
                    child: FilledButton(
                      key: const Key('thunderid-action-verificationDone'),
                      onPressed: state.isLoading ? null : state.done,
                      child: Text(i18n.resolve('verifyAttribute.done')),
                    ),
                  ),
                if (cancel != null)
                  Semantics(
                    identifier: 'thunderid-action-verificationCancel',
                    child: OutlinedButton(
                      key: const Key('thunderid-action-verificationCancel'),
                      onPressed: cancel,
                      child: Text(
                        i18n.resolve(
                          active || state.phase == VerifyAttributePhase.loading
                              ? 'verifyAttribute.cancel'
                              : 'verifyAttribute.close',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;
  final bool isError;

  const _Notice({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        isError ? colors.onErrorContainer : colors.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message, style: TextStyle(color: foreground, fontSize: 13)),
      ),
    );
  }
}

/// Unstyled base variant (spec §8.3) of [VerifyAttribute]: runs the flow and hands its state to
/// [builder], which draws every step. The flow still starts once per showing, the profile is read
/// again before [onComplete], and the status comes only from the server.
class BaseVerifyAttribute extends StatefulWidget {
  final String attribute;
  final String flowHandle;
  final String? attributeDisplayName;

  /// Called once the server has recorded the verification and the profile was read again.
  final VoidCallback? onComplete;

  /// Called when the user selects Done after a link was sent and the profile was read again.
  final VoidCallback? onDone;

  /// Called when the attribute cannot be verified, the server refuses
  /// ([ThunderIDErrorCode.verificationFailed]), or a request fails.
  final ValueChanged<IAMException>? onError;

  /// Handed to [builder] as [VerifyAttributeState.onCancel].
  final VoidCallback? onCancel;
  final Widget Function(BuildContext context, VerifyAttributeState state)
      builder;

  const BaseVerifyAttribute({
    super.key,
    required this.attribute,
    required this.builder,
    this.flowHandle = AttributeVerification.defaultFlowHandle,
    this.attributeDisplayName,
    this.onComplete,
    this.onDone,
    this.onError,
    this.onCancel,
  });

  @override
  State<BaseVerifyAttribute> createState() => _BaseVerifyAttributeState();
}

class _BaseVerifyAttributeState extends State<BaseVerifyAttribute> {
  // Guards against a second start, which would send a second message.
  bool _started = false;
  VerifyAttributePhase _phase = VerifyAttributePhase.loading;
  EmbeddedFlowResponse? _step;
  Map<String, dynamic>? _additionalData;
  String? _flowId;
  String? _challengeToken;
  int _stepCount = 0;
  bool _isLoading = false;
  String? _loadingActionId;
  String? _error;
  Map<String, dynamic> _meta = const {};
  String? _displayName;
  // Values a builder typed through onValueChanged; FlowForm keeps its own.
  final _values = <String, String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Starts once the provider has initialized the client, and never again for this showing.
    if (!_started && ThunderIDProvider.of(context).initialized) {
      _started = true;
      Future.microtask(_start);
    }
  }

  Future<void> _start() async {
    if (!mounted) return;
    final thunder = ThunderIDProvider.of(context);
    try {
      final results = await Future.wait<Object>([
        thunder.client.getUserSchema(),
        _loadMeta(thunder),
      ]);
      if (!mounted) return;
      final schema = results[0] as Map<String, AttributeSchema>;
      _meta = results[1] as Map<String, dynamic>;
      _displayName =
          widget.attributeDisplayName ?? schema[widget.attribute]?.displayName;
      if (!AttributeVerification.isVerifiableAttribute(
        widget.attribute,
        schema,
      )) {
        _fail(
          IAMException(
            ThunderIDErrorCode.invalidInput,
            'Attribute "${widget.attribute}" is not a verifiable email or mobile attribute',
          ),
        );
        return;
      }
      final response = await thunder.client.verifyAttribute(
        attribute: widget.attribute,
        handle: widget.flowHandle,
      );
      await _handle(response);
    } catch (e) {
      _fail(e);
    }
  }

  // As sign-up does, labels resolve from the application's flow metadata when it has one; otherwise
  // the SDK's own strings are used.
  Future<Map<String, dynamic>> _loadMeta(ThunderIDState thunder) async {
    final applicationId = thunder.config.applicationId;
    if (applicationId == null) return const {};
    try {
      return await thunder.client
          .getFlowMeta(applicationId, language: thunder.i18n.activeLocale);
    } catch (_) {
      return const {};
    }
  }

  Future<void> _handle(EmbeddedFlowResponse response) async {
    if (!mounted) return;
    _flowId = response.flowId ?? _flowId;
    _challengeToken = response.challengeToken ?? _challengeToken;
    final resolver = FlowTemplateResolver(_meta);
    final hasError = response.errorMessage != null ||
        _nonEmpty(response.failureReason) != null;
    final message = hasError
        ? resolver.translate(response.errorMessage) ??
            _resolve('verifyAttribute.error')
        : null;
    switch (response.flowStatus) {
      case FlowStatus.error:
        final shown = _resolve('verifyAttribute.error');
        setState(() {
          _phase = VerifyAttributePhase.failed;
          _error = shown;
        });
        widget.onError?.call(
          const IAMException(
            ThunderIDErrorCode.verificationFailed,
            'The server refused the verification',
          ),
        );
      case FlowStatus.complete:
        setState(() {
          _phase = VerifyAttributePhase.complete;
          _error = null;
          _values.clear();
        });
        // Re-read whether or not anyone listens, so the recorded status shows.
        await _readProfile();
        if (mounted) widget.onComplete?.call();
      case FlowStatus.promptOnly:
        // A rejected code returns the step without additionalData; keep only the destination, channel
        // and code length from the step that sent the code.
        final carried = {
          for (final entry
              in (_additionalData ?? const <String, dynamic>{}).entries)
            if (AttributeVerification.carriedForwardKeys.contains(entry.key))
              entry.key: entry.value,
        };
        final additionalData = {...carried, ...?response.additionalData};
        setState(() {
          _additionalData = additionalData.isEmpty ? null : additionalData;
          _step = response;
          _stepCount++;
          _values.clear();
          _phase = VerifyAttributePhase.active;
          _error = message;
        });
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    final exception = error is IAMException
        ? error
        : IAMException(
            ThunderIDErrorCode.unknownError,
            'The verification request failed',
            cause: error,
          );
    // A generic message: an error's text is not meant for the user.
    setState(() {
      _phase = VerifyAttributePhase.failed;
      _error = _resolve('verifyAttribute.error');
    });
    widget.onError?.call(exception);
  }

  Future<void> _submit(String actionId, [Map<String, String>? inputs]) async {
    if (_isLoading) return;
    final sent = {
      for (final entry in (inputs ?? _values).entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    final missing = _requiredInputs().any((name) => !sent.containsKey(name));
    if (missing) {
      setState(() => _error = _resolve('verifyAttribute.required'));
      return;
    }
    await _send(actionId, sent);
  }

  Future<void> _resend(String actionId) => _send(actionId, const {});

  Future<void> _send(String actionId, Map<String, String> inputs) async {
    final flowId = _flowId;
    if (flowId == null || _isLoading) return;
    setState(() {
      _isLoading = true;
      _loadingActionId = actionId;
      _error = null;
    });
    try {
      final response =
          await ThunderIDProvider.of(context).client.verifyAttribute(
                payload: EmbeddedSignInPayload(
                  flowId: flowId,
                  actionId: actionId,
                  inputs: inputs,
                  challengeToken: _challengeToken,
                ),
              );
      await _handle(response);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingActionId = null;
        });
      }
    }
  }

  Future<void> _done() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    await _readProfile();
    if (!mounted) return;
    setState(() => _isLoading = false);
    widget.onDone?.call();
  }

  // Re-reads the profile into the provider and hands it to an enclosing [VerifiedProfileSink].
  Future<void> _readProfile() async {
    final sink = VerifiedProfileSink.maybeOf(context);
    final profile = await ThunderIDProvider.of(context).reloadUserProfile();
    if (mounted) sink?.call(profile);
  }

  Iterable<String> _requiredInputs() => _readList(_step?.data?['inputs'])
      .where((input) => input['required'] == true)
      .map(
        (input) => _str(
          input['name'],
          fallback: _str(input['identifier'], fallback: _str(input['ref'])),
        ),
      )
      .where((name) => name.isNotEmpty);

  String _resolve(String key) =>
      ThunderIDProvider.of(context).i18n.resolve(key);

  @override
  Widget build(BuildContext context) {
    final i18n = ThunderIDProvider.of(context).i18n;
    final resolver = FlowTemplateResolver(_meta);
    final displayName = _displayName ?? widget.attribute;
    final data = _step?.data ?? const <String, dynamic>{};
    final rawMeta = data['meta'];
    final components = rawMeta is Map
        ? _readList(rawMeta['components'])
        : const <Map<String, dynamic>>[];
    final headings = splitHeadings(components);

    final awaitingLink = _phase == VerifyAttributePhase.active &&
        !_hasInput(headings.rest, data) &&
        !_hasAction(headings.rest, data);
    final destination = _nonEmpty(
      _additionalData?[AttributeVerification.maskedDestinationKey]?.toString(),
    );
    final flowSubtitle = _label(resolver, headings.subtitle);
    final title = _label(resolver, headings.title) ??
        i18n
            .resolve('verifyAttribute.heading')
            .replaceAll('{attribute}', displayName);

    final actions = _readList(data['actions']);
    final resendRef = _firstRef(headings.rest, (c) => c['type'] == 'RESEND');
    final submitRef = _firstRef(headings.rest, (c) => c['type'] == 'ACTION');
    final resendActionId =
        resendRef == null ? null : _actionId(resendRef, actions);
    final submitActionId = submitRef != null
        ? _actionId(submitRef, actions)
        : actions
            .map(_actionSubmitId)
            .where((id) => id.isNotEmpty && id != resendActionId)
            .firstOrNull;

    final step = _step;
    final shownStep = step == null
        ? null
        : EmbeddedFlowResponse(
            flowId: step.flowId,
            flowStatus: step.flowStatus,
            stepId: step.stepId,
            type: step.type,
            challengeToken: step.challengeToken,
            data: {
              ...data,
              'meta': {
                if (rawMeta is Map) ...rawMeta.cast<String, dynamic>(),
                'components': headings.rest,
              },
              if (_additionalData != null) 'additionalData': _additionalData,
            },
          );

    return widget.builder(
      context,
      VerifyAttributeState(
        phase: _phase,
        currentStep: shownStep,
        stepCount: _stepCount,
        title: title,
        subtitle: flowSubtitle ??
            (destination == null
                ? i18n.resolve('verifyAttribute.subheading.generic')
                : null),
        destination: destination,
        destinationMessage: destination == null
            ? null
            : i18n
                .resolve(
                  awaitingLink
                      ? 'verifyAttribute.destination.link'
                      : 'verifyAttribute.destination',
                )
                .replaceAll('{destination}', destination),
        isAwaitingLink: awaitingLink,
        isLoading: _isLoading || _phase == VerifyAttributePhase.loading,
        loadingActionId: _loadingActionId,
        error: _error,
        meta: _meta,
        attributeDisplayName: displayName,
        inputNames: _phase == VerifyAttributePhase.active
            ? _inputNames(headings.rest, data)
            : const [],
        values: Map.unmodifiable(_values),
        onValueChanged: (name, value) => setState(() => _values[name] = value),
        submit: _submit,
        submitActionId:
            _phase == VerifyAttributePhase.active ? submitActionId : null,
        resend: _resend,
        resendActionId:
            _phase == VerifyAttributePhase.active ? resendActionId : null,
        done: _done,
        onCancel: widget.onCancel,
        successMessage: _phase == VerifyAttributePhase.complete
            ? i18n
                .resolve('verifyAttribute.success')
                .replaceAll('{attribute}', displayName)
            : null,
      ),
    );
  }
}

/// Hands the profile a [BaseVerifyAttribute] read again to an enclosing widget, such as
/// [UserProfile]'s, so its status updates without a second read. Not exported.
class VerifiedProfileSink extends InheritedWidget {
  final ValueChanged<UserProfile?> onProfileRead;

  const VerifiedProfileSink({
    super.key,
    required this.onProfileRead,
    required super.child,
  });

  static ValueChanged<UserProfile?>? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<VerifiedProfileSink>()
      ?.onProfileRead;

  @override
  bool updateShouldNotify(VerifiedProfileSink oldWidget) => false;
}

/// The first two top-level `HEADING_*` texts of a step, as its title and subtitle, and the
/// components left once they are taken out.
@visibleForTesting
({String? title, String? subtitle, List<Map<String, dynamic>> rest})
    splitHeadings(
  List<Map<String, dynamic>> components,
) {
  final headings = <String>[];
  final rest = <Map<String, dynamic>>[];
  for (final component in components) {
    final isHeading = component['type'] == 'TEXT' &&
        _str(component['variant']).startsWith('HEADING');
    if (isHeading && headings.length < 2) {
      headings.add(_str(component['label']));
    } else {
      rest.add(component);
    }
  }
  return (
    title: headings.isEmpty ? null : headings[0],
    subtitle: headings.length < 2 ? null : headings[1],
    rest: rest,
  );
}

bool _hasInput(
  List<Map<String, dynamic>> components,
  Map<String, dynamic> data,
) {
  if (components.isEmpty) return _readList(data['inputs']).isNotEmpty;
  return _anyComponent(
    components,
    (c) => _str(c['type']).endsWith('_INPUT') || c['category'] == 'FIELD',
  );
}

bool _hasAction(
  List<Map<String, dynamic>> components,
  Map<String, dynamic> data,
) {
  if (components.isEmpty) return _readList(data['actions']).isNotEmpty;
  return _anyComponent(
    components,
    (c) =>
        const {'ACTION', 'RESEND'}.contains(_str(c['type'])) ||
        c['category'] == 'ACTION',
  );
}

// Input names as FlowForm submits them: the component refs, then any input the components miss.
List<String> _inputNames(
  List<Map<String, dynamic>> components,
  Map<String, dynamic> data,
) {
  final names = <String>[];
  void add(String name) {
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }

  void walk(List<Map<String, dynamic>> list) {
    for (final c in list) {
      final isField =
          _str(c['type']).endsWith('_INPUT') || c['category'] == 'FIELD';
      if (isField) add(_firstOf(c, const ['ref', 'identifier', 'name', 'id']));
      walk(_readList(c['components']));
    }
  }

  walk(components);
  for (final input in _readList(data['inputs'])) {
    add(_firstOf(input, const ['name', 'identifier', 'ref', 'id']));
  }
  return names;
}

String _firstOf(Map<String, dynamic> map, List<String> keys) => keys
    .map((key) => _str(map[key]))
    .firstWhere((value) => value.isNotEmpty, orElse: () => '');

String? _firstRef(
  List<Map<String, dynamic>> components,
  bool Function(Map<String, dynamic>) test,
) {
  for (final c in components) {
    if (test(c)) return _str(c['ref'], fallback: _str(c['id']));
    final nested = _firstRef(_readList(c['components']), test);
    if (nested != null) return nested;
  }
  return null;
}

// The action ID FlowForm submits for a component.
String _actionId(String ref, List<Map<String, dynamic>> actions) {
  for (final a in actions) {
    if (_str(a['ref']) == ref || _str(a['id']) == ref) {
      return _actionSubmitId(a);
    }
  }
  return ref;
}

String _actionSubmitId(Map<String, dynamic> a) =>
    _str(a['ref'], fallback: _str(a['id'], fallback: _str(a['nextNode'])));

bool _anyComponent(
  List<Map<String, dynamic>> components,
  bool Function(Map<String, dynamic>) test,
) =>
    components
        .any((c) => test(c) || _anyComponent(_readList(c['components']), test));

// A label that does not resolve, or still holds a template, falls back to the SDK's string.
String? _label(FlowTemplateResolver resolver, String? raw) {
  final resolved = _nonEmpty(resolver.resolve(raw));
  return resolved == null || resolved.contains('{{') ? null : resolved;
}

List<Map<String, dynamic>> _readList(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry('$k', v)))
        .toList()
    : const [];

String _str(Object? value, {String fallback = ''}) =>
    value is String && value.isNotEmpty ? value : fallback;

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;
