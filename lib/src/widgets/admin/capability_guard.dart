// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../state/capabilities_notifier.dart';
import '../thunderid_provider.dart';

/// Renders [child] only when the signed-in user may perform [action] on [resource], or any one of
/// [anyOf] when it is given (spec "Management capabilities").
///
/// Reads the capabilities through the [ThunderIDProvider]'s [CapabilitiesNotifier], starting the
/// read on first use; every guard under one provider shares that one read. While they load it
/// renders [loading], when they cannot be read [error] (with [CapabilitiesNotifier.retry] to read
/// again), and otherwise [child] or [denied]. Each fallback renders nothing by default.
///
/// It decides what is offered, not what is allowed: it is not an authorization decision. The
/// server authorizes every management request, and the SDK never blocks one because of it.
class CapabilityGuard extends StatefulWidget {
  final String? resource;
  final String action;

  /// `(resource, action)` pairs; the guard allows when any one is allowed. Replaces [resource].
  final List<(String, String)>? anyOf;
  final Widget child;
  final Widget denied;
  final Widget loading;

  /// Built when the capabilities cannot be read, with the notifier so it can offer
  /// [CapabilitiesNotifier.retry]. Renders nothing when omitted.
  final Widget Function(BuildContext context, CapabilitiesNotifier capabilities)? error;

  const CapabilityGuard({
    super.key,
    this.resource,
    this.action = 'view',
    this.anyOf,
    required this.child,
    this.denied = const SizedBox.shrink(),
    this.loading = const SizedBox.shrink(),
    this.error,
  }) : assert(resource != null || anyOf != null, 'Pass a resource or anyOf');

  @override
  State<CapabilityGuard> createState() => _CapabilityGuardState();
}

class _CapabilityGuardState extends State<CapabilityGuard> {
  CapabilitiesNotifier? _capabilities;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final capabilities = ThunderIDProvider.of(context).capabilities;
    if (!identical(capabilities, _capabilities)) {
      _capabilities?.removeListener(_changed);
      _capabilities = capabilities..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _capabilities?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities!..load();
    if (capabilities.isLoading) return widget.loading;
    if (capabilities.error != null) return widget.error?.call(context, capabilities) ?? const SizedBox.shrink();
    final anyOf = widget.anyOf;
    final allowed = anyOf != null
        ? anyOf.any((pair) => capabilities.can(pair.$1, pair.$2))
        : capabilities.can(widget.resource!, widget.action);
    return allowed ? widget.child : widget.denied;
  }
}
