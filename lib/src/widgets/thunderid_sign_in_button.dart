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

/// A pre-built sign-in button that integrates with [ThunderIDProvider].
///
/// Triggers the sign-in flow and rebuilds on authentication state changes.
/// WCAG 2.1 AA compliant: minimum 44x44 tap target, semantic label (spec §8).
class SignInButton extends StatelessWidget {
  final String label;
  final VoidCallback? onSignInComplete;
  final VoidCallback? onError;

  const SignInButton({
    super.key,
    this.label = 'Sign In',
    this.onSignInComplete,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: state.isLoading
            ? null
            : () async {
                try {
                  // Delegates to app-native flow via ThunderIDClient — no direct
                  // protocol logic here; native SDK handles OAuth2/OIDC.
                  await state.refresh();
                  onSignInComplete?.call();
                } catch (_) {
                  onError?.call();
                }
              },
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Unstyled base variant — for full customization (spec §8.2 Base* components).
class BaseSignInButton extends StatelessWidget {
  final WidgetBuilder builder;
  final VoidCallback? onSignInComplete;
  final VoidCallback? onError;

  const BaseSignInButton({
    super.key,
    required this.builder,
    this.onSignInComplete,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return GestureDetector(
      onTap: state.isLoading ? null : () async {
        try {
          await state.refresh();
          onSignInComplete?.call();
        } catch (_) {
          onError?.call();
        }
      },
      child: builder(context),
    );
  }
}
