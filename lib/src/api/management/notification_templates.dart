// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/notification_template.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Notification template operations: `/notification-templates/{channel}/templates`.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.notificationTemplates] override, then
/// `{baseUrl}/notification-templates`.
extension NotificationTemplateOperations on ThunderIDManagementClient {
  Future<ManagementPage<NotificationTemplateSummary>> getNotificationTemplates(
    NotificationChannel channel, {
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getNotificationTemplates',
          'Failed to fetch notification templates',
          segments: [channel.value, 'templates'],
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'templates',
        (item) => NotificationTemplateSummary.fromJson(readMap(item)),
      );

  Future<NotificationTemplate> getNotificationTemplate(
    NotificationChannel channel,
    String templateId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      NotificationTemplate.fromJson(
        readMap(
          await _send(
            'getNotificationTemplate',
            'Failed to fetch notification template',
            segments: [channel.value, 'templates', templateId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<NotificationTemplate> createNotificationTemplate(
    NotificationChannel channel,
    CreateNotificationTemplateRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      NotificationTemplate.fromJson(
        readMap(
          await _send(
            'createNotificationTemplate',
            'Failed to create notification template',
            method: 'POST',
            segments: [channel.value, 'templates'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<NotificationTemplate> updateNotificationTemplate(
    NotificationChannel channel,
    String templateId,
    UpdateNotificationTemplateRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      NotificationTemplate.fromJson(
        readMap(
          await _send(
            'updateNotificationTemplate',
            'Failed to update notification template',
            method: 'PUT',
            segments: [channel.value, 'templates', templateId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteNotificationTemplate(
    NotificationChannel channel,
    String templateId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteNotificationTemplate',
        'Failed to delete notification template',
        method: 'DELETE',
        segments: [channel.value, 'templates', templateId],
        url: url,
        fetcher: fetcher,
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
        endpointKey: ManagementEndpointKeys.notificationTemplates,
        collection: 'notification-templates',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
