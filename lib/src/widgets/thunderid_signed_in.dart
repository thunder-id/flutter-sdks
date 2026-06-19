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

/// Renders [child] only when the user is authenticated. Renders [fallback] (or
/// nothing) otherwise (spec §8.4 Control/Guard).
class SignedIn extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const SignedIn({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    if (state.isSignedIn) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
