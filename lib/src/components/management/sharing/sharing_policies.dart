// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../api/management/management_display.dart';
import '../../../models/management/management_page.dart';
import '../../../models/management/sharing_policy.dart';
import '../../../models/preferences.dart';
import '../../../state/hierarchy_resources.dart';
import '../../../state/management_resources.dart';
import '../../../state/resource_notifiers.dart';
import '../admin_render_state.dart';
import '../internal/admin_connected.dart';
import '../internal/admin_context.dart';
import '../internal/admin_inputs.dart';
import '../internal/admin_parts.dart';
import '../internal/hierarchy_support.dart';
import 'sharing_policy_parts.dart';

/// What [BaseSharingPolicies] and [SharingPolicies] hand their `builder`.
class SharingPoliciesState {
  final List<SharingPolicy> policies;
  final bool isLoading;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;
  final int limit;
  final int offset;
  final int totalResults;

  /// Shows the page that starts at the given offset. `null` when the list is not paginated.
  final ValueChanged<int>? onPageChange;

  /// How the resource appears in one organization unit, read only. `null` when none was asked for
  /// or it has not loaded.
  final ResolvedOverlay? overlay;

  /// Describes a policy's reach in translated words, as the server records it.
  final String Function(SharingPolicy policy) describe;

  /// Whether a create, update or delete is running.
  final bool isMutating;

  /// Adds a policy. `null` unless the view is editable.
  final ValueChanged<CreateSharingPolicyRequest>? onCreate;

  /// Saves a policy. `null` unless the view is editable. Never offered for a read-only policy.
  final void Function(SharingPolicy policy, UpdateSharingPolicyRequest request)? onUpdate;

  /// Deletes a policy. `null` unless the view is editable. Never offered for a read-only policy. A
  /// custom UI must ask for confirmation first.
  final ValueChanged<SharingPolicy>? onDelete;

  const SharingPoliciesState({
    required this.policies,
    required this.isLoading,
    required this.error,
    required this.limit,
    required this.offset,
    required this.totalResults,
    required this.onPageChange,
    required this.overlay,
    required this.describe,
    required this.isMutating,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
  });
}

/// Presentational sharing policies of one resource, each with its reach as the server records it.
///
/// Adding, editing and deleting appear only when their callbacks are set, never for a read-only
/// policy, and a delete asks for confirmation first. [overlay], when given, shows the resolved
/// overlay rules for one organization unit, read only.
class BaseSharingPolicies extends StatefulWidget {
  final List<SharingPolicy> policies;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ResolvedOverlay? overlay;
  final bool isMutating;
  final ValueChanged<CreateSharingPolicyRequest>? onCreate;
  final void Function(SharingPolicy policy, UpdateSharingPolicyRequest request)? onUpdate;
  final ValueChanged<SharingPolicy>? onDelete;
  final String? title;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view, from the policies, the paging, the overlay
  /// rules, the loading and error state, and the create, update and delete actions.
  final AdminWidgetBuilder<SharingPoliciesState>? builder;

  const BaseSharingPolicies({
    super.key,
    required this.policies,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.overlay,
    this.isMutating = false,
    this.onCreate,
    this.onUpdate,
    this.onDelete,
    this.title,
    this.preferences,
    this.builder,
  });

  @override
  State<BaseSharingPolicies> createState() => _BaseSharingPoliciesState();
}

