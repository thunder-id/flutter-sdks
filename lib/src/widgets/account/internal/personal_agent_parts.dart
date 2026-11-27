// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../models/management/access_status.dart';
import '../../../models/management/agent.dart';
import '../../../models/personal_agent.dart';
import '../../admin/identity_candidate.dart';
import '../../admin/internal/account_lifecycle_parts.dart';
import '../../admin/internal/admin_context.dart';
import '../../admin/internal/admin_inputs.dart';
import '../../admin/internal/admin_parts.dart';
import '../../admin/internal/application_form.dart';

// Package-internal (not exported): the pieces of the personal agent widgets that read the agent.

/// The parties whose suspension the details explain, in the order they are shown.
const List<String> _explainedParties = [
  SuspensionAppliedBy.owner,
  SuspensionAppliedBy.organization,
  SuspensionAppliedBy.cascade,
];

/// One translated notice per suspension in force, saying who placed it.
List<String> personalAgentSuspensionNotices(AdminContext ac, Agent agent) {
  final parties = agent.status?.suspendedBy ?? const <String>[];
  return [
    for (final party in _explainedParties)
      if (parties.contains(party)) ac.t('user.agents.suspension.$party'),
  ];
}

/// The translated label of a grant type, or the grant type itself when it has none.
String personalAgentGrantTypeLabel(AdminContext ac, String grantType) {
  final key = PersonalAgentGrantTypes.labelKeys[grantType];
  return key == null ? grantType : ac.t(key);
}

/// The overview rows: the status, the client ID, the grant types and the redirect URIs.
List<(String, String)> personalAgentOverview(AdminContext ac, Agent agent) {
  final none = ac.t('user.agents.details.none');
  final oauth = agent.oauthConfig;
  final grantTypes = [for (final grantType in oauth?.grantTypes ?? const <String>[]) personalAgentGrantTypeLabel(ac, grantType)];
  final redirectUris = oauth?.redirectUris ?? const <String>[];
  final status = agent.status?.value;
  return [
    (ac.t('user.agents.list.columns.status'), status == null ? none : accessStatusLabel(ac, status)),
    (ac.t('user.agents.details.client_id'), agent.clientId ?? none),
    (ac.t('user.agents.details.grant_types'), grantTypes.isEmpty ? none : grantTypes.join(', ')),
    (ac.t('user.agents.details.redirect_uris'), redirectUris.isEmpty ? none : redirectUris.join('\n')),
  ];
}

/// The agent's attributes sorted by name, each value as text: a string as it is, and any other
/// value as JSON.
List<(String, String)> personalAgentAttributes(Agent agent) {
  final names = agent.attributes.keys.toList()..sort();
  return [
    for (final name in names)
      (
        name,
        switch (agent.attributes[name]) {
          final String text => text,
          null => '',
          final value => jsonEncode(value),
        },
      ),
  ];
}

/// The details' header: the name and description, with the actions kept beside them on the right.
class PersonalAgentHeader extends StatelessWidget {
  final AdminContext ac;
  final String title;
  final String? description;
  final List<Widget> actions;

  const PersonalAgentHeader({
    super.key,
    required this.ac,
    required this.title,
    required this.actions,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final description = this.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ac.colors.text),
                  ),
                ),
                if (description != null && description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(description, style: TextStyle(color: ac.colors.textSecondary)),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}

/// The confirmation a suspension or a delete asks for, from the details' actions menu.
enum PersonalAgentConfirmation { suspend, delete }

/// The details' actions menu: the owner's suspension and the delete.
class PersonalAgentActionMenu extends StatelessWidget {
  final AdminContext ac;
  final bool isBusy;
  final VoidCallback? onUnsuspend;
  final VoidCallback? onSuspend;
  final VoidCallback? onDelete;

  const PersonalAgentActionMenu({
    super.key,
    required this.ac,
    required this.isBusy,
    this.onUnsuspend,
    this.onSuspend,
    this.onDelete,
  });

