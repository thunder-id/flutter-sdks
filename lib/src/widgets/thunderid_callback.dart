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
import '../models/user.dart';

/// Handles the OAuth2 redirect callback URL (spec §8.4 Auth Flow).
///
/// Use this widget at the route your app receives the deep-link callback on
/// after a redirect-based sign-in. Pass the full callback URL including the
/// `code` query parameter.
///
/// ```dart
/// Callback(
///   url: callbackUrl,
///   onSuccess: (user) => Navigator.pushReplacementNamed(context, '/home'),
///   onError: (e) => Navigator.pushReplacementNamed(context, '/signin'),
/// )
/// ```
class Callback extends StatelessWidget {
  final String url;
  final void Function(User user)? onSuccess;
  final void Function(Object error)? onError;
  final Widget? loadingIndicator;

  const Callback({
    super.key,
    required this.url,
    this.onSuccess,
    this.onError,
    this.loadingIndicator,
  });

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseCallback(
      url: url,
      onSuccess: onSuccess,
      onError: onError,
      builder: (ctx, isLoading, error) {
        if (error != null) {
          return Text(state.i18n.resolve('callback.error'));
        }
        return loadingIndicator ??
            Center(child: Text(state.i18n.resolve('callback.loading')));
      },
    );
  }
}

/// Unstyled base variant (spec §8.2).
class BaseCallback extends StatefulWidget {
  final String url;
  final void Function(User user)? onSuccess;
  final void Function(Object error)? onError;
  final Widget Function(BuildContext context, bool isLoading, Object? error) builder;

  const BaseCallback({
    super.key,
    required this.url,
    required this.builder,
    this.onSuccess,
    this.onError,
  });

  @override
  State<BaseCallback> createState() => _BaseCallbackState();
}

class _BaseCallbackState extends State<BaseCallback> {
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _exchange();
  }

  Future<void> _exchange() async {
    try {
      final state = ThunderIDProvider.of(context);
      final user = await state.client.handleRedirectCallback(widget.url);
      await state.refresh();
      widget.onSuccess?.call(user);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      widget.onError?.call(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _isLoading, _error);
}