class _BaseSharingPoliciesState extends State<BaseSharingPolicies> {
  static const _block = 'sharing-policies';
  bool _adding = false;
  String? _editingId;

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        SharingPoliciesState(
          policies: widget.policies,
          isLoading: widget.isLoading,
          error: widget.error,
          limit: widget.limit,
          offset: widget.offset,
          totalResults: widget.totalResults ?? widget.policies.length,
          onPageChange: widget.onPageChange,
          overlay: widget.overlay,
          describe: (policy) => describeSharingScope(policy, ac),
          isMutating: widget.isMutating,
          onCreate: widget.onCreate,
          onUpdate: widget.onUpdate,
          onDelete: widget.onDelete,
        ),
      );
    }
    final onCreate = widget.onCreate;
    final overlay = widget.overlay;
    return AdminSection(
      ac: ac,
      block: _block,
      title: widget.title ?? ac.t('admin.sharing.title'),
      actions: [
        if (onCreate != null && !_adding)
          AdminButton(
            ac: ac,
            label: ac.t('admin.sharing.add'),
            identifier: 'thunderid-action-sharing-policies-add',
            variant: AdminButtonVariant.outline,
            onPressed: widget.isMutating ? null : () => setState(() => _adding = true),
          ),
      ],
      children: [
        if (_adding && onCreate != null)
          SharingPolicyForm(
            ac: ac,
            policy: null,
            isSubmitting: widget.isMutating,
            onCancel: () => setState(() => _adding = false),
            onSubmit: (draft) {
              onCreate(CreateSharingPolicyRequest(childUnits: draft.childUnits));
              setState(() => _adding = false);
            },
          ),
        AdminTable<SharingPolicy>(
          ac: ac,
          block: _block,
          rows: widget.policies,
          rowId: (policy) => policy.id,
          isLoading: widget.isLoading,
          error: widget.error,
          emptyText: ac.t('admin.sharing.empty'),
          paging: widget.onPageChange == null
              ? null
              : AdminPaging(
                  limit: widget.limit,
                  offset: widget.offset,
                  total: widget.totalResults ?? widget.policies.length,
                  onChange: widget.onPageChange!,
                ),
          columns: [AdminColumn(header: ac.t('admin.sharing.title'), build: (policy) => _scope(ac, policy))],
          trailing: (policy) => policy.isReadOnly ? const SizedBox.shrink() : _rowActions(ac, policy),
        ),
        if (overlay != null) SharingOverlayPanel(ac: ac, overlay: overlay),
      ],
    );
  }

  /// The policy's reach, its details, or its edit form while it is being edited.
  Widget _scope(AdminContext ac, SharingPolicy policy) {
    final onUpdate = widget.onUpdate;
    if (_editingId == policy.id && onUpdate != null && !policy.isReadOnly) {
      return SharingPolicyForm(
        ac: ac,
        policy: policy,
        isSubmitting: widget.isMutating,
        onCancel: () => setState(() => _editingId = null),
        onSubmit: (draft) {
          onUpdate(
            policy,
            UpdateSharingPolicyRequest(
              version: policy.version ?? 0,
              allUnits: draft.allUnits,
              childUnits: draft.childUnits,
              otherTreeRoots: policy.otherTreeRoots,
            ),
          );
          setState(() => _editingId = null);
        },
      );
    }
    final details = [
      if (policy.stage == 'reshare') ac.t('admin.sharing.stage.reshare'),
      if (policy.initiatingOuId != null) ac.t('admin.sharing.issuer', {'unit': policy.initiatingOuId!}),
      if (policy.isReadOnly) ac.t('admin.sharing.read_only'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(describeSharingScope(policy, ac)),
        if (details.isNotEmpty)
          Text(details.join(' · '), style: TextStyle(color: ac.colors.textSecondary, fontSize: 13)),
      ],
    );
  }

  Widget _rowActions(AdminContext ac, SharingPolicy policy) {
    final onDelete = widget.onDelete;
    return Wrap(
      spacing: 8,
      children: [
        if (widget.onUpdate != null && _editingId != policy.id)
          AdminButton(
            ac: ac,
            label: ac.t('admin.sharing.edit'),
            identifier: 'thunderid-action-sharing-policies-edit-${policy.id}',
            variant: AdminButtonVariant.text,
            onPressed: widget.isMutating ? null : () => setState(() => _editingId = policy.id),
          ),
        if (onDelete != null)
          AdminConfirmButton(
            ac: ac,
            label: ac.t('admin.sharing.delete.action'),
            confirmText: ac.t('admin.sharing.delete.confirm'),
            identifier: 'thunderid-action-sharing-policies-delete-${policy.id}',
            onConfirm: () => onDelete(policy),
          ),
      ],
    );
  }
}

