// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

// Kept apart from the other management tests: those initialize the Flutter test binding, which
// replaces dart:io's HttpClient with one that answers every request with HTTP 400.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

void main() {
  group('default authenticated transport', () {
    test('attaches the bearer token and sends the JSON body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? authorization;
      String? body;
      String? method;
      server.listen((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        method = request.method;
        body = await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'id': 'g1', 'name': 'Team', 'ouId': 'ou1'}));
        await request.response.close();
      });

      var tokenReads = 0;
      final live = ThunderIDManagementClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessTokenProvider: () async {
          tokenReads++;
          return 'token-$tokenReads';
        },
      );

      final group = await live.createGroup(const CreateGroupRequest(name: 'Team', ouId: 'ou1'));
      expect(group.id, 'g1');
      expect(method, 'POST');
      expect(authorization, 'Bearer token-1');
      expect(jsonDecode(body!), {'name': 'Team', 'ouId': 'ou1'});

      await live.createGroup(const CreateGroupRequest(name: 'Team', ouId: 'ou1'));
      expect(authorization, 'Bearer token-2', reason: 'the token is read per request, never cached');
    });
  });

}
