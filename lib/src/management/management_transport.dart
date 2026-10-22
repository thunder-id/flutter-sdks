// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

/// A management request, handed to a [ManagementFetcher].
class ManagementRequest {
  /// `GET`, `POST`, `PUT`, or `DELETE`.
  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// The JSON-encoded body, or `null` when the request has none.
  final String? body;

  const ManagementRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
  });
}

/// The server's answer to a [ManagementRequest].
class ManagementResponse {
  final int statusCode;
  final String statusText;
  final String body;

  const ManagementResponse({required this.statusCode, this.statusText = '', this.body = ''});

  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// Sends a management request (spec "Management operations", requirement 3).
///
/// A fetcher replaces the whole transport, authorization included: the SDK's default fetcher
/// attaches the signed-in user's access token, and a replacement that talks to the ThunderID
/// server directly has to do the same, for example with `ThunderIDClient.getAccessToken()`.
/// It applies to management operations only; sign-in, token, and flow requests keep using the
/// native SDK's transport.
typedef ManagementFetcher = Future<ManagementResponse> Function(ManagementRequest request);

/// Returns the signed-in user's access token.
typedef AccessTokenProvider = Future<String> Function();

/// The SDK's default management transport: `dart:io` [HttpClient], authorized with the token
/// [accessTokenProvider] returns. The token is read per request and never cached here, so a
/// refreshed token is picked up immediately (spec "Management operations", requirement 1).
///
/// [allowInsecureConnections] mirrors `ThunderIDConfig.allowInsecureConnections`: it accepts
/// certificates that cannot be verified, for a development server's self-signed certificate.
/// Never enable it in a release build.
ManagementFetcher createAuthenticatedFetcher(
  AccessTokenProvider accessTokenProvider, {
  bool allowInsecureConnections = false,
}) =>
    (request) async {
      final token = await accessTokenProvider();
      final client = HttpClient();
      if (allowInsecureConnections) {
        client.badCertificateCallback = (certificate, host, port) => true;
      }
      try {
        final httpRequest = await client.openUrl(request.method, request.url);
        request.headers.forEach(httpRequest.headers.set);
        if (token.isNotEmpty) {
          httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        final body = request.body;
        if (body != null) {
          final bytes = utf8.encode(body);
          httpRequest.contentLength = bytes.length;
          httpRequest.add(bytes);
        }
        final response = await httpRequest.close();
        final responseBody = await response.transform(utf8.decoder).join();
        return ManagementResponse(
          statusCode: response.statusCode,
          statusText: response.reasonPhrase,
          body: responseBody,
        );
      } finally {
        client.close();
      }
    };
