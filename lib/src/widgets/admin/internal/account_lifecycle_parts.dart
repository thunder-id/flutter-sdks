// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../management/account_lifecycle.dart';
import '../../../management/management_display.dart';
import '../../../models/management/access_status.dart';
import '../../../models/management/administration.dart';
import '../../../state/management_resources.dart';
import '../../../state/resource_notifiers.dart';
import '../admin_render_state.dart';
import 'admin_context.dart';
import 'admin_inputs.dart';

// Package-internal (not exported): the access status label and the account lifecycle actions
// shared by the user, agent and application details.

/// Matches the server's limit on an operator note.
const int operatorNoteMaxLength = 100;

/// The translated label of an access status value, or the value itself when this SDK does not
/// know it.
String accessStatusLabel(AdminContext ac, String status) => switch (status) {
      AccessStatusValue.active => ac.t('admin.common.status.active'),
      AccessStatusValue.locked => ac.t('admin.common.status.locked'),
      AccessStatusValue.suspended => ac.t('admin.common.status.suspended'),
      _ => status,
    };

/// The translated label of an account lifecycle action.
String accountLifecycleActionLabel(AdminContext ac, AccountLifecycleAction action) =>
    ac.t('admin.common.lifecycle.${action.name}');

/// An identity's access status as a translated chip.
class AdminAccessStatusLabel extends StatelessWidget {
  final AdminContext ac;
  final String status;

  const AdminAccessStatusLabel({super.key, required this.ac, required this.status});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ac.colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: status == AccessStatusValue.active ? ac.colors.border : ac.colors.error),
        ),
        child: Text(accessStatusLabel(ac, status), style: TextStyle(color: ac.colors.text, fontSize: 13)),
      );
}

/// One button per account lifecycle action. Suspending and unsuspending ask for confirmation
/// inline, and a suspension can take an optional operator note; unlocking is remedial and runs
/// straight away.
class AdminLifecycleButtons extends StatefulWidget {
  final AdminContext ac;

  /// The actions to offer, most expected first.
  final List<AccountLifecycleAction> actions;

  /// Name of the identity, already resolved, used in the confirmation question.
  final String name;

  /// The component's identifier block, e.g. `user-details`.
  final String block;
  final AccountLifecycleCallback onAction;
  final bool isRunning;

  /// Whether a suspension asks for an optional operator note, recorded by the flow.
  final bool collectsOperatorNote;

  const AdminLifecycleButtons({
    super.key,
    required this.ac,
    required this.actions,
    required this.name,
    required this.block,
    required this.onAction,
    this.isRunning = false,
    this.collectsOperatorNote = false,
  });

  @override
  State<AdminLifecycleButtons> createState() => _AdminLifecycleButtonsState();
}

class _AdminLifecycleButtonsState extends State<AdminLifecycleButtons> {
  AccountLifecycleAction? _confirming;
  String _operatorNote = '';

  void _close() => setState(() {
        _confirming = null;
        _operatorNote = '';
      });

  @override
  Widget build(BuildContext context) {
    final ac = widget.ac;
    final isRunning = widget.isRunning;
    final confirming = _confirming;
    final prefix = 'thunderid-action-${widget.block}';

    if (confirming != null && widget.actions.contains(confirming)) {
      final suspending = confirming == AccountLifecycleAction.suspend;
      final question = ac.t(
        suspending ? 'admin.common.lifecycle.suspend_confirm' : 'admin.common.lifecycle.unsuspend_confirm',
        {'name': widget.name},
      );
      final withNote = widget.collectsOperatorNote && suspending;
      return Semantics(
        container: true,
        label: question,
        liveRegion: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(question, style: TextStyle(color: ac.colors.text)),
            if (withNote)
              SizedBox(
                width: 240,
                child: AdminTextField(
                  ac: ac,
                  label: ac.t('admin.common.lifecycle.operator_note'),
                  identifier: 'thunderid-field-${widget.block}-operatorNote',
                  maxLength: operatorNoteMaxLength,
                  enabled: !isRunning,
                  onChanged: (value) => _operatorNote = value,
                ),
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.common.actions.cancel'),
              identifier: '$prefix-${confirming.name}-cancel',
              variant: AdminButtonVariant.text,
              onPressed: isRunning ? null : _close,
            ),
            AdminButton(
              ac: ac,
              label: accountLifecycleActionLabel(ac, confirming),
              identifier: '$prefix-${confirming.name}-confirm',
              variant: suspending ? AdminButtonVariant.danger : AdminButtonVariant.primary,
              isLoading: isRunning,
              onPressed: () {
                final note = _operatorNote.trim();
                widget.onAction(confirming, withNote && note.isNotEmpty ? note : null);
                _close();
              },
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in widget.actions)
          AdminButton(
            ac: ac,
            label: accountLifecycleActionLabel(ac, action),
            identifier: '$prefix-${action.name}',
            variant: action == AccountLifecycleAction.suspend
                ? AdminButtonVariant.dangerOutline
                : AdminButtonVariant.outline,
            isLoading: isRunning && action == AccountLifecycleAction.unlock,
            onPressed: isRunning
                ? null
                : () => action == AccountLifecycleAction.unlock
                    ? widget.onAction(action, null)
                    : setState(() => _confirming = action),
          ),
      ],
    );
  }
}

/// The account lifecycle state of a connected details component: the configured flows (read only
/// while [enabled]) and the mutation that runs an action.
class AdminLifecycleBinding {
  final AccountLifecycleSubjectKind kind;

  /// Whether the application turned the actions on.
  final bool enabled;
  final ResourceQuery<Map<String, String>> flows;
  final ResourceMutation<AccountLifecycleVariables, AccountLifecycleResult> mutation;

  AdminLifecycleBinding._(this.kind, this.enabled, this.flows, this.mutation);

  /// Creates the query and mutation through [own], so the component rebuilds on their changes
  /// and disposes them.
  factory AdminLifecycleBinding(
    ManagementResources resources,
    AccountLifecycleSubjectKind kind, {
    required bool enabled,
    required T Function<T extends ChangeNotifier>(T notifier) own,
  }) =>
      AdminLifecycleBinding._(
        kind,
        enabled,
        own(resources.accountLifecycleFlowsQuery(kind, enabled: enabled)),
        own(resources.accountLifecycleMutation(kind)),
      );

  /// The actions to offer for an identity with [status]: none while off or until the configured
  /// flows are read.
  List<AccountLifecycleAction> actions(String? status) {
    final configured = flows.data;
    return enabled && configured != null ? getAccountLifecycleActions(kind, status, configured) : const [];
  }

  bool get isRunning => mutation.isLoading;

  /// Why the last action failed, or why the configured flows could not be read, translated.
  String? error(AdminContext ac) =>
      toManagementErrorMessage(ac.t, mutation.error, 'admin.common.lifecycle.error') ??
      toManagementErrorMessage(ac.t, flows.error, 'admin.common.lifecycle.load_error');

  /// Runs an action against [subject]. `null` while the actions are off.
  AccountLifecycleCallback? handler(String subject) => enabled
      ? (action, operatorNote) => unawaited(
            mutation.mutate((subject: subject, action: action, operatorNote: operatorNote)),
          )
      : null;
}
