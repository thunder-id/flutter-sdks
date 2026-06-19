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
import '../models/sign_out_options.dart';

/// Triggers sign-out on tap. Accessible per WCAG 2.1 AA (spec §8.1).
class SignOutButton extends StatelessWidget {
  final SignOutOptions? options;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;

  const SignOutButton({super.key, this.options, this.onSuccess, this.onError});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    final label = state.i18n.resolve('signOut.button');
    return BaseSignOutButton(
      options: options,
      onSuccess: onSuccess,
      onError: onError,
      builder: (ctx, isLoading) => Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: isLoading ? null : () => _signOut(ctx),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final state = ThunderIDProvider.of(context);
    try {
      await state.client.signOut(options: options);
      await state.refresh();
      onSuccess?.call();
    } catch (_) {
      onError?.call();
    }
  }
}

/// Unstyled base variant for full style customization (spec §8.2).
class BaseSignOutButton extends StatefulWidget {
  final SignOutOptions? options;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, bool isLoading) builder;

  const BaseSignOutButton({
    super.key,
    required this.builder,
    this.options,
    this.onSuccess,
    this.onError,
  });

  @override
  State<BaseSignOutButton> createState() => _BaseSignOutButtonState();
}

class _BaseSignOutButtonState extends State<BaseSignOutButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isLoading ? null : _signOut,
      child: widget.builder(context, _isLoading),
    );
  }

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    try {
      final state = ThunderIDProvider.of(context);
      await state.client.signOut(options: widget.options);
      await state.refresh();
      widget.onSuccess?.call();
    } catch (_) {
      widget.onError?.call();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
