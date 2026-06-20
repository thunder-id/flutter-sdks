/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import 'package:flutter/widgets.dart';
import 'thunderid_provider.dart';
import 'flow_form.dart';
import '../models/flow_models.dart';
import '../models/token_exchange_config.dart';

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
        error: flowState.error,
        submit: flowState.submit,
        submitLabel: state.i18n.resolve('signUp.submit'),
      ),
    );
  }
}

class _FlowState {
  final EmbeddedFlowResponse? currentStep;
  final bool isLoading;
  final String? error;
  final Future<void> Function(String actionId, Map<String, String> inputs) submit;

  const _FlowState({
    required this.currentStep,
    required this.isLoading,
    required this.error,
    required this.submit,
  });
}

/// Unstyled base variant (spec §8.3).
class BaseSignUp extends StatefulWidget {
  final String applicationId;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, _FlowState state) builder;

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
        payload: EmbeddedSignInPayload(actionId: 'init'),
        request: EmbeddedFlowRequestConfig(
          applicationId: widget.applicationId,
          flowType: FlowType.registration,
        ),
      );
      if (mounted) setState(() { _currentStep = response; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit(String actionId, Map<String, String> inputs) async {
    final flowId = _currentStep?.flowId;
    if (flowId == null) return;
    setState(() => _isLoading = true);
    try {
      final state = ThunderIDProvider.of(context);
      final response = await state.client.signUp(
        payload: EmbeddedSignInPayload(flowId: flowId, actionId: actionId, inputs: inputs, challengeToken: _currentStep?.challengeToken),
        request: EmbeddedFlowRequestConfig(
          applicationId: widget.applicationId,
          flowType: FlowType.registration,
        ),
      );
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
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      widget.onError?.call();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        _FlowState(
          currentStep: _currentStep,
          isLoading: _isLoading,
          error: _error,
          submit: _submit,
        ),
      );
}
