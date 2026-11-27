// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

// Shared by the admin widget tests: the connected components gate their actions on the
// provider's capabilities, which are read only for a signed-in user.

/// A platform channel that initializes and reports a signed-in user (`sub: admin`).
Future<Object?> signedInChannel(MethodCall call) async => switch (call.method) {
      'initialize' => true,
      'isSignedIn' => true,
      'getUser' => const {'sub': 'admin'},
      'getAccessToken' => '',
      _ => null,
    };

/// Capabilities that allow every action on [resources].
Map<String, Object?> allowAll([
  List<String> resources = const ['app', 'user', 'group', 'role', 'agent', 'ou'],
]) =>
    {
      'scope': {'type': 'deployment'},
      'resources': {
        for (final resource in resources) resource: {'view': true, 'create': true, 'update': true, 'delete': true},
      },
    };

/// Answers `GET /capabilities` with [capabilities] (or a 500 when null) and sends every other
/// request to [next], so the wrapped server's own request log stays unchanged.
ManagementFetcher withCapabilities(ManagementFetcher next, {Map<String, Object?>? capabilities, int status = 200}) =>
    (request) {
      if (request.method != 'GET' || request.url.path != '/capabilities') return next(request);
      return Future.value(
        ManagementResponse(
          statusCode: status,
          statusText: status == 200 ? 'OK' : 'Error',
          body: jsonEncode(capabilities ?? allowAll()),
        ),
      );
    };
