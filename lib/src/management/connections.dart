// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/management/connection.dart';
import '../models/management/json_reader.dart';
import '../models/management/management_page.dart';
import '../models/management/resource_usage.dart';
import '../models/thunderid_error.dart';
import 'management_collection.dart';
import 'management_filter.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Connection operations: `/connections`, with each [ConnectionType] under
/// `/connections/{type}`.
///
/// A connection's settings can hold credentials (client secrets, auth tokens, API secrets);
/// nothing here logs a request or response.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.connections] override, then `{baseUrl}/connections`.
extension ConnectionOperations on ThunderIDManagementClient {
  /// Lists the connections: every one, paged and optionally narrowed to a [category] (such as
  /// `identity-provider`), or only those of [type]. With [ouId], lists the connections that
  /// organization unit owns followed by the ones shared into it, instead of every connection the
  /// caller can see.
  ///
  /// The server lists one type without paging, so with [type] the page holds every connection of
  /// that type and [limit], [offset], [category] and [ouId] are not sent.
  Future<ManagementPage<ConnectionInstance>> getConnections({
    ConnectionType? type,
    String? category,
    String? ouId,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (type != null) {
      final json = await _send(
        'getConnections',
        'Failed to fetch connections',
        segments: [type.value],
        url: url,
        fetcher: fetcher,
      );
      final items = (json is List ? json : const <Object?>[])
          .map((item) => ConnectionInstance.fromJson(readMap(item), type: type))
          .toList(growable: false);
      return ManagementPage(items: items, totalResults: items.length);
    }
    return ManagementPage.fromJson(
      await _send(
        'getConnections',
        'Failed to fetch connections',
        query: {
          'category': category,
          'filter': ouId == null ? null : ManagementFilter.equality('ouId', ouId),
          'limit': limit,
          'offset': offset,
        },
        url: url,
        fetcher: fetcher,
      ),
      'connections',
      (item) => ConnectionInstance.fromJson(readMap(item)),
    );
  }

  Future<Connection> getConnection(
    ConnectionType type,
    String connectionId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Connection.fromJson(
        readMap(
          await _send(
            'getConnection',
            'Failed to fetch connection',
            segments: [type.value, connectionId],
            url: url,
            fetcher: fetcher,
          ),
        ),
        type: type,
      );

  Future<Connection> createConnection(
    ConnectionType type,
    CreateConnectionRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Connection.fromJson(
        readMap(
          await _send(
            'createConnection',
            'Failed to create connection',
            method: 'POST',
            segments: [type.value],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
        type: type,
      );

  Future<Connection> updateConnection(
    ConnectionType type,
    String connectionId,
    UpdateConnectionRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Connection.fromJson(
        readMap(
          await _send(
            'updateConnection',
            'Failed to update connection',
            method: 'PUT',
            segments: [type.value, connectionId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
        type: type,
      );

  Future<void> deleteConnection(
    ConnectionType type,
    String connectionId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteConnection',
        'Failed to delete connection',
        method: 'DELETE',
        segments: [type.value, connectionId],
        url: url,
        fetcher: fetcher,
      );

  /// Lists the flows that use a connection, and what happens to each when it is deleted.
  ///
  /// Every type but [ConnectionType.http] reports its usages; for an HTTP connection this raises
  /// [ThunderIDErrorCode.invalidInput] without sending anything.
  Future<ResourceUsages> getConnectionUsages(
    ConnectionType type,
    String connectionId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'getConnectionUsages';
    if (type == ConnectionType.http) {
      throw const IAMException(
        ThunderIDErrorCode.invalidInput,
        '$operation: the server does not report usages for HTTP connections.',
      );
    }
    return ResourceUsages.fromJson(
      readMap(
        await _send(
          operation,
          'Failed to fetch connection usages',
          segments: [type.value, connectionId, 'usages'],
          url: url,
          fetcher: fetcher,
        ),
      ),
    );
  }

  /// Reads what the server supports for each connection vendor, or only for [vendor].
  Future<ConnectionsMeta> getConnectionsMeta({String? vendor, String? url, ManagementFetcher? fetcher}) async =>
      ConnectionsMeta.fromJson(
        readMap(
          await _send(
            'getConnectionsMeta',
            'Failed to fetch connection metadata',
            segments: const ['meta'],
            query: {'vendor': vendor},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Object?> _send(
    String operation,
    String failureMessage, {
    String method = 'GET',
    List<String> segments = const [],
    Map<String, Object?> query = const {},
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: ManagementEndpointKeys.connections,
        collection: 'connections',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
