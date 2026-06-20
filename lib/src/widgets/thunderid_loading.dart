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

/// Renders [indicator] while the SDK is initializing or loading (spec §8.4 Control/Guard).
/// Renders [child] (or nothing) once loading completes.
class Loading extends StatelessWidget {
  final Widget? child;
  final Widget? indicator;

  const Loading({super.key, this.child, this.indicator});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    if (state.isLoading) {
      return indicator ?? const Center(child: _DefaultSpinner());
    }
    return child ?? const SizedBox.shrink();
  }
}

class _DefaultSpinner extends StatelessWidget {
  const _DefaultSpinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 24, height: 24, child: CircularProgressIndicatorStub());
}

// Stub — avoids a Material/Cupertino import at this layer.
// Replace with CircularProgressIndicator when using with Flutter Material.
class CircularProgressIndicatorStub extends StatelessWidget {
  const CircularProgressIndicatorStub();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
