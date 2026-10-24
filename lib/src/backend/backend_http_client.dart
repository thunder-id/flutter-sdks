// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../models/http_request.dart';
import '../models/thunderid_error.dart';
import 'backend_client.dart';
import 'http_transport.dart';

/// Sends the app's API requests when sign-in runs on the backend. A request under the API base
/// goes through the backend's proxy with the session handle instead of a token, and the session
/// is refreshed once when the backend reports it expired. A request under `bypass` goes straight
/// to its URL with, unless turned off, the access token the backend issued. Anything else is
/// refused before it is sent.
class BackendHttpClient {
  final BackendClient _backend;
  final HttpTransport _transport;

  BackendHttpClient(this._backend, this._transport);

  Future<HttpResponseData> request(HttpRequestConfig config) async {
    final method = config.method.toUpperCase();
    final body = _encodeBody(config.data);
    // The handle is the backend's credential and the SDK sets it itself; a caller's value is never
    // sent, and never reaches an API outside the backend.
    final headers = {
      for (final entry in config.headers.entries)
        if (entry.key.toLowerCase() != sessionHandleHeader.toLowerCase()) entry.key: entry.value,
      if (config.data != null && config.data is! String && !_hasHeader(config.headers, 'content-type'))
        'Content-Type': 'application/json',
    };

    if (_backend.isBypassed(config.url)) {
      return _sendBypassed(method, Uri.parse(config.url), headers, body);
    }

    final proxyUrl = _backend.toProxyUrl(config.url);
    if (proxyUrl == null) {
      // The URL is left out of the message: its query can carry personal data.
      throw const IAMException(
        ThunderIDErrorCode.backendUnsupportedUrl,
        'The URL is not under the API base or a bypass URL, so it was not sent',
      );
    }

    var response = await _backend.sendThroughProxy(method, proxyUrl, headers, body);
    // Only the backend's own `session_expired` calls for a refresh. Any other 401 is the API's
    // answer and goes back to the caller untouched.
    if (backendErrorOf(response) == 'session_expired' && await _backend.refresh()) {
      response = await _backend.sendThroughProxy(method, proxyUrl, headers, body);
      // A second failure means signed out.
      if (backendErrorOf(response) == 'session_expired') _backend.markSignedOut();
    }
    if (backendErrorOf(response) == 'login_required') _backend.markSignedOut();
    return response;
  }

  /// Sends a request straight to its URL, skipping the proxy, with the access token. When the API
  /// rejects the token, it gets a new one and retries once; a second 401 goes back to the caller.
  Future<HttpResponseData> _sendBypassed(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    if (!_backend.endpoints.attachToken) {
      return _transport(method, url, headers, body);
    }

    final withoutAuthorization = {
      for (final entry in headers.entries)
        if (entry.key.toLowerCase() != 'authorization') entry.key: entry.value,
    };

    Future<HttpResponseData> send({required bool renew}) async {
      final token = await _backend.getAccessToken(renew: renew);
      return _transport(method, url, {...withoutAuthorization, 'Authorization': 'Bearer $token'}, body);
    }

    final response = await send(renew: false);
    if (response.statusCode != 401) return response;
    return send(renew: true);
  }

  static String? _encodeBody(Object? data) {
    if (data == null) return null;
    if (data is String) return data;
    return jsonEncode(data);
  }

  static bool _hasHeader(Map<String, String> headers, String name) =>
      headers.keys.any((key) => key.toLowerCase() == name);
}
