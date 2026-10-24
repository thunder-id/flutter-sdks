// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// A request sent through [ThunderIDClient.httpRequest].
class HttpRequestConfig {
  /// The API URL: absolute, or a path starting with `/` relative to [ThunderIDConfig.baseUrl].
  final String url;

  final String method;
  final Map<String, String> headers;

  /// The request body. A [String] is sent as is; anything else is encoded as JSON.
  final Object? data;

  const HttpRequestConfig({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.data,
  });
}

/// The response to an [HttpRequestConfig]. Every status comes back as a response, including a
/// `401` that is the API's own answer; only a failure to reach the server throws.
class HttpResponseData {
  final int statusCode;

  /// Response headers, with lower-cased names.
  final Map<String, String> headers;

  final String body;

  const HttpResponseData({
    required this.statusCode,
    this.headers = const {},
    this.body = '',
  });

  bool get ok => statusCode >= 200 && statusCode < 300;

  /// The body decoded as JSON, or `null` when it is empty or not JSON.
  Object? get data {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
