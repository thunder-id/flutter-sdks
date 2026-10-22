// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:thunderid_flutter/thunderid_flutter.dart';

/// Where one management collection resolves, or why it cannot.
class ResolvedEndpoint {
  final String key;

  /// The collection URL without its query, or `null` when [error] is set.
  final String? url;
  final String? error;

  const ResolvedEndpoint(this.key, {this.url, this.error});
}

/// Asks the SDK itself where each management collection resolves.
///
/// The SDK has no public resolver, so each list call is sent through a per-call fetcher that
/// records the URL and answers with an empty page. Nothing reaches the network, and the URLs are
/// exactly the ones a real call would use: [ThunderIDConfig.endpoints] first, then `baseUrl`.
Future<List<ResolvedEndpoint>> resolveManagementEndpoints(ThunderIDManagementClient management) async {
  final calls = <String, Future<Object?> Function(ManagementFetcher fetcher)>{
    ManagementEndpointKeys.users: (f) => management.getUsers(limit: 1, fetcher: f),
    ManagementEndpointKeys.userTypes: (f) => management.getUserTypes(limit: 1, fetcher: f),
    ManagementEndpointKeys.groups: (f) => management.getGroups(limit: 1, fetcher: f),
    ManagementEndpointKeys.roles: (f) => management.getRoles(limit: 1, fetcher: f),
    ManagementEndpointKeys.agents: (f) => management.getAgents(limit: 1, fetcher: f),
    ManagementEndpointKeys.agentTypes: (f) => management.getAgentTypes(limit: 1, fetcher: f),
  };
  final resolved = <ResolvedEndpoint>[];
  for (final entry in calls.entries) {
    Uri? captured;
    try {
      await entry.value((request) async {
        captured = request.url;
        return const ManagementResponse(statusCode: 200, body: '{}');
      });
      final url = captured!;
      resolved.add(ResolvedEndpoint(entry.key, url: '${url.scheme}://${url.authority}${url.path}'));
    } on IAMException catch (e) {
      // Raised before the fetcher runs, e.g. an override that is not HTTPS.
      resolved.add(ResolvedEndpoint(entry.key, error: '${e.code.value}: ${e.message}'));
    }
  }
  return resolved;
}
