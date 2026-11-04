// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/credential_configuration.dart';
import '../../models/management/json_reader.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// OpenID4VCI credential configuration operations: `/openid4vci/credential-configurations`, the
/// verifiable credential types the issuer offers.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.credentialConfigurations] override, then
/// `{baseUrl}/openid4vci/credential-configurations`.
extension CredentialConfigurationOperations on ThunderIDManagementClient {
  /// Lists the credential configurations, each with its summary fields only (see
  /// [CredentialConfiguration]). The server does not page this list.
  Future<List<CredentialConfiguration>> getCredentialConfigurations({
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    final json = await _send(
      'getCredentialConfigurations',
      'Failed to fetch credential configurations',
      url: url,
      fetcher: fetcher,
    );
    return (json is List ? json : const <Object?>[])
        .map((item) => CredentialConfiguration.fromJson(readMap(item)))
        .toList(growable: false);
  }

  Future<CredentialConfiguration> getCredentialConfiguration(
    String configurationId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      CredentialConfiguration.fromJson(
        readMap(
          await _send(
            'getCredentialConfiguration',
            'Failed to fetch credential configuration',
            segments: [configurationId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<CredentialConfiguration> createCredentialConfiguration(
    CredentialConfigurationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      CredentialConfiguration.fromJson(
        readMap(
          await _send(
            'createCredentialConfiguration',
            'Failed to create credential configuration',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Replaces [configurationId]: fields [payload] leaves out are not kept.
  Future<CredentialConfiguration> updateCredentialConfiguration(
    String configurationId,
    CredentialConfigurationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      CredentialConfiguration.fromJson(
        readMap(
          await _send(
            'updateCredentialConfiguration',
            'Failed to update credential configuration',
            method: 'PUT',
            segments: [configurationId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Deletes [configurationId]. Deleting one that does not exist succeeds.
  Future<void> deleteCredentialConfiguration(
    String configurationId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteCredentialConfiguration',
        'Failed to delete credential configuration',
        method: 'DELETE',
        segments: [configurationId],
        url: url,
        fetcher: fetcher,
      );

  Future<Object?> _send(
    String operation,
    String failureMessage, {
    String method = 'GET',
    List<String> segments = const [],
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: ManagementEndpointKeys.credentialConfigurations,
        collection: 'openid4vci/credential-configurations',
        method: method,
        segments: segments,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
