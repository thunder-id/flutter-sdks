// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _baseUrl = 'https://idp.example.com';

Capabilities _caps(Map<String, Map<String, bool>> resources) =>
    Capabilities(scope: const CapabilityScope(type: 'deployment'), resources: resources);

/// A read the test finishes by hand, so it can observe loading and supersede reads.
class _Reads {
  final List<Completer<Capabilities>> pending = [];
  int get count => pending.length;

  Future<Capabilities> call() {
    final completer = Completer<Capabilities>();
    pending.add(completer);
    return completer.future;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('getCapabilities', () {
    final body = jsonEncode({
      'scope': {'type': 'ou', 'ouId': 'ou-1'},
      'resources': {
        'app': {'view': true, 'create': false, 'odd': 'yes'},
        'broken': 'not a map',
      },
    });
    final requests = <ManagementRequest>[];
    Future<ManagementResponse> answer(ManagementRequest request) async {
      requests.add(request);
      return ManagementResponse(statusCode: 200, statusText: 'OK', body: body);
    }

    setUp(requests.clear);

    test('reads {baseUrl}/capabilities and parses leniently', () async {
      final caps = await ThunderIDManagementClient(baseUrl: '$_baseUrl/', fetcher: answer).getCapabilities();
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(), '$_baseUrl/capabilities');
      expect(caps.scope.type, 'ou');
      expect(caps.scope.ouId, 'ou-1');
      expect(caps.resources, {
        'app': {'view': true, 'create': false},
      });
      expect(caps.can('app'), isTrue);
      expect(caps.can('app', 'create'), isFalse);
      expect(caps.can('app', 'odd'), isFalse);
      expect(caps.can('user'), isFalse);
    });

    test('keeps an unknown scope type as sent', () {
      expect(Capabilities.fromJson({'scope': {'type': 'tenant'}}).scope.type, 'tenant');
      expect(Capabilities.fromJson(const {}).resources, isEmpty);
    });

    test('url beats the endpoints override, which beats baseUrl', () async {
      final client = ThunderIDManagementClient(
        baseUrl: _baseUrl,
        endpoints: const {ManagementEndpointKeys.capabilities: 'https://mgmt.example.com/caps'},
        fetcher: answer,
      );
      await client.getCapabilities();
      await client.getCapabilities(url: 'https://other.example.com/c');
      expect(requests.map((r) => r.url.toString()), ['https://mgmt.example.com/caps', 'https://other.example.com/c']);
    });

    test('EndpointsConfig.capabilities is the override key', () {
      expect(const EndpointsConfig(capabilities: 'https://e/cap').collections, {'capabilities': 'https://e/cap'});
    });

    test('a per-call fetcher beats the client fetcher', () async {
      final perCall = <ManagementRequest>[];
      await ThunderIDManagementClient(baseUrl: _baseUrl, fetcher: answer).getCapabilities(
        fetcher: (request) async {
          perCall.add(request);
          return ManagementResponse(statusCode: 200, body: body);
        },
      );
      expect(perCall, hasLength(1));
      expect(requests, isEmpty);
    });

    test('a failure raises the API error', () async {
      final client = ThunderIDManagementClient(
        baseUrl: _baseUrl,
        fetcher: (_) async => const ManagementResponse(statusCode: 403, statusText: 'Forbidden'),
      );
      await expectLater(
        client.getCapabilities(),
        throwsA(
          isA<IAMApiException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.forbidden)
              .having((e) => e.operation, 'operation', 'getCapabilities'),
        ),
      );
    });
  });

  group('RecordAccess', () {
    // [isReadOnly, isOwnedByOU, update, delete] -> [readOnly, canDelete, canChangeState]
    final table = <List<Object?>>[
      [null, null, true, true, false, true, true],
      [false, true, true, true, false, true, true],
      [true, null, true, true, true, false, true],
      [null, false, true, true, true, false, false],
      [true, false, true, true, true, false, false],
      [null, null, false, true, true, true, false],
      [null, null, true, false, false, false, true],
      [null, null, false, false, true, false, false],
    ];
    for (final row in table) {
      test('isReadOnly ${row[0]}, isOwnedByOU ${row[1]}, update ${row[2]}, delete ${row[3]}', () {
        bool can(String resource, [String action = 'view']) =>
            resource == 'user' && ((action == 'update' && row[2] == true) || (action == 'delete' && row[3] == true));
        final access = RecordAccess.from(
          'user',
          isReadOnly: row[0] as bool?,
          isOwnedByOU: row[1] as bool?,
          can: can,
        );
        expect([access.readOnly, access.canDelete, access.canChangeState], row.sublist(4));
      });
    }
  });

  group('CapabilitiesNotifier', () {
    late _Reads reads;
    late List<String> permissions;
    late CapabilitiesNotifier notifier;
    const ada = User({'sub': 'ada', 'ouId': 'ou-1'});

    setUp(() {
      reads = _Reads();
      permissions = ['b', 'a'];
      notifier = CapabilitiesNotifier(read: reads.call, grantedPermissions: () async => permissions, user: ada);
    });

    tearDown(() => notifier.dispose());

    test('reads nothing until load', () async {
      await _settle();
      expect(reads.count, 0);
      expect(notifier.isLoading, isFalse);
      expect(notifier.can('app'), isFalse);
    });

    test('can is false while loading, true for reported actions, false otherwise; default action is view',
        () async {
      notifier.load();
      expect(notifier.isLoading, isTrue);
      expect(notifier.can('app'), isFalse);
      await _settle();
      reads.pending.single.complete(
        _caps({
          'app': {'view': true, 'update': false},
        }),
      );
      await _settle();
      expect(notifier.isLoading, isFalse);
      expect(notifier.can('app'), isTrue);
      expect(notifier.can('app', 'view'), isTrue);
      expect(notifier.can('app', 'update'), isFalse);
      expect(notifier.can('app', 'delete'), isFalse);
      expect(notifier.can('user'), isFalse);
      expect(notifier.recordAccess('app').readOnly, isTrue);
    });

    test('a failed read never allows anything, is reported apart from a denial, and retry reads again', () async {
      notifier.load();
      await _settle();
      reads.pending.single.completeError(const IAMException(ThunderIDErrorCode.networkError, 'down'));
      await _settle();
      expect(notifier.error, isA<IAMException>());
      expect(notifier.isLoading, isFalse);
      expect(notifier.capabilities, isNull);
      for (final resource in ['app', 'user', 'group', 'role', 'agent', 'ou']) {
        for (final action in ['view', 'create', 'update', 'delete']) {
          expect(notifier.can(resource, action), isFalse, reason: '$resource/$action');
        }
      }
      final access = notifier.recordAccess('app');
      expect([access.readOnly, access.canDelete, access.canChangeState], [true, false, false]);

      notifier.load();
      await _settle();
      expect(reads.count, 1, reason: 'load does not re-read a failure; retry does');

      notifier.retry();
      expect(notifier.isLoading, isTrue);
      expect(notifier.error, isNull);
      await _settle();
      expect(reads.count, 2);
      reads.pending.last.complete(
        _caps({
          'app': {'view': true},
        }),
      );
      await _settle();
      expect(notifier.can('app'), isTrue);
    });

    test('several consumers share one read', () async {
      notifier
        ..load()
        ..load()
        ..load();
      await _settle();
      notifier.load();
      expect(reads.count, 1);
    });

    Future<void> loaded() async {
      notifier.load();
      await _settle();
      reads.pending.last.complete(_caps(const {}));
      await _settle();
    }

    test('reads again when the user changes', () async {
      await loaded();
      notifier.setUser(const User({'sub': 'grace', 'ouId': 'ou-1'}));
      await _settle();
      expect(reads.count, 2);
    });

    test('reads again when the organization unit changes', () async {
      await loaded();
      notifier.setUser(const User({'sub': 'ada', 'ouId': 'ou-2'}));
      await _settle();
      expect(reads.count, 2);
    });

    test('reads again when the granted permissions change, not when only their order does', () async {
      await loaded();
      permissions = ['a', 'b'];
      notifier.setUser(const User({'sub': 'ada', 'ouId': 'ou-1', 'name': 'Ada'}));
      await _settle();
      expect(reads.count, 1);
      permissions = ['a', 'b', 'c'];
      notifier.setUser(ada);
      await _settle();
      expect(reads.count, 2);
    });

    test('does not read on a user change before first use', () async {
      notifier.setUser(const User({'sub': 'grace'}));
      await _settle();
      expect(reads.count, 0);
    });

    test('sign-out clears, and the next sign-in reads again', () async {
      notifier.load();
      await _settle();
      reads.pending.single.complete(
        _caps({
          'app': {'view': true},
        }),
      );
      await _settle();
      expect(notifier.can('app'), isTrue);

      notifier.setUser(null);
      expect(notifier.capabilities, isNull);
      expect(notifier.can('app'), isFalse);
      notifier.retry();
      expect(reads.count, 1, reason: 'nothing to read while signed out');

      notifier.setUser(ada);
      await _settle();
      expect(reads.count, 2);
    });

    test('a superseded read is discarded', () async {
      notifier.load();
      await _settle();
      notifier.setUser(const User({'sub': 'grace'}));
      await _settle();
      expect(reads.count, 2);
      reads.pending.last.complete(
        _caps({
          'user': {'view': true},
        }),
      );
      await _settle();
      reads.pending.first.complete(
        _caps({
          'app': {'view': true},
        }),
      );
      await _settle();
      expect(notifier.can('user'), isTrue);
      expect(notifier.can('app'), isFalse);
    });

    test('a read that finishes after sign-out is discarded', () async {
      notifier.load();
      await _settle();
      notifier.setUser(null);
      reads.pending.single.complete(
        _caps({
          'app': {'view': true},
        }),
      );
      await _settle();
      expect(notifier.can('app'), isFalse);
      expect(notifier.isLoading, isFalse);
    });
  });
}
