// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../../models/management/sharing_policy.dart';
import '../identity_candidate.dart';
import '../internal/admin_context.dart';
import '../internal/admin_inputs.dart';
import '../internal/admin_parts.dart';
import '../internal/application_form.dart';

// Package-internal (not exported): the pieces of the built-in sharing policies UI.

List<String> _ids(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
      ]
    : const [];

List<Map<Object?, Object?>> _units(Map<String, dynamic>? selection) {
  final units = selection?['units'];
  return units is List
      ? [
          for (final unit in units)
            if (unit is Map) unit,
        ]
      : const [];
}

/// A sharing policy's reach in translated words, as the server records it.
String describeSharingScope(SharingPolicy policy, AdminContext ac) {
  String excluding(String scope, List<String> ids) =>
      ids.isEmpty ? scope : ac.t('admin.sharing.scope.excluding', {'scope': scope, 'units': ids.join(', ')});

  final parts = <String>[];
  final all = policy.allUnits;
  if (all != null) parts.add(excluding(ac.t('admin.sharing.scope.all_units'), _ids(all['excludedOuIds'])));
  final children = policy.childUnits;
  if (children != null) {
    if (children['mode'] == 'selected') {
      final units = [
        for (final unit in _units(children))
          unit['reach'] == 'subtree'
              ? ac.t('admin.sharing.scope.subtree', {'unit': '${unit['ouId']}'})
              : '${unit['ouId']}',
      ];
      parts.add(ac.t('admin.sharing.scope.selected_children', {'units': units.join(', ')}));
    } else {
      parts.add(excluding(ac.t('admin.sharing.scope.all_children'), _ids(children['excludedOuIds'])));
    }
  }
  final roots = policy.otherTreeRoots;
  if (roots != null) {
    if (roots['mode'] == 'selected') {
      final units = [for (final unit in _units(roots)) '${unit['ouId']}'];
      parts.add(ac.t('admin.sharing.scope.selected_other_roots', {'units': units.join(', ')}));
    } else {
      parts.add(excluding(ac.t('admin.sharing.scope.all_other_roots'), _ids(roots['excludedOuIds'])));
    }
  }
  return parts.isEmpty ? ac.t('admin.sharing.scope.none') : parts.join(' · ');
}

/// The reach the sharing policy form submits.
enum SharingDraftMode { everywhere, allChildren, selected }

/// What the sharing policy form edits: the reach beneath the issuer, or across every unit when an
/// existing policy already says so.
class SharingPolicyDraft {
  SharingDraftMode mode;
  String units;
  bool subtree;
  String excluded;

  SharingPolicyDraft._(this.mode, this.units, this.subtree, this.excluded);

  factory SharingPolicyDraft.of(SharingPolicy? policy) {
    final children = policy?.childUnits;
    final mode = policy?.allUnits != null
        ? SharingDraftMode.everywhere
        : children?['mode'] == 'selected'
        ? SharingDraftMode.selected
        : SharingDraftMode.allChildren;
    final units = _units(children);
    return SharingPolicyDraft._(
      mode,
      [for (final unit in units) '${unit['ouId']}'].join(', '),
      units.any((unit) => unit['reach'] == 'subtree'),
      (policy?.allUnits != null ? _ids(policy!.allUnits!['excludedOuIds']) : _ids(children?['excludedOuIds'])).join(
        ', ',
      ),
    );
  }

