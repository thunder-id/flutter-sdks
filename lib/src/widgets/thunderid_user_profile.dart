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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'thunderid_provider.dart';
import '../models/user_profile.dart' as model;

/// Read-only profile view built from the decoded access token.
class UserProfile extends StatelessWidget {
  final VoidCallback? onSaved;
  final VoidCallback? onError;

  const UserProfile({super.key, this.onSaved, this.onError});

  static const _labels = <String, String>{
    'sub': 'User ID',
    'username': 'Username',
    'email': 'Email',
    'displayName': 'Display Name',
    'phone': 'Phone',
  };

  String _label(String key) =>
      _labels[key] ?? key[0].toUpperCase() + key.substring(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return BaseUserProfile(
      onSaved: onSaved,
      onError: onError,
      builder: (ctx, profile, controllers, isLoading, error, save) {
        if (isLoading && profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (error != null) {
          return Text(error, style: TextStyle(color: cs.error, fontSize: 13));
        }
        if (profile == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in controllers.entries) ...[
              _ClaimRow(
                label: _label(entry.key),
                value: entry.value.text,
                labelStyle: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                valueStyle: tt.bodyMedium,
              ),
              if (entry.key != controllers.keys.last)
                Divider(height: 1, color: cs.outlineVariant),
            ],
          ],
        );
      },
    );
  }
}

class _ClaimRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  const _ClaimRow({
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: 2),
            Text(value, style: valueStyle),
          ],
        ),
      );
}

/// Unstyled base variant (spec §8.3).
class BaseUserProfile extends StatefulWidget {
  final VoidCallback? onSaved;
  final VoidCallback? onError;
  final Widget Function(
    BuildContext context,
    model.UserProfile? profile,
    Map<String, TextEditingController> controllers,
    bool isLoading,
    String? error,
    VoidCallback save,
  ) builder;

  const BaseUserProfile({
    super.key,
    required this.builder,
    this.onSaved,
    this.onError,
  });

  @override
  State<BaseUserProfile> createState() => _BaseUserProfileState();
}

class _BaseUserProfileState extends State<BaseUserProfile> {
  model.UserProfile? _profile;
  final _controllers = <String, TextEditingController>{};
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  static const _hiddenClaims = {
    'assurance', 'aud', 'exp', 'iat', 'iss', 'jti', 'nbf',
  };

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final state = ThunderIDProvider.of(context);
      final token = await state.client.getAccessToken();
      final parts = token.split('.');
      if (parts.length != 3) throw Exception('Invalid token format');
      final padded = parts[1].padRight((parts[1].length + 3) ~/ 4 * 4, '=');
      final payload = json.decode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
      final profileClaims = {
        for (final e in payload.entries)
          if (!_hiddenClaims.contains(e.key)) e.key: e.value,
      };
      final profile = model.UserProfile(id: payload['sub'] as String? ?? '', claims: profileClaims);
      for (final entry in profileClaims.entries) {
        _controllers.putIfAbsent(
            entry.key, () => TextEditingController(text: entry.value?.toString() ?? ''));
      }
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _profile, _controllers, _isLoading, _error, _save);
}
