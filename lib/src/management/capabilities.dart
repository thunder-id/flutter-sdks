// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/management/capabilities.dart';
import '../models/management/json_reader.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Management capabilities: `GET /capabilities` (spec "Management capabilities").
///
/// The URL resolves like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.capabilities] override, then `{baseUrl}/capabilities`.
extension CapabilitiesOperations on ThunderIDManagementClient {
  /// Reads which management actions the signed-in user's access token allows.
  ///
  /// The answer decides what an application offers, not what is allowed: it is not an
  /// authorization decision. The server authorizes every management request, and the SDK never
  /// skips or blocks one because of it. A failure is raised like any other management operation.
  Future<Capabilities> getCapabilities({String? url, ManagementFetcher? fetcher}) async => Capabilities.fromJson(
        readMap(
          await sendCollectionRequest(
            this,
            operation: 'getCapabilities',
            failureMessage: 'Failed to fetch capabilities',
            endpointKey: ManagementEndpointKeys.capabilities,
            collection: 'capabilities',
            url: url,
            fetcher: fetcher,
          ),
        ),
      );
}