  static List<String> ids(String text) => [
    for (final part in text.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  bool get isValid => mode != SharingDraftMode.selected || ids(units).isNotEmpty;

  Map<String, dynamic>? get childUnits => switch (mode) {
    SharingDraftMode.everywhere => null,
    SharingDraftMode.allChildren => {'mode': 'all', if (ids(excluded).isNotEmpty) 'excludedOuIds': ids(excluded)},
    SharingDraftMode.selected => {
      'mode': 'selected',
      'units': [
        for (final id in ids(units)) {'ouId': id, 'reach': subtree ? 'subtree' : 'unit'},
      ],
    },
  };

  Map<String, dynamic>? get allUnits =>
      mode == SharingDraftMode.everywhere ? {if (ids(excluded).isNotEmpty) 'excludedOuIds': ids(excluded)} : null;
}

/// The create and edit form of the built-in sharing policies UI.
class SharingPolicyForm extends StatefulWidget {
  final AdminContext ac;
  final SharingPolicy? policy;
  final bool isSubmitting;
  final VoidCallback onCancel;
  final ValueChanged<SharingPolicyDraft> onSubmit;

  const SharingPolicyForm({
    super.key,
    required this.ac,
    required this.policy,
    required this.isSubmitting,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  State<SharingPolicyForm> createState() => _SharingPolicyFormState();
}

class _SharingPolicyFormState extends State<SharingPolicyForm> {
  late final SharingPolicyDraft _draft = SharingPolicyDraft.of(widget.policy);

  @override
  Widget build(BuildContext context) {
    final ac = widget.ac;
    final draft = _draft;
    // Every unit is offered only for a policy that already reaches every unit: a new one cannot.
    final modes = [
      if (widget.policy?.allUnits != null)
        AdminSelectOption(value: SharingDraftMode.everywhere.name, label: ac.t('admin.sharing.scope.all_units')),
      AdminSelectOption(value: SharingDraftMode.allChildren.name, label: ac.t('admin.sharing.scope.all_children')),
      AdminSelectOption(value: SharingDraftMode.selected.name, label: ac.t('admin.sharing.fields.mode_selected')),
    ];
    return Column(
      key: const Key('thunderid-admin-sharing-policies-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDropdown(
          ac: ac,
          label: ac.t('admin.sharing.fields.mode'),
          identifier: 'thunderid-field-sharing-policies-mode',
          value: draft.mode.name,
          options: modes,
          onChanged: (value) => setState(
            () => draft.mode = SharingDraftMode.values.firstWhere(
              (mode) => mode.name == value,
              orElse: () => SharingDraftMode.allChildren,
            ),
          ),
        ),
        if (draft.mode == SharingDraftMode.selected) ...[
          AdminTextField(
            ac: ac,
            label: ac.t('admin.sharing.fields.units'),
            identifier: 'thunderid-field-sharing-policies-units',
            required: true,
            initialValue: draft.units,
            hint: ac.t('admin.sharing.fields.ids_hint'),
            onChanged: (value) => setState(() => draft.units = value),
          ),
          AdminCheckbox(
            ac: ac,
            label: ac.t('admin.sharing.fields.subtree'),
            identifier: 'thunderid-field-sharing-policies-subtree',
            value: draft.subtree,
            onChanged: (value) => setState(() => draft.subtree = value),
          ),
        ] else
          AdminTextField(
            ac: ac,
            label: ac.t('admin.sharing.fields.excluded'),
            identifier: 'thunderid-field-sharing-policies-excluded',
            initialValue: draft.excluded,
            hint: ac.t('admin.sharing.fields.ids_hint'),
            onChanged: (value) => setState(() => draft.excluded = value),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            AdminButton(
              ac: ac,
              label: ac.t('admin.common.actions.cancel'),
              identifier: 'thunderid-action-sharing-policies-cancel',
              variant: AdminButtonVariant.text,
              onPressed: widget.isSubmitting ? null : widget.onCancel,
            ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.sharing.save'),
              identifier: 'thunderid-action-sharing-policies-save',
              isLoading: widget.isSubmitting,
              onPressed: draft.isValid && !widget.isSubmitting ? () => widget.onSubmit(draft) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// The resolved overlay rules for one organization unit, read only.
class SharingOverlayPanel extends StatelessWidget {
  final AdminContext ac;
  final ResolvedOverlay overlay;

  const SharingOverlayPanel({super.key, required this.ac, required this.overlay});

  @override
  Widget build(BuildContext context) {
    final rules = overlay.rules.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    String ruleText(OverlayRule rule) {
      final access = ac.t(rule.editable == true ? 'admin.sharing.overlay.editable' : 'admin.sharing.overlay.locked');
      final values = rule.allowedValues ?? rule.value ?? const <String>[];
      return values.isEmpty ? access : '$access · ${values.join(', ')}';
    }

    return AdminPanel(
      key: const Key('thunderid-admin-sharing-policies-overlay'),
      ac: ac,
      title: ac.t('admin.sharing.overlay.title', {'unit': overlay.ouId ?? ''}),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminDetailList(
            ac: ac,
            items: [
              (
                ac.t('admin.sharing.overlay.visibility'),
                Text(ac.t(overlay.visible == false ? 'admin.sharing.overlay.hidden' : 'admin.sharing.overlay.visible')),
              ),
              (
                ac.t('admin.sharing.overlay.ownership'),
                Text(ac.t(overlay.isOwned == true ? 'admin.sharing.overlay.owned' : 'admin.sharing.overlay.shared')),
              ),
            ],
          ),
          if (rules.isEmpty)
            AdminMuted(ac: ac, text: ac.t('admin.sharing.overlay.no_rules'))
          else
            AdminDetailList(ac: ac, items: [for (final rule in rules) (rule.key, Text(ruleText(rule.value)))]),
        ],
      ),
    );
  }
}
