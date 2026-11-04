// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../i18n/default_strings.dart';
import '../../models/account/organization_unit.dart';
import '../../models/thunderid_error.dart';
import '../../models/user.dart';
import '../thunderid_provider.dart';

/// What [OrganizationUnitSwitcher] and [BaseOrganizationUnitSwitcher] hand their `builder`, so the
/// units can be drawn with any UI.
class OrganizationUnitSwitcherState {
  /// The units on the current page.
  final List<AccessibleOrganizationUnit> units;

  /// The id of the unit the session is signed in to, or `null` when it is not known.
  final String? currentId;
  final bool isLoading;

  /// The id of the unit a switch is running for, or `null` when none is.
  final String? switchingId;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;
  final int limit;
  final int offset;
  final int totalResults;

  /// Shows the page that starts at the given offset. `null` when the list is not paginated.
  final ValueChanged<int>? onPageChange;

  /// Switches to a unit. `null` while a switch is running.
  final ValueChanged<AccessibleOrganizationUnit>? onSwitch;

  const OrganizationUnitSwitcherState({
    required this.units,
    required this.currentId,
    required this.isLoading,
    required this.switchingId,
    required this.error,
    required this.limit,
    required this.offset,
    required this.totalResults,
    required this.onPageChange,
    required this.onSwitch,
  });
}

/// Builds custom UI for an organization unit switcher from the state it hands over.
typedef OrganizationUnitSwitcherBuilder = Widget Function(BuildContext context, OrganizationUnitSwitcherState state);

/// Lists the organization units the signed-in user can access, marks the current one, and signs
/// in again to the one the user picks with [ThunderIDClient.switchOrganizationUnit].
///
/// [scope] narrows the list (for example to the current unit's siblings). Pass [onSelect] to take
/// the switch over: the widget then calls it instead of switching. After a switch the provider's
/// user is refreshed and [onSwitched] is called; a failed switch leaves the session as it was and
/// shows a translated message.
class OrganizationUnitSwitcher extends StatefulWidget {
  final AccessibleOrganizationUnitScope? scope;

  /// The page size.
  final int limit;

  /// Called instead of switching, so the app can switch itself.
  final ValueChanged<AccessibleOrganizationUnit>? onSelect;

  /// Called with the user of the new session after a switch.
  final ValueChanged<User>? onSwitched;

  /// Called with the error when loading or switching fails.
  final ValueChanged<Object>? onError;

  /// Builds custom UI in place of the default list.
  final OrganizationUnitSwitcherBuilder? builder;

  const OrganizationUnitSwitcher({
    super.key,
    this.scope,
    this.limit = 10,
    this.onSelect,
    this.onSwitched,
    this.onError,
    this.builder,
  });

  @override
  State<OrganizationUnitSwitcher> createState() => _OrganizationUnitSwitcherState();
}

