// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/flow_models.dart';
import '../../models/thunderid_error.dart';
import '../../models/token_exchange_config.dart';
import '../../models/user.dart';
import '../thunderid_provider.dart';
import 'federated_redirect.dart';
import 'flow/flow_expiry.dart';
import 'flow/flow_form.dart';

/// State exposed to [BaseSignIn]'s builder.
class SignInState {
  final EmbeddedFlowResponse? currentStep;
  final bool isLoading;
  final String? loadingActionId;
  final String? error;
  /// The server's translatable form of [error], when the flow returned one.
  final FlowErrorText? errorMessage;
  final Future<void> Function(String actionId, Map<String, String> inputs) submit;

  /// Whether the flow was started again because the previous one expired. Clears once the user acts on the
  /// new flow.
  final bool isFlowRestarted;

  const SignInState({
    required this.currentStep,
    required this.isLoading,
    required this.error,
    required this.submit,
    this.loadingActionId,
    this.errorMessage,
    this.isFlowRestarted = false,
  });
}

/// Full sign-in form that drives the Flow Execution API loop (spec §8.4 Presentation).
/// Renders each step's inputs dynamically based on server-reported [FlowStepData].
class SignIn extends StatelessWidget {
  final String applicationId;
  final void Function(User user)? onSuccess;
  final VoidCallback? onError;

  final bool _reauthentication;
  final int? _reauthenticationMaxAge;
  final void Function(Object error)? _onException;

  const SignIn({
    super.key,
    required this.applicationId,
    this.onSuccess,
    this.onError,
  })  : _reauthentication = false,
        _reauthenticationMaxAge = null,
        _onException = null;

  const SignIn._reauthentication({
    required this.applicationId,
    required int? maxAge,
    this.onSuccess,
    this.onError,
    void Function(Object error)? onException,
  })  : _reauthentication = true,
        _reauthenticationMaxAge = maxAge,
        _onException = onException;

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseSignIn._all(
      applicationId: applicationId,
      onSuccess: onSuccess,
      onError: onError,
      reauthentication: _reauthentication,
      reauthenticationMaxAge: _reauthenticationMaxAge,
      onException: _onException,
      builder: (ctx, signInState) => FlowForm(
        applicationId: applicationId,
        currentStep: signInState.currentStep,
        isLoading: signInState.isLoading,
        loadingActionId: signInState.loadingActionId,
        error: signInState.error,
        errorMessage: signInState.errorMessage,
        submit: signInState.submit,
        submitLabel: state.i18n.resolve('signIn.submit'),
        notice: signInState.isFlowRestarted ? state.i18n.resolve('flow.expired.restarted') : null,
      ),
    );
  }
}

/// Unstyled base variant. [builder] receives [SignInState] to render any UI (spec §8.3).
class BaseSignIn extends StatefulWidget {
  final String applicationId;
  final void Function(User user)? onSuccess;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, SignInState state) builder;

  final bool _reauthentication;
  final int? _reauthenticationMaxAge;
  final void Function(Object error)? _onException;

  const BaseSignIn({
    super.key,
    required this.applicationId,
    required this.builder,
    this.onSuccess,
    this.onError,
  })  : _reauthentication = false,
        _reauthenticationMaxAge = null,
        _onException = null;

  const BaseSignIn._all({
    required this.applicationId,
    required this.builder,
    required bool reauthentication,
    required int? reauthenticationMaxAge,
    required void Function(Object error)? onException,
    this.onSuccess,
    this.onError,
  })  : _reauthentication = reauthentication,
        _reauthenticationMaxAge = reauthenticationMaxAge,
        _onException = onException;

  @override
  State<BaseSignIn> createState() => _BaseSignInState();
}

class _BaseSignInState extends State<BaseSignIn> {
  EmbeddedFlowResponse? _currentStep;
  bool _isLoading = false;
  String? _loadingActionId;
  String? _errorText;
  FlowErrorText? _errorMessage;

  /// Every new error replaces [_errorMessage], so a flow error's key never outlives its text.
  String? get _error => _errorText;
  set _error(String? value) {
    _errorText = value;
    _errorMessage = null;
  }
  bool _autoAdvancing = false;

  /// Debug log tag scoped to the configured [ThunderIDConfig.vendor] rather than a hardcoded
  /// brand literal, since a consuming app may white-label the SDK.
  String get _logTag => '[${ThunderIDProvider.of(context).widget.config.vendor}SignIn]';

  bool _isFlowRestarted = false;

  EmbeddedFlowRequestConfig get _request => EmbeddedFlowRequestConfig(
        applicationId: widget.applicationId,
        reauthentication: widget._reauthentication,
        maxAge: widget._reauthenticationMaxAge,
      );

  // Starts again after the current submit settles, so its loading state doesn't end the new flow's.
  late final FlowExpiry _flowExpiry = FlowExpiry(restart: () => Future.microtask(_restartFlow));

  @override
  void initState() {
    super.initState();
    _flowExpiry.listen();
    Future.microtask(_initFlow);
  }

  @override
  void dispose() {
    _flowExpiry.dispose();
    super.dispose();
  }

