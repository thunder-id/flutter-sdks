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

/// Avatar chip that opens a menu with profile and sign-out actions (spec §8.4 Presentation).
class UserDropdown extends StatelessWidget {
  final VoidCallback? onProfileTap;
  final VoidCallback? onSignOutComplete;

  const UserDropdown({super.key, this.onProfileTap, this.onSignOutComplete});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return BaseUserDropdown(
      onProfileTap: onProfileTap,
      onSignOutComplete: onSignOutComplete,
      builder: (ctx, user, isOpen, toggle, signOut) => GestureDetector(
        onTap: toggle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Semantics(
              label: user?.displayName ?? state.i18n.resolve('user.anonymous'),
              button: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    _initials(user),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            if (isOpen)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onProfileTap != null)
                    GestureDetector(
                      onTap: onProfileTap,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: const Text('Profile'),
                      ),
                    ),
                  GestureDetector(
                    onTap: signOut,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Text(state.i18n.resolve('signOut.button')),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _initials(User? user) {
    final name = user?.displayName ?? user?.username ?? user?.email ?? '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

/// Unstyled base variant (spec §8.3).
class BaseUserDropdown extends StatefulWidget {
  final VoidCallback? onProfileTap;
  final VoidCallback? onSignOutComplete;
  final Widget Function(
    BuildContext context,
    User? user,
    bool isOpen,
    VoidCallback toggle,
    VoidCallback signOut,
  ) builder;

  const BaseUserDropdown({
    super.key,
    required this.builder,
    this.onProfileTap,
    this.onSignOutComplete,
  });

  @override
  State<BaseUserDropdown> createState() => _BaseUserDropdownState();
}

class _BaseUserDropdownState extends State<BaseUserDropdown> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return widget.builder(
      context,
      state.user,
      _isOpen,
      () => setState(() => _isOpen = !_isOpen),
      () async {
        await state.client.signOut();
        await state.refresh();
        widget.onSignOutComplete?.call();
      },
    );
  }
}