  static const String _block = 'personal-agent-details';

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return Semantics(
        label: ac.t('admin.common.loading'),
        child: ExcludeSemantics(
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: ac.colors.primary),
              ),
            ),
          ),
        ),
      );
    }
    final unsuspend = onUnsuspend;
    final suspend = onSuspend;
    final delete = onDelete;
    return Semantics(
      identifier: 'thunderid-action-$_block-menu',
      child: PopupMenuButton<VoidCallback>(
        key: const Key('thunderid-action-$_block-menu'),
        tooltip: ac.t('user.agents.actions.menu'),
        icon: Icon(Icons.more_vert, color: ac.colors.text),
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          if (unsuspend != null) _item('unsuspend', ac.t('user.agents.unsuspend.action'), Icons.play_circle_outline, unsuspend),
          if (suspend != null) _item('suspend', ac.t('user.agents.suspend.action'), Icons.pause_circle_outline, suspend),
          if (delete != null && (unsuspend != null || suspend != null)) const PopupMenuDivider(),
          if (delete != null) _item('delete', ac.t('user.agents.delete.action'), Icons.delete_outline, delete, danger: true),
        ],
      ),
    );
  }

  PopupMenuItem<VoidCallback> _item(
    String name,
    String label,
    IconData icon,
    VoidCallback action, {
    bool danger = false,
  }) {
    final color = danger ? ac.colors.error : ac.colors.text;
    return PopupMenuItem<VoidCallback>(
      key: Key('thunderid-action-$_block-$name'),
      value: action,
      child: Semantics(
        identifier: 'thunderid-action-$_block-$name',
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

/// The inline confirmation a suspension or a delete asks for, in place of the header's actions.
class PersonalAgentConfirmBar extends StatelessWidget {
  final AdminContext ac;
  final PersonalAgentConfirmation confirmation;
  final String name;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const PersonalAgentConfirmBar({
    super.key,
    required this.ac,
    required this.confirmation,
    required this.name,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final text = ac.t('user.agents.${confirmation.name}.confirm', {'name': name});
    final identifier = 'thunderid-action-personal-agent-details-${confirmation.name}';
    return Semantics(
      container: true,
      label: text,
      liveRegion: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(text, style: TextStyle(color: ac.colors.text)),
          AdminButton(
            ac: ac,
            label: ac.t('admin.common.actions.cancel'),
            identifier: '$identifier-cancel',
            variant: AdminButtonVariant.text,
            onPressed: onCancel,
          ),
          AdminButton(
            ac: ac,
            label: ac.t('admin.common.actions.confirm'),
            identifier: '$identifier-confirm',
            variant: AdminButtonVariant.danger,
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

/// The edit form: the name, the agent's other text attributes, the description, the redirect URIs
/// and the grant types.
class PersonalAgentEditForm extends StatelessWidget {
  final AdminContext ac;
  final PersonalAgentFormValues values;
  final ValueChanged<PersonalAgentFormValues> onChanged;
  final bool isUpdating;
  final VoidCallback onCancel;
  final ValueChanged<PersonalAgentFormValues> onSave;

  const PersonalAgentEditForm({
    super.key,
    required this.ac,
    required this.values,
    required this.onChanged,
    required this.isUpdating,
    required this.onCancel,
    required this.onSave,
  });

  static const String _block = 'personal-agent-details';

  @override
  Widget build(BuildContext context) {
    final attributeNames = values.attributes.keys.toList()..sort();
    return AdminPanel(
      ac: ac,
      title: ac.t('user.agents.edit.title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminTextField(
            ac: ac,
            label: ac.t('user.agents.fields.name'),
            identifier: 'thunderid-field-$_block-name',
            initialValue: values.name,
            required: true,
            onChanged: (name) => onChanged(values.copyWith(name: name)),
          ),
          for (final attribute in attributeNames)
            AdminTextField(
              ac: ac,
              label: attribute,
              identifier: 'thunderid-field-$_block-attribute-$attribute',
              initialValue: values.attributes[attribute] ?? '',
              onChanged: (text) => onChanged(values.copyWith(attributes: {...values.attributes, attribute: text})),
            ),
          AdminTextField(
            ac: ac,
            label: ac.t('user.agents.fields.description'),
            identifier: 'thunderid-field-$_block-description',
            initialValue: values.description,
            onChanged: (description) => onChanged(values.copyWith(description: description)),
          ),
          AdminTextField(
            ac: ac,
            label: ac.t('user.agents.details.redirect_uris'),
            identifier: 'thunderid-field-$_block-redirectUris',
            initialValue: values.redirectUris,
            maxLines: 4,
            onChanged: (uris) => onChanged(values.copyWith(redirectUris: uris)),
          ),
          AdminMuted(ac: ac, text: ac.t('user.agents.fields.redirect_uris_hint')),
          AdminCheckboxGroup(
            ac: ac,
            label: ac.t('user.agents.details.grant_types'),
            identifier: 'thunderid-field-$_block-grantTypes',
            options: [
              for (final grantType in PersonalAgentGrantTypes.all)
                AdminSelectOption(value: grantType, label: personalAgentGrantTypeLabel(ac, grantType)),
            ],
            selected: values.grantTypes,
            onChanged: (grantType, selected) => onChanged(
              values.copyWith(
                grantTypes: [
                  for (final current in values.grantTypes)
                    if (current != grantType) current,
                  if (selected) grantType,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              AdminButton(
                ac: ac,
                label: ac.t('admin.common.actions.cancel'),
                identifier: 'thunderid-action-$_block-edit-cancel',
                variant: AdminButtonVariant.text,
                onPressed: isUpdating ? null : onCancel,
              ),
              AdminButton(
                ac: ac,
                label: ac.t('user.agents.edit.save'),
                identifier: 'thunderid-action-$_block-edit-save',
                isLoading: isUpdating,
                onPressed: values.isValid ? () => onSave(values) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