  /// Starts an expired flow again in place.
  Future<void> _restartFlow() async {
    if (!mounted) return;
    setState(() {
      _currentStep = null;
      _error = null;
      _isFlowRestarted = true;
    });
    await _initFlow();
  }

  Future<void> _initFlow() async {
    setState(() => _isLoading = true);
    try {
      final state = ThunderIDProvider.of(context);
      final response = await state.client.signIn(
        payload: const EmbeddedSignInPayload(actionId: 'init'),
        request: _request,
      );
      if (kDebugMode) {
        final inputList = (response.data?['inputs'] as List?) ?? const [];
        final actionList = (response.data?['actions'] as List?) ?? const [];
        debugPrint('$_logTag init response flowStatus=${response.flowStatus} inputs=$inputList actions=$actionList');
      }
      await _finishResponse(response, actionId: 'init', flowId: response.flowId ?? '');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      widget._onException?.call(e);
      widget.onError?.call();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit(String actionId, Map<String, String> inputs) async {
    final flowId = _currentStep?.flowId;
    debugPrint('$_logTag _submit flowId=$flowId actionId=$actionId inputs=${inputs.keys.toList()}');
    if (flowId == null) return;
    setState(() { _isLoading = true; _loadingActionId = actionId; _isFlowRestarted = false; });
    try {
      final response = await ThunderIDProvider.of(context).client.signIn(
        payload: EmbeddedSignInPayload(flowId: flowId, actionId: actionId, inputs: inputs, challengeToken: _currentStep?.challengeToken),
        request: _request,
      );
      await _finishResponse(response, actionId: actionId, flowId: flowId);
    } catch (e, st) {
      if (e is IAMException && e.code == ThunderIDErrorCode.flowExpired) {
        _flowExpiry.expire();
        return;
      }
      debugPrint('$_logTag _submit error: $e\n$st');
      if (mounted) setState(() => _error = e.toString());
      widget._onException?.call(e);
      widget.onError?.call();
    } finally {
      _autoAdvancing = false;
      if (mounted) setState(() { _isLoading = false; _loadingActionId = null; });
    }
  }

  /// Shared response-handling tail for both [_initFlow] and [_submit]: resolves any pending
  /// passkey ceremony, follows a `REDIRECTION` federated-auth step, auto-advances a
  /// single-action step, and then applies the terminal completion/error/incomplete state.
  Future<void> _finishResponse(
    EmbeddedFlowResponse initialResponse, {
    required String actionId,
    required String flowId,
  }) async {
    final state = ThunderIDProvider.of(context);
    var response = initialResponse;

    if (response.additionalData?['passkeyChallenge'] != null ||
        response.additionalData?['passkeyCreationOptions'] != null) {
      final ceremonyResponse = await _performPasskeyCeremony(response);
      if (ceremonyResponse == null) return;
      response = ceremonyResponse;
    }

    try {
      if (kDebugMode && response.type == 'REDIRECTION') {
        debugPrint('$_logTag REDIRECTION for actionId=$actionId, delegating to continueFederatedAuth');
      }
      final resumed = await followFederatedRedirect(
        state.client,
        response,
        actionId: actionId,
        applicationId: widget.applicationId,
        flowId: flowId,
        challengeToken: _currentStep?.challengeToken,
      );
      // User dismissed the browser without completing sign-in — reset silently.
      if (resumed == null) return;
      response = resumed;

      if (_shouldAutoAdvance(response)) {
        _autoAdvancing = true;
        final nextActionId = _nextActionId(response);
        if (nextActionId.isNotEmpty && response.flowId != null) {
          if (kDebugMode) {
            debugPrint('$_logTag auto-advancing actionId=$nextActionId');
          }
          response = await state.client.signIn(
            payload: EmbeddedSignInPayload(
              flowId: response.flowId,
              actionId: nextActionId,
              inputs: const {},
              challengeToken: response.challengeToken,
            ),
            request: _request,
          );
        }
      }

      if (kDebugMode) {
        final hasAssertion = response.assertion?.isNotEmpty ?? false;
        final inputCount = (response.data?['inputs'] as List?)?.length ?? 0;
        final actionCount = (response.data?['actions'] as List?)?.length ?? 0;
        final inputList = (response.data?['inputs'] as List?) ?? const [];
        final actionList = (response.data?['actions'] as List?) ?? const [];
        debugPrint('$_logTag submit response flowStatus=${response.flowStatus} hasAssertion=$hasAssertion inputs=$inputCount actions=$actionCount failureReason=${response.failureReason}');
        debugPrint('$_logTag submit response inputData=$inputList actionData=$actionList');
      }
      _flowExpiry.track(response);
      final isComplete = response.flowStatus == FlowStatus.complete ||
          (response.assertion?.isNotEmpty ?? false);
      if (isComplete) {
        if (mounted) {
          setState(() {
            _currentStep = response;
            _error = null;
          });
        }
        final assertion = response.assertion;
        if (assertion != null && assertion.isNotEmpty) {
          final signedIn = await state.client.isSignedIn();
          if (!signedIn) {
            await state.client.exchangeToken(
              TokenExchangeRequestConfig(
                subjectToken: assertion,
                subjectTokenType: 'urn:ietf:params:oauth:token-type:jwt',
              ),
            );
          }
        }
        await state.refresh();
        if (mounted) {
          final user = state.user;
          if (user != null) {
            widget.onSuccess?.call(user);
          } else {
            setState(() => _error = 'Sign-in completed, but session was not established.');
            widget.onError?.call();
          }
        }
      } else if (response.flowStatus == FlowStatus.error) {
        if (mounted) {
          setState(() {
            _error = response.failureReason ?? 'Authentication failed';
            _errorMessage = response.errorMessage;
          });
        }
        widget.onError?.call();
      } else {
        if (mounted) {
          setState(() {
            _currentStep = response;
            _error = response.failureReason;
            _errorMessage = response.errorMessage;
          });
        }
      }
    } finally {
      _autoAdvancing = false;
    }
  }

  /// Runs the native WebAuthn ceremony (`performPasskeyAuthentication` for a
  /// `passkeyChallenge`, `performPasskeyRegistration` for `passkeyCreationOptions`) and
  /// resubmits the flow with the resulting flat inputs, without requiring another user tap.
  /// A failed ceremony is submitted as `passkeyError` and the step the flow returns is shown.
  /// Loops in case a successful resubmit returns another passkey ceremony step. Returns `null`
  /// (after setting [_error]) when the resubmit fails, so the caller can bail out of [_submit].
  Future<EmbeddedFlowResponse?> _performPasskeyCeremony(EmbeddedFlowResponse response) async {
    final state = ThunderIDProvider.of(context);
    var current = response;
    while (true) {
      final passkeyChallenge = current.additionalData?['passkeyChallenge'] as String?;
      final passkeyCreationOptions = current.additionalData?['passkeyCreationOptions'] as String?;
      if (passkeyChallenge == null && passkeyCreationOptions == null) return current;

      final flowId = current.flowId;
      if (flowId == null) return current;

      Map<String, String> inputs;
      Object? ceremonyError;
      try {
        inputs = passkeyChallenge != null
            ? await state.client.performPasskeyAuthentication(requestOptionsJson: passkeyChallenge)
            : await state.client.performPasskeyRegistration(creationOptionsJson: passkeyCreationOptions!);
      } catch (e) {
        ceremonyError = e;
        // Reports the failed prompt to the flow, which is still waiting for the passkey.
        inputs = {'passkeyError': e is IAMException ? e.code.value : ThunderIDErrorCode.passkeyFailed.value};
      }
      try {
        current = await state.client.signIn(
          payload: EmbeddedSignInPayload(
            flowId: flowId,
            actionId: '',
            inputs: inputs,
            challengeToken: current.challengeToken,
          ),
          request: _request,
        );
      } catch (e) {
        if (mounted) setState(() => _error = (ceremonyError ?? e).toString());
        widget._onException?.call(e);
        widget.onError?.call();
        return null;
      }
      // Shows the step the flow returned for the failure instead of prompting again.
      if (ceremonyError != null) return current;
    }
  }

  bool _shouldAutoAdvance(EmbeddedFlowResponse response) {
    if (_autoAdvancing) return false;
    if (response.flowStatus != FlowStatus.promptOnly) return false;
    // A step carrying an error is shown, not skipped.
    if (response.failureReason != null || response.errorMessage != null) return false;
    final data = response.data;
    if (data == null) return false;

    final inputs = data['inputs'];
    final actions = data['actions'];
    final inputCount = inputs is List ? inputs.length : 0;
    final actionCount = actions is List ? actions.length : 0;
    return inputCount == 0 && actionCount == 1;
  }

  String _nextActionId(EmbeddedFlowResponse response) {
    final data = response.data;
    if (data == null) return '';
    final actions = data['actions'];
    if (actions is! List || actions.isEmpty) return '';
    final first = actions.first;
    if (first is! Map) return '';
    final ref = first['ref'];
    if (ref is String && ref.isNotEmpty) return ref;

    final id = first['id'];
    if (id is String && id.isNotEmpty) return id;

    final nextNode = first['nextNode'];
    return nextNode is String ? nextNode : '';
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        SignInState(
          currentStep: _currentStep,
          isLoading: _isLoading,
          loadingActionId: _loadingActionId,
          error: _error,
          errorMessage: _errorMessage,
          submit: _submit,
          isFlowRestarted: _isFlowRestarted,
        ),
      );
}

/// The sign-in form, run to sign the signed-in user in again with [maxAge]: see
/// `EmbeddedFlowRequestConfig.reauthentication`. [onException] gets the error when a request of the
/// flow fails, before [onError]. Not exported.
Widget reauthenticationSignIn({
  required String applicationId,
  required int? maxAge,
  required void Function(User user) onSuccess,
  required VoidCallback onError,
  required void Function(Object error) onException,
}) =>
    SignIn._reauthentication(
      applicationId: applicationId,
      maxAge: maxAge,
      onSuccess: onSuccess,
      onError: onError,
      onException: onException,
    );
