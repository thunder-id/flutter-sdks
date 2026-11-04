// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/presentation_definition.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// OpenID4VP presentation definition operations: `/openid4vp/presentation-definitions`, what
/// the verifier asks a wallet to present.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.presentationDefinitions] override, then
/// `{baseUrl}/openid4vp/presentation-definitions`.
extension PresentationDefinitionOperations on ThunderIDManagementClient {
  /// Lists the presentation definitions, each with its summary fields only (see
  /// [PresentationDefinition]). The server does not page this list.
  Future<List<PresentationDefinition>> getPresentationDefinitions({
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    final json = await _send(
      'getPresentationDefinitions',
      'Failed to fetch presentation definitions',
      url: url,
      fetcher: fetcher,
    );
    return (json is List ? json : const <Object?>[])
        .map((item) => PresentationDefinition.fromJson(readMap(item)))
        .toList(growable: false);
  }

  Future<PresentationDefinition> getPresentationDefinition(
    String definitionId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      PresentationDefinition.fromJson(
        readMap(
          await _send(
            'getPresentationDefinition',
            'Failed to fetch presentation definition',
            segments: [definitionId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<PresentationDefinition> createPresentationDefinition(
    PresentationDefinitionRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      PresentationDefinition.fromJson(
        readMap(
          await _send(
            'createPresentationDefinition',
            'Failed to create presentation definition',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Replaces [definitionId]: fields [payload] leaves out are not kept.
  Future<PresentationDefinition> updatePresentationDefinition(
    String definitionId,
    PresentationDefinitionRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      PresentationDefinition.fromJson(
        readMap(
          await _send(
            'updatePresentationDefinition',
            'Failed to update presentation definition',
            method: 'PUT',
            segments: [definitionId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Deletes [definitionId]. Deleting one that does not exist succeeds.
  Future<void> deletePresentationDefinition(
    String definitionId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deletePresentationDefinition',
        'Failed to delete presentation definition',
        method: 'DELETE',
        segments: [definitionId],
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
        endpointKey: ManagementEndpointKeys.presentationDefinitions,
        collection: 'openid4vp/presentation-definitions',
        method: method,
        segments: segments,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
