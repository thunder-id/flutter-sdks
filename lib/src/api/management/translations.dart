// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/translation.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Translation operations: `/i18n/languages` and each language's translations.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.i18n] override, then `{baseUrl}/i18n`.
extension TranslationOperations on ThunderIDManagementClient {
  /// Lists the language tags that have translations, such as `en-US`.
  Future<List<String>> getLanguages({String? url, ManagementFetcher? fetcher}) async => readStringList(
        readMap(
          await _send('getLanguages', 'Failed to fetch languages', segments: const ['languages'], url: url, fetcher: fetcher),
        ),
        'languages',
      );

  /// Reads [language]'s translations, or only those of [namespace].
  Future<LanguageTranslations> resolveTranslations(
    String language, {
    String? namespace,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      LanguageTranslations.fromJson(
        readMap(
          await _send(
            'resolveTranslations',
            'Failed to fetch translations',
            segments: ['languages', language, 'translations', 'resolve'],
            query: {'namespace': namespace},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Translation> resolveTranslation(
    String language,
    String namespace,
    String key, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Translation.fromJson(
        readMap(
          await _send(
            'resolveTranslation',
            'Failed to fetch translation',
            segments: [..._keySegments(language, namespace, key), 'resolve'],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Sets many of [language]'s translations at once, keyed by namespace and key.
  Future<LanguageTranslations> setTranslations(
    String language,
    SetTranslationsRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      LanguageTranslations.fromJson(
        readMap(
          await _send(
            'setTranslations',
            'Failed to set translations',
            method: 'POST',
            segments: ['languages', language, 'translations'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Removes every translation set for [language], so its defaults apply again.
  Future<void> deleteTranslations(String language, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteTranslations',
        'Failed to delete translations',
        method: 'DELETE',
        segments: ['languages', language, 'translations'],
        url: url,
        fetcher: fetcher,
      );

  Future<Translation> setTranslation(
    String language,
    String namespace,
    String key,
    SetTranslationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Translation.fromJson(
        readMap(
          await _send(
            'setTranslation',
            'Failed to set translation',
            method: 'POST',
            segments: _keySegments(language, namespace, key),
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteTranslation(
    String language,
    String namespace,
    String key, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteTranslation',
        'Failed to delete translation',
        method: 'DELETE',
        segments: _keySegments(language, namespace, key),
        url: url,
        fetcher: fetcher,
      );

  static List<String> _keySegments(String language, String namespace, String key) =>
      ['languages', language, 'translations', 'ns', namespace, 'keys', key];

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
        endpointKey: ManagementEndpointKeys.i18n,
        collection: 'i18n',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
