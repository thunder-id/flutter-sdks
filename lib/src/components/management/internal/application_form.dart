// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/management/application.dart';
import '../identity_candidate.dart';
import 'admin_context.dart';
import 'admin_inputs.dart';

// Package-internal (not exported): the pieces ApplicationCreate and ApplicationDetails share.

/// The application types the server accepts, in the order they are offered.
const List<String> applicationTypes = ['browser', 'mobile', 'fullstack', 'm2m', 'mcp', 'custom'];

/// The grant types the application components offer.
const List<String> applicationGrantTypes = [
  OAuth2GrantTypes.authorizationCode,
  OAuth2GrantTypes.refreshToken,
  OAuth2GrantTypes.clientCredentials,
];

/// [applicationTypes] with translated labels.
List<AdminSelectOption> applicationTypeOptions(AdminContext ac) => [
      for (final type in applicationTypes) AdminSelectOption(value: type, label: ac.t('admin.applications.types.$type')),
    ];

/// [applicationGrantTypes] with translated labels.
List<AdminSelectOption> applicationGrantTypeOptions(AdminContext ac) => [
      for (final grant in applicationGrantTypes)
        AdminSelectOption(value: grant, label: ac.t('admin.applications.grant_types.$grant')),
    ];

/// The translated label of an application type, or the type itself when it has none.
String applicationTypeLabel(AdminContext ac, String? type) {
  if (type == null || type.isEmpty) return '';
  return applicationTypes.contains(type) ? ac.t('admin.applications.types.$type') : type;
}

/// The translated label of an application status such as `ACTIVE`, or the status itself.
String applicationStatusLabel(AdminContext ac, String? status) {
  if (status == null || status.isEmpty) return '';
  final key = status.toLowerCase();
  return key == 'active' || key == 'suspended' ? ac.t('admin.applications.status.$key') : status;
}

/// Splits redirect URIs typed one per line (commas also separate), dropping blanks.
List<String> parseRedirectUris(String text) =>
    text.split(RegExp(r'[\n,]')).map((uri) => uri.trim()).where((uri) => uri.isNotEmpty).toList(growable: false);

/// Whether every one of [uris] is an absolute URL with a scheme and a host or a path, such as
/// `https://app.example.com/callback` or `com.example.app:/callback`.
bool areValidRedirectUris(List<String> uris) => uris.every((uri) {
      final parsed = Uri.tryParse(uri);
      return parsed != null && parsed.hasScheme && (parsed.host.isNotEmpty || parsed.path.isNotEmpty);
    });

/// Whether an OAuth setup can be saved: at least one grant type, a redirect URI for the
/// authorization code grant, valid redirect URIs, and no client credentials for a public client.
bool isValidOAuthSetup({
  required List<String> grantTypes,
  required List<String> redirectUris,
  required bool publicClient,
}) =>
    grantTypes.isNotEmpty &&
    (!grantTypes.contains(OAuth2GrantTypes.authorizationCode) || redirectUris.isNotEmpty) &&
    areValidRedirectUris(redirectUris) &&
    !(publicClient && grantTypes.contains(OAuth2GrantTypes.clientCredentials));

/// A labelled checkbox at least 44 logical pixels tall.
class AdminCheckbox extends StatelessWidget {
  final AdminContext ac;
  final String label;
  final String identifier;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AdminCheckbox({
    super.key,
    required this.ac,
    required this.label,
    required this.identifier,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: identifier,
        child: InkWell(
          key: Key(identifier),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  activeColor: ac.colors.primary,
                  onChanged: onChanged == null ? null : (next) => onChanged!(next ?? false),
                ),
                Flexible(child: Text(label, style: TextStyle(color: ac.colors.text))),
              ],
            ),
          ),
        ),
      );
}

/// A group of [AdminCheckbox]es under a [label], one per option.
class AdminCheckboxGroup extends StatelessWidget {
  final AdminContext ac;
  final String label;
  final String identifier;
  final List<AdminSelectOption> options;
  final List<String> selected;
  final void Function(String value, bool selected)? onChanged;

  const AdminCheckboxGroup({
    super.key,
    required this.ac,
    required this.label,
    required this.identifier,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          container: true,
          label: label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: ac.colors.textSecondary, fontSize: 13)),
              for (final option in options)
                AdminCheckbox(
                  ac: ac,
                  label: option.label,
                  identifier: '$identifier-${option.value}',
                  value: selected.contains(option.value),
                  onChanged: onChanged == null ? null : (value) => onChanged!(option.value, value),
                ),
            ],
          ),
        ),
      );
}

/// A newly issued secret, shown once with a copy action and a done action that dismisses it.
class AdminSecretReveal extends StatelessWidget {
  final AdminContext ac;
  final String block;
  final String secret;
  final VoidCallback onDone;

  const AdminSecretReveal({
    super.key,
    required this.ac,
    required this.block,
    required this.secret,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ac.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: ac.t('admin.applications.secret.title'),
      child: Container(
        key: Key('thunderid-admin-$block-secret'),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ac.t('admin.applications.secret.title'),
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(ac.t('admin.applications.secret.notice'), style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 8),
            SelectableText(secret, style: TextStyle(color: colors.text, fontFamily: 'monospace')),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                AdminButton(
                  ac: ac,
                  label: ac.t('elements.display.copyable_text.copy'),
                  identifier: 'thunderid-action-$block-secret-copy',
                  variant: AdminButtonVariant.text,
                  onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: secret))),
                ),
                AdminButton(
                  ac: ac,
                  label: ac.t('admin.applications.secret.done'),
                  identifier: 'thunderid-action-$block-secret-done',
                  onPressed: onDone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
