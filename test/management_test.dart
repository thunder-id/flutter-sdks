// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.thunderid/sdk');
  final List<MethodCall> log = [];
  late ThunderIDClient client;

  void respond(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'initialize') return true;
      return handler(call);
    });
  }

  setUp(() async {
    log.clear();
    respond((_) => null);
    client = ThunderIDClient();
    await client.initialize(const ThunderIDConfig(baseUrl: 'https://localhost:8090'));
  });

  test('management requires initialization', () {
    expect(
      () => ThunderIDClient().applications,
      throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
    );
  });

  test('list sends pagination and parses numbers the Android bridge sends as doubles', () async {
    respond(
      (_) => <Object?, Object?>{
        'totalResults': 1.0,
        'count': 1.0,
        'applications': [
          <Object?, Object?>{'id': 'app-1', 'name': 'App', 'clientId': 'client-1'},
        ],
      },
    );

    final page = await client.applications.list(limit: 5, offset: 10);

    expect(page.totalResults, 1);
    expect(page.applications.single.clientId, 'client-1');
    expect(log.last.method, 'applications.list');
    expect(log.last.arguments, {'limit': 5, 'offset': 10});
  });

  test('users and agents map to their own channel methods', () async {
    respond(
      (call) => switch (call.method) {
        'users.get' => <Object?, Object?>{
            'id': 'u-1',
            'ouId': 'ou',
            'type': 'customer',
            'display': 'Alice',
            'attributes': <Object?, Object?>{
              'name': <Object?, Object?>{'givenName': 'Alice'},
            },
          },
        'agents.list' => <Object?, Object?>{'totalResults': 0, 'startIndex': 1, 'count': 0, 'agents': []},
        _ => null,
      },
    );

    final user = await client.users.get('u-1');
    final agents = await client.agents.list();

    expect(user.display, 'Alice');
    expect((user.attributes['name'] as Map<String, dynamic>)['givenName'], 'Alice');
    expect(agents.agents, isEmpty);
    expect(log.where((c) => c.method != 'initialize').map((c) => c.method), ['users.get', 'agents.list']);
    expect(log[log.length - 2].arguments, {'id': 'u-1'});
  });

  test('create sends the payload and toRequest keeps every server field', () async {
    respond(
      (_) => <Object?, Object?>{
        'id': 'new',
        'name': 'My SPA',
        'createdAt': '2026-01-01',
        'inboundAuthConfig': [
          <Object?, Object?>{
            'type': 'oauth2',
            'config': <Object?, Object?>{
              'grantTypes': ['authorization_code'],
            },
          },
        ],
      },
    );

    final application = await client.applications.create(
      ApplicationRequest(name: 'My SPA', url: 'https://app.example.com'),
    );

    expect(log.last.method, 'applications.create');
    expect(log.last.arguments, {
      'payload': {'name': 'My SPA', 'url': 'https://app.example.com'},
    });
    expect(application.id, 'new');
    final request = application.toRequest().toMap();
    expect(request.containsKey('id'), isFalse);
    expect(request.containsKey('createdAt'), isFalse);
    expect(request['inboundAuthConfig'], isA<List<dynamic>>());
  });

  test('update and delete target the resource', () async {
    respond(
      (call) => call.method == 'agents.update'
          ? <Object?, Object?>{'id': 'ag-1', 'ouId': 'ou', 'type': 'default', 'name': 'Renamed'}
          : null,
    );

    final agent = await client.agents.update('ag-1', UpdateAgentRequest(name: 'Renamed'));
    await client.agents.delete('ag-1');

    expect(agent.name, 'Renamed');
    expect(log[log.length - 2].arguments, {
      'id': 'ag-1',
      'payload': {'name': 'Renamed'},
    });
    expect(log.last.method, 'agents.delete');
    expect(log.last.arguments, {'id': 'ag-1'});
  });

  test('native FORBIDDEN and NOT_FOUND map to their own codes', () async {
    for (final entry in {
      'FORBIDDEN': ThunderIDErrorCode.forbidden,
      'NOT_FOUND': ThunderIDErrorCode.notFound,
    }.entries) {
      respond((_) => throw PlatformException(code: entry.key, message: 'failed'));

      await expectLater(
        client.users.get('u-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', entry.value)),
      );
    }
  });

  test('endpoints travel to the native SDK on initialize', () async {
    final endpointsClient = ThunderIDClient();
    await endpointsClient.initialize(
      const ThunderIDConfig(
        baseUrl: 'https://idp.example.com',
        endpoints: ThunderIDEndpoints(users: 'https://rs.example.com/users'),
      ),
    );

    final args = log.last.arguments as Map<Object?, Object?>;
    expect(args['endpoints'], {'users': 'https://rs.example.com/users'});
  });
}
