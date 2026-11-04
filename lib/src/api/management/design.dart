// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/design.dart';
import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/resource_usage.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Design operations: themes (`/design/themes`), layouts (`/design/layouts`), and the design
/// that applies to an application or organization unit (`/design/resolve`).
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.design] override, then `{baseUrl}/design`.
extension DesignOperations on ThunderIDManagementClient {
  // ── Themes ─────────────────────────────────────────────────────────────

  Future<ManagementPage<DesignThemeSummary>> getThemes({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getThemes',
          'Failed to fetch themes',
          segments: const ['themes'],
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'themes',
        (item) => DesignThemeSummary.fromJson(readMap(item)),
      );

  Future<DesignTheme> getTheme(String themeId, {String? url, ManagementFetcher? fetcher}) async =>
      DesignTheme.fromJson(
        readMap(
          await _send('getTheme', 'Failed to fetch theme', segments: ['themes', themeId], url: url, fetcher: fetcher),
        ),
      );

  Future<DesignTheme> createTheme(DesignThemeRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      DesignTheme.fromJson(
        readMap(
          await _send(
            'createTheme',
            'Failed to create theme',
            method: 'POST',
            segments: const ['themes'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<DesignTheme> updateTheme(
    String themeId,
    DesignThemeRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      DesignTheme.fromJson(
        readMap(
          await _send(
            'updateTheme',
            'Failed to update theme',
            method: 'PUT',
            segments: ['themes', themeId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteTheme(String themeId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteTheme',
        'Failed to delete theme',
        method: 'DELETE',
        segments: ['themes', themeId],
        url: url,
        fetcher: fetcher,
      );

  /// Lists the applications and agents that use [themeId].
  Future<ResourceUsages> getThemeUsages(
    String themeId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceUsages.fromJson(
        readMap(
          await _send(
            'getThemeUsages',
            'Failed to fetch theme usages',
            segments: ['themes', themeId, 'usages'],
            query: {'limit': limit, 'offset': offset},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  // ── Layouts ────────────────────────────────────────────────────────────

  Future<ManagementPage<DesignLayoutSummary>> getLayouts({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getLayouts',
          'Failed to fetch layouts',
          segments: const ['layouts'],
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'layouts',
        (item) => DesignLayoutSummary.fromJson(readMap(item)),
      );

  Future<DesignLayout> getLayout(String layoutId, {String? url, ManagementFetcher? fetcher}) async =>
      DesignLayout.fromJson(
        readMap(
          await _send(
            'getLayout',
            'Failed to fetch layout',
            segments: ['layouts', layoutId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<DesignLayout> createLayout(DesignLayoutRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      DesignLayout.fromJson(
        readMap(
          await _send(
            'createLayout',
            'Failed to create layout',
            method: 'POST',
            segments: const ['layouts'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<DesignLayout> updateLayout(
    String layoutId,
    DesignLayoutRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      DesignLayout.fromJson(
        readMap(
          await _send(
            'updateLayout',
            'Failed to update layout',
            method: 'PUT',
            segments: ['layouts', layoutId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteLayout(String layoutId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteLayout',
        'Failed to delete layout',
        method: 'DELETE',
        segments: ['layouts', layoutId],
        url: url,
        fetcher: fetcher,
      );

  /// Lists the applications and agents that use [layoutId].
  Future<ResourceUsages> getLayoutUsages(
    String layoutId, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceUsages.fromJson(
        readMap(
          await _send(
            'getLayoutUsages',
            'Failed to fetch layout usages',
            segments: ['layouts', layoutId, 'usages'],
            query: {'limit': limit, 'offset': offset},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  // ── Resolution ─────────────────────────────────────────────────────────

  /// Reads the theme and layout that apply to the application or organization unit [id].
  Future<ResolvedDesign> resolveDesign(
    DesignEntityType type,
    String id, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResolvedDesign.fromJson(
        readMap(
          await _send(
            'resolveDesign',
            'Failed to resolve design',
            segments: const ['resolve'],
            query: {'type': type.value, 'id': id},
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
        endpointKey: ManagementEndpointKeys.design,
        collection: 'design',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
