// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../models/flow_models.dart';
import '../models/token_exchange_config.dart';
import 'federated_redirect.dart';
import 'flow_form.dart';
import 'thunderid_provider.dart';

/// Full registration form driving the REGISTRATION flow (spec §8.4 Presentation).
class SignUp extends StatelessWidget {
  final String applicationId;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;

  const SignUp({super.key, required this.applicationId, this.onSuccess, this.onError});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseSignUp(
      applicationId: applicationId,
      onSuccess: onSuccess,
      onError: onError,
      builder: (ctx, flowState) => FlowForm(
        applicationId: applicationId,
        currentStep: flowState.currentStep,
        isLoading: flowState.isLoading,
        loadingActionId: flowState.loadingActionId,
        error: flowState.error,
        submit: flowState.submit,
        submitLabel: state.i18n.resolve('signUp.submit'),
      ),
    );
  }
}

class SignUpState {
  final EmbeddedFlowResponse? currentStep;
  final bool isLoading;
  final String? loadingActionId;
  final String? error;
  final Future<void> Function(String actionId, Map<String, String> inputs) submit;

  const SignUpState({
    required this.currentStep,
    required this.isLoading,
    required this.error,
    required this.submit,
    this.loadingActionId,
  });
}

/// Unstyled base variant (spec §8.3).
class BaseSignUp extends StatefulWidget {
  final String applicationId;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, SignUpState state) builder;

  const BaseSignUp({
    super.key,
    required this.applicationId,
    required this.builder,
    this.onSuccess,
    this.onError,
  });

  @override
  State<BaseSignUp> createState() => _BaseSignUpState();
}

class _BaseSignUpState extends State<BaseSignUp> {
  EmbeddedFlowResponse? _currentStep;
  bool _isLoading = true;
  String? _loadingActionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initFlow);
  }

  Future<void> _initFlow() async {
    setState(() => _isLoading = true);
    try {
      final state = ThunderIDProvider.of(context);
      final response = await state.client.signUp(
        payload: const EmbeddedSignInPayload(actionId: 'init'),
        request: EmbeddedFlowRequestConfig(
          applicationId: widget.applicationId,
          flowType: FlowType.registration,
        ),
      );
      await _finishResponse(response, actionId: 'init', flowId: response.flowId ?? '');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit(String actionId, Map<String, String> inputs) async {
    final flowId = _currentStep?.flowId;
    if (flowId == null) return;
    setState(() { _isLoading = true; _loadingActionId = actionId; });
    try {
      final state = ThunderIDProvider.of(context);
      final response = await state.client.signUp(
        payload: EmbeddedSignInPayload(flowId: flowId, actionId: actionId, inputs: inputs, challengeToken: _currentStep?.challengeToken),
        request: EmbeddedFlowRequestConfig(
          applicationId: widget.applicationId,
          flowType: FlowType.registration,
        ),
      );
      await _finishResponse(response, actionId: actionId, flowId: flowId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      widget.onError?.call();
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingActionId = null; });
    }
  }

  /// Shared response handling for [_initFlow] and [_submit]: follows a `REDIRECTION` step (a
  /// federated sign-up, e.g. ahead of an account-linking prompt), then applies the
  /// completion/error/incomplete state.
  Future<void> _finishResponse(
    EmbeddedFlowResponse initialResponse, {
    required String actionId,
    required String flowId,
  }) async {
    final state = ThunderIDProvider.of(context);
    final response = await followFederatedRedirect(
      state.client,
      initialResponse,
      actionId: actionId,
      applicationId: widget.applicationId,
      flowId: flowId,
      challengeToken: _currentStep?.challengeToken,
    );
    // User dismissed the browser without completing sign-up — reset silently.
    if (response == null) return;

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
      widget.onSuccess?.call();
    } else if (response.flowStatus == FlowStatus.error) {
      if (mounted) setState(() => _error = response.failureReason ?? 'Registration failed');
      widget.onError?.call();
    } else {
      if (mounted) setState(() { _currentStep = response; _error = null; });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        SignUpState(
          currentStep: _currentStep,
          isLoading: _isLoading,
          loadingActionId: _loadingActionId,
          error: _error,
          submit: _submit,
        ),
      );
}
