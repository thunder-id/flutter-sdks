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
/// The SDK has no public resolver, so each list call (a dry-run import and an empty export for
/// those two collections, and a client registration read for that one) is sent through a per-call fetcher that
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
    ManagementEndpointKeys.applications: (f) => management.getApplications(limit: 1, fetcher: f),
    ManagementEndpointKeys.organizationUnits: (f) => management.getOrganizationUnits(limit: 1, fetcher: f),
    ManagementEndpointKeys.resourceServers: (f) => management.getResourceServers(limit: 1, fetcher: f),
    ManagementEndpointKeys.connections: (f) => management.getConnections(limit: 1, fetcher: f),
    ManagementEndpointKeys.flows: (f) => management.getFlows(limit: 1, fetcher: f),
    ManagementEndpointKeys.notificationTemplates: (f) =>
        management.getNotificationTemplates(NotificationChannel.email, limit: 1, fetcher: f),
    ManagementEndpointKeys.design: (f) => management.getThemes(limit: 1, fetcher: f),
    ManagementEndpointKeys.i18n: (f) => management.getLanguages(fetcher: f),
    ManagementEndpointKeys.serverConfig: (f) => management.getServerConfigs(fetcher: f),
    ManagementEndpointKeys.gateways: (f) => management.getGateways(fetcher: f),
    ManagementEndpointKeys.variables: (f) => management.getVariables(limit: 1, fetcher: f),
    ManagementEndpointKeys.secrets: (f) => management.getSecrets(limit: 1, fetcher: f),
    ManagementEndpointKeys.configurationVersions: (f) => management.getConfigurationVersions(fetcher: f),
    ManagementEndpointKeys.import: (f) =>
        management.importConfiguration(const ImportConfigurationRequest(dryRun: true), fetcher: f),
    ManagementEndpointKeys.export: (f) => management.exportConfiguration(const ExportConfigurationRequest(), fetcher: f),
    ManagementEndpointKeys.credentialConfigurations: (f) => management.getCredentialConfigurations(fetcher: f),
    ManagementEndpointKeys.presentationDefinitions: (f) => management.getPresentationDefinitions(fetcher: f),
    // Registration has no listing; reading a placeholder client only resolves the URL.
    ManagementEndpointKeys.clientRegistrations: (f) => management.getClientRegistration('client', fetcher: f),
    ManagementEndpointKeys.projects: (f) => management.getProjects(limit: 1, fetcher: f),
    ManagementEndpointKeys.authorizationDetailTypes: (f) => management.getAuthorizationDetailTypes(limit: 1, fetcher: f),
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