class _OrganizationUnitSwitcherState extends State<OrganizationUnitSwitcher> {
  AccessibleOrganizationUnitList? _page;
  int _offset = 0;
  bool _isLoading = true;
  String? _switchingId;
  String? _errorKey;
  int _request = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The provider initializes asynchronously; the list is read once it has.
    if (!_started && ThunderIDProvider.of(context).initialized) {
      _started = true;
      Future.microtask(_load);
    }
  }

  @override
  void didUpdateWidget(OrganizationUnitSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_started && (oldWidget.scope != widget.scope || oldWidget.limit != widget.limit)) {
      _offset = 0;
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final client = ThunderIDProvider.of(context).client;
    setState(() {
      _isLoading = true;
      _errorKey = null;
    });
    try {
      final page = await client.getAccessibleOrganizationUnits(
        scope: widget.scope,
        limit: widget.limit,
        offset: _offset,
      );
      if (!mounted || request != _request) return;
      setState(() => _page = page);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _errorKey = 'organizationSwitcher.errors.load');
      widget.onError?.call(error);
    } finally {
      if (mounted && request == _request) setState(() => _isLoading = false);
    }
  }

  Future<void> _switch(AccessibleOrganizationUnit unit) async {
    final onSelect = widget.onSelect;
    if (onSelect != null) {
      onSelect(unit);
      return;
    }
    final state = ThunderIDProvider.of(context);
    setState(() {
      _switchingId = unit.id;
      _errorKey = null;
    });
    try {
      final user = await state.client.switchOrganizationUnit(unit.id);
      await state.refresh();
      if (!mounted) return;
      widget.onSwitched?.call(user);
      await _load();
    } on IAMException catch (error) {
      if (!mounted) return;
      // Closing the browser is the user changing their mind, not a failure.
      if (error.code != ThunderIDErrorCode.federatedAuthCancelled) {
        setState(
          () => _errorKey = error.code == ThunderIDErrorCode.organizationUnitUnavailable
              ? 'organizationSwitcher.errors.unavailable'
              : 'organizationSwitcher.errors.switch',
        );
        widget.onError?.call(error);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorKey = 'organizationSwitcher.errors.switch');
      widget.onError?.call(error);
    } finally {
      if (mounted) setState(() => _switchingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final errorKey = _errorKey;
    return BaseOrganizationUnitSwitcher(
      units: page?.organizationUnits ?? const [],
      currentId: page?.current,
      isLoading: _isLoading,
      switchingId: _switchingId,
      error: errorKey == null ? null : _resolve(context, errorKey),
      limit: widget.limit,
      offset: _offset,
      totalResults: page?.totalResults,
      onPageChange: (offset) {
        _offset = offset;
        _load();
      },
      onSwitch: _switch,
      builder: widget.builder,
    );
  }
}

/// Unstyled base variant: draws the units it is given and reports the user's choice, with no SDK
/// state.
class BaseOrganizationUnitSwitcher extends StatelessWidget {
  final List<AccessibleOrganizationUnit> units;
  final String? currentId;
  final bool isLoading;
  final String? switchingId;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<AccessibleOrganizationUnit>? onSwitch;

  /// Builds custom UI in place of the default list.
  final OrganizationUnitSwitcherBuilder? builder;

  const BaseOrganizationUnitSwitcher({
    super.key,
    required this.units,
    this.currentId,
    this.isLoading = false,
    this.switchingId,
    this.error,
    this.limit = 10,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSwitch,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final onSwitch = this.onSwitch;
    final state = OrganizationUnitSwitcherState(
      units: units,
      currentId: currentId,
      isLoading: isLoading,
      switchingId: switchingId,
      error: error,
      limit: limit,
      offset: offset,
      totalResults: totalResults ?? units.length,
      onPageChange: onPageChange,
      onSwitch: switchingId == null ? onSwitch : null,
    );
    final builder = this.builder;
    if (builder != null) return builder(context, state);
    return _DefaultSwitcher(state: state);
  }
}

class _DefaultSwitcher extends StatelessWidget {
  final OrganizationUnitSwitcherState state;

  const _DefaultSwitcher({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String t(String key) => _resolve(context, key);
    final error = state.error;
    final onPageChange = state.onPageChange;
    final hasPrevious = state.offset > 0;
    final hasNext = state.offset + state.units.length < state.totalResults;

    return Semantics(
      container: true,
      label: t('organizationSwitcher.label'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(t('organizationSwitcher.label'), style: theme.textTheme.titleMedium),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (state.isLoading && state.units.isEmpty)
            Semantics(
              label: t('organizationSwitcher.loading'),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (state.units.isEmpty && error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t('organizationList.empty'), style: theme.textTheme.bodyMedium),
            )
          else
            for (final unit in state.units) _row(context, unit, t),
          if (onPageChange != null && (hasPrevious || hasNext))
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: hasPrevious && !state.isLoading
                      ? () => onPageChange((state.offset - state.limit).clamp(0, state.offset))
                      : null,
                  child: Text(t('admin.common.pagination.previous')),
                ),
                TextButton(
                  onPressed: hasNext && !state.isLoading ? () => onPageChange(state.offset + state.limit) : null,
                  child: Text(t('admin.common.pagination.next')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AccessibleOrganizationUnit unit, String Function(String) t) {
    final theme = Theme.of(context);
    final isCurrent = unit.id == state.currentId;
    final isSwitching = unit.id == state.switchingId;
    final onSwitch = state.onSwitch;
    final name = unit.name.isNotEmpty ? unit.name : (unit.handle.isNotEmpty ? unit.handle : t('organization.unnamed'));
    return ListTile(
      key: Key('thunderid-ou-${unit.id}'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      title: Text(name),
      subtitle: unit.handle.isNotEmpty && unit.handle != name ? Text(unit.handle) : null,
      trailing: isCurrent
          ? Chip(
              label: Text(t('organizationSwitcher.current')),
              backgroundColor: theme.colorScheme.secondaryContainer,
            )
          : isSwitching
              ? Semantics(
                  label: t('organizationSwitcher.switching'),
                  child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  child: OutlinedButton(
                    key: Key('thunderid-ou-switch-${unit.id}'),
                    onPressed: onSwitch == null ? null : () => onSwitch(unit),
                    child: Text(t('organizationSwitcher.switch')),
                  ),
                ),
    );
  }
}

String _resolve(BuildContext context, String key) =>
    ThunderIDProvider.maybeOf(context)?.i18n.resolve(key) ?? thunderDefaultStrings[key] ?? key;
