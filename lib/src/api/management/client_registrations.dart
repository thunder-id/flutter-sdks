// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/client_registration.dart';
import '../../models/management/json_reader.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Dynamic client registration operations (RFC 7591 / RFC 7592): `/oauth2/dcr/register`.
///
/// The server answers a failure with an OAuth error (`{error, error_description}`) rather than
/// the management error envelope; it surfaces the same way, as an [IAMApiException] whose code
/// follows the HTTP status and whose [IAMApiException.serverError] carries `error` as its code and
/// `error_description` as its message.
///
/// A client's secret is returned by [registerClient] only, and nothing here logs it.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.clientRegistrations] override, then `{baseUrl}/oauth2/dcr/register`.
extension ClientRegistrationOperations on ThunderIDManagementClient {
  /// Registers a client. The result carries the issued `clientSecret`, readable only now.
  Future<ClientRegistration> registerClient(
    ClientRegistrationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ClientRegistration.fromJson(
        readMap(
          await _send(
            'registerClient',
            'Failed to register client',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Reads [clientId]'s registration, without its secret.
  Future<ClientRegistration> getClientRegistration(
    String clientId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ClientRegistration.fromJson(
        readMap(
          await _send(
            'getClientRegistration',
            'Failed to fetch client registration',
            segments: [clientId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Replaces [clientId]'s registered metadata, keeping its id and secret: metadata [payload]
  /// leaves out is not kept. The body's `client_id` is set to [clientId].
  Future<ClientRegistration> updateClientRegistration(
    String clientId,
    UpdateClientRegistrationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ClientRegistration.fromJson(
        readMap(
          await _send(
            'updateClientRegistration',
            'Failed to update client registration',
            method: 'PUT',
            segments: [clientId],
            body: {...payload.toJson(), 'client_id': clientId},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteClientRegistration(String clientId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteClientRegistration',
        'Failed to delete client registration',
        method: 'DELETE',
        segments: [clientId],
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
        endpointKey: ManagementEndpointKeys.clientRegistrations,
        collection: 'oauth2/dcr/register',
        method: method,
        segments: segments,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
