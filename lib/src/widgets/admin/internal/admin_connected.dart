// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../../state/management_resources.dart';
import '../../thunderid_provider.dart';

// Package-internal (not exported): the wiring every connected admin component shares.

/// State of a connected admin component: binds its queries and mutations once the
/// [ThunderIDProvider] has initialized, rebuilds when any of them changes, and disposes them
/// with the widget.
abstract class AdminConnectedState<W extends StatefulWidget> extends State<W> {
  ManagementResources? _resources;
  ThunderIDState? _thunder;
  final List<ChangeNotifier> _owned = [];

  /// The provider's management state, or `null` until the provider has initialized.
  ManagementResources? get resources => _resources;

  ThunderIDState? get thunder => _thunder;

  /// Whether the provider failed to initialize, so nothing will load.
  bool get providerFailed => _resources == null && (_thunder?.error != null) && !(_thunder?.isLoading ?? true);

  /// Creates the queries and mutations this component needs, through [own].
  void bind(ManagementResources resources);

  /// Takes ownership of [notifier]: the component rebuilds when it changes and disposes it.
  T own<T extends ChangeNotifier>(T notifier) {
    _owned.add(notifier);
    notifier.addListener(_changed);
    return notifier;
  }

  /// Disposes [notifier] early, e.g. a list query replaced by the next page's.
  void release(ChangeNotifier? notifier) {
    if (notifier == null || !_owned.remove(notifier)) return;
    notifier
      ..removeListener(_changed)
      ..dispose();
  }

  /// Disposes everything bound and binds again, e.g. after the resource id changed.
  void rebind() {
    _releaseAll();
    final resources = _resources;
    if (resources != null) bind(resources);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _releaseAll() {
    for (final notifier in _owned) {
      notifier
        ..removeListener(_changed)
        ..dispose();
    }
    _owned.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final thunder = ThunderIDProvider.of(context);
    _thunder = thunder;
    if (_resources == null && thunder.initialized) {
      final resources = thunder.managementResources;
      _resources = resources;
      bind(resources);
    }
  }

  @override
  void dispose() {
    _releaseAll();
    super.dispose();
  }
}
