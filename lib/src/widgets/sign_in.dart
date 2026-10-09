// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/flow_models.dart';
import '../models/token_exchange_config.dart';
import '../models/user.dart';
import 'federated_redirect.dart';
import 'flow_form.dart';
import 'thunderid_provider.dart';

/// State exposed to [BaseSignIn]'s builder.
class SignInState {
  final EmbeddedFlowResponse? currentStep;
  final bool isLoading;
  final String? loadingActionId;
  final String? error;
  final Future<void> Function(String actionId, Map<String, String> inputs) submit;

  const SignInState({
    required this.currentStep,
    required this.isLoading,
    required this.error,
    required this.submit,
    this.loadingActionId,
  });
}

/// Full sign-in form that drives the Flow Execution API loop (spec §8.4 Presentation).
/// Renders each step's inputs dynamically based on server-reported [FlowStepData].
class SignIn extends StatelessWidget {
  final String applicationId;
  final void Function(User user)? onSuccess;
  final VoidCallback? onError;

  const SignIn({
    super.key,
    required this.applicationId,
    this.onSuccess,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseSignIn(
      applicationId: applicationId,
      onSuccess: onSuccess,
      onError: onError,
      builder: (ctx, signInState) => FlowForm(
        applicationId: applicationId,
        currentStep: signInState.currentStep,
        isLoading: signInState.isLoading,
        loadingActionId: signInState.loadingActionId,
        error: signInState.error,
        submit: signInState.submit,
        submitLabel: state.i18n.resolve('signIn.submit'),
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

  const BaseSignIn({
    super.key,
    required this.applicationId,
    required this.builder,
    this.onSuccess,
    this.onError,
  });

  @override
  State<BaseSignIn> createState() => _BaseSignInState();
}

class _BaseSignInState extends State<BaseSignIn> {
  EmbeddedFlowResponse? _currentStep;
  bool _isLoading = false;
  String? _loadingActionId;
  String? _error;
  bool _autoAdvancing = false;

  /// Debug log tag scoped to the configured [ThunderIDConfig.vendor] rather than a hardcoded
  /// brand literal, since a consuming app may white-label the SDK.
  String get _logTag => '[${ThunderIDProvider.of(context).widget.config.vendor}SignIn]';

  @override
  void initState() {
    super.initState();
    Future.microtask(_initFlow);
  }

  Future<void> _initFlow() async {
    setState(() => _isLoading = true);
    try {
      final state = ThunderIDProvider.of(context);
      final response = await state.client.signIn(
        payload: const EmbeddedSignInPayload(actionId: 'init'),
        request: EmbeddedFlowRequestConfig(applicationId: widget.applicationId),
      );
      if (kDebugMode) {
        final inputList = (response.data?['inputs'] as List?) ?? const [];
        final actionList = (response.data?['actions'] as List?) ?? const [];
        debugPrint('$_logTag init response flowStatus=${response.flowStatus} inputs=$inputList actions=$actionList');
      }
      await _finishResponse(response, actionId: 'init', flowId: response.flowId ?? '');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      widget.onError?.call();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit(String actionId, Map<String, String> inputs) async {
    final flowId = _currentStep?.flowId;
    debugPrint('$_logTag _submit flowId=$flowId actionId=$actionId inputs=${inputs.keys.toList()}');
    if (flowId == null) return;
    setState(() { _isLoading = true; _loadingActionId = actionId; });
    try {
      final response = await ThunderIDProvider.of(context).client.signIn(
        payload: EmbeddedSignInPayload(flowId: flowId, actionId: actionId, inputs: inputs, challengeToken: _currentStep?.challengeToken),
        request: EmbeddedFlowRequestConfig(applicationId: widget.applicationId),
      );
      await _finishResponse(response, actionId: actionId, flowId: flowId);
    } catch (e, st) {
      debugPrint('$_logTag _submit error: $e\n$st');
      if (mounted) setState(() => _error = e.toString());
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
            request: EmbeddedFlowRequestConfig(applicationId: widget.applicationId),
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
        if (mounted) setState(() => _error = response.failureReason ?? 'Authentication failed');
        widget.onError?.call();
      } else {
        if (mounted) setState(() { _currentStep = response; _error = null; });
      }
    } finally {
      _autoAdvancing = false;
    }
  }

  /// Runs the native WebAuthn ceremony (`performPasskeyAuthentication` for a
  /// `passkeyChallenge`, `performPasskeyRegistration` for `passkeyCreationOptions`) and
  /// resubmits the flow with the resulting flat inputs, without requiring another user tap.
  /// Loops in case the resubmit itself returns another passkey ceremony step. Returns `null`
  /// (after setting [_error]) on ceremony failure, so the caller can bail out of [_submit].
  Future<EmbeddedFlowResponse?> _performPasskeyCeremony(EmbeddedFlowResponse response) async {
    final state = ThunderIDProvider.of(context);
    var current = response;
    while (true) {
      final passkeyChallenge = current.additionalData?['passkeyChallenge'] as String?;
      final passkeyCreationOptions = current.additionalData?['passkeyCreationOptions'] as String?;
      if (passkeyChallenge == null && passkeyCreationOptions == null) return current;

      final flowId = current.flowId;
      if (flowId == null) return current;

      try {
        final inputs = passkeyChallenge != null
            ? await state.client.performPasskeyAuthentication(requestOptionsJson: passkeyChallenge)
            : await state.client.performPasskeyRegistration(creationOptionsJson: passkeyCreationOptions!);
        current = await state.client.signIn(
          payload: EmbeddedSignInPayload(
            flowId: flowId,
            actionId: '',
            inputs: inputs,
            challengeToken: current.challengeToken,
          ),
          request: EmbeddedFlowRequestConfig(applicationId: widget.applicationId),
        );
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
        widget.onError?.call();
        return null;
      }
    }
  }

  bool _shouldAutoAdvance(EmbeddedFlowResponse response) {
    if (_autoAdvancing) return false;
    if (response.flowStatus != FlowStatus.promptOnly) return false;
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
          submit: _submit,
        ),
      );
}