/// The sharing policies of one user, application, role or flow, loaded through that resource
/// type's sharing operations.
///
/// Set [editable] to let the signed-in user add, edit and delete policies; it is off by default,
/// and a delete asks for confirmation first. With [ouId], the resolved overlay rules for that
/// organization unit are shown too, read only. The details components do not embed it: place it
/// where the app wants it.
class SharingPolicies extends StatefulWidget {
  final SharingResourceType resourceType;
  final String resourceId;

  /// Shows how the resource appears in this organization unit, read only.
  final String? ouId;
  final int limit;
  final bool editable;
  final String? title;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default view. See [BaseSharingPolicies.builder].
  final AdminWidgetBuilder<SharingPoliciesState>? builder;

  const SharingPolicies({
    super.key,
    required this.resourceType,
    required this.resourceId,
    this.ouId,
    this.limit = 20,
    this.editable = false,
    this.title,
    this.preferences,
    this.builder,
  });

  @override
  State<SharingPolicies> createState() => _SharingPoliciesState();
}

class _SharingPoliciesState extends AdminConnectedState<SharingPolicies> {
  int _offset = 0;
  ResourceQuery<ManagementPage<SharingPolicy>>? _policies;
  ResourceQuery<ResolvedOverlay>? _overlay;
  ResourceMutation<CreateSharingPolicyVariables, SharingPolicy>? _create;
  ResourceMutation<UpdateSharingPolicyVariables, SharingPolicy>? _update;
  ResourceMutation<DeleteSharingPolicyVariables, void>? _delete;

  @override
  void bind(ManagementResources resources) {
    final type = widget.resourceType;
    _policies = own(resources.sharingPoliciesQuery(type, widget.resourceId, limit: widget.limit, offset: _offset));
    _overlay = own(resources.overlayRulesQuery(type, widget.resourceId, widget.ouId));
    _create = own(resources.createSharingPolicyMutation(type));
    _update = own(resources.updateSharingPolicyMutation(type));
    _delete = own(resources.deleteSharingPolicyMutation(type));
  }

  @override
  void didUpdateWidget(SharingPolicies oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceType != widget.resourceType ||
        oldWidget.resourceId != widget.resourceId ||
        oldWidget.ouId != widget.ouId ||
        oldWidget.limit != widget.limit) {
      _offset = 0;
      rebind();
    }
  }

  void _changePage(int offset) {
    setState(() => _offset = offset);
    rebind();
  }

  String? _mutationError(AdminContext ac) {
    for (final error in [_create?.error, _update?.error, _delete?.error]) {
      final message = toManagementErrorMessage(
        ac.t,
        error,
        'admin.sharing.update_error',
        codeKeys: HierarchyErrorKeys.sharing,
      );
      if (message != null) return message;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _policies;
    final create = _create;
    final update = _update;
    final delete = _delete;
    final editable = widget.editable;
    final resourceId = widget.resourceId;
    return BaseSharingPolicies(
      policies: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.sharing.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.sharing.error') ??
                _mutationError(ac) ??
                toManagementErrorMessage(ac.t, _overlay?.error, 'admin.sharing.overlay.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      overlay: _overlay?.data,
      isMutating: (create?.isLoading ?? false) || (update?.isLoading ?? false) || (delete?.isLoading ?? false),
      onCreate: editable && create != null
          ? (request) => unawaited(create.mutate((resourceId: resourceId, data: request)))
          : null,
      onUpdate: editable && update != null
          ? (policy, request) => unawaited(update.mutate((resourceId: resourceId, policyId: policy.id, data: request)))
          : null,
      onDelete: editable && delete != null
          ? (policy) => unawaited(delete.mutate((resourceId: resourceId, policyId: policy.id)))
          : null,
      title: widget.title,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
