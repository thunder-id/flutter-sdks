// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import '../models/http_request.dart';
import '../models/thunderid_error.dart';

/// Sends one HTTP request and returns its response, whatever the status. Fails with
/// [ThunderIDErrorCode.networkError] only when the server cannot be reached.
typedef HttpTransport = Future<HttpResponseData> Function(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
);

/// The default [HttpTransport], on `dart:io`.
///
/// Redirects are not followed: a redirect would carry the session handle or the access token to
/// a URL nobody checked, so the `3xx` goes back to the caller instead.
Future<HttpResponseData> ioHttpTransport(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (body != null) {
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final text = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) => responseHeaders[name] = values.join(','));
    return HttpResponseData(statusCode: response.statusCode, headers: responseHeaders, body: text);
  } on IOException catch (e) {
    // The URL is left out: its query can carry personal data.
    throw IAMException(ThunderIDErrorCode.networkError, 'Could not reach ${url.host}', cause: e);
  } finally {
    client.close();
  }
}
