// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

String _jwt(Map<String, Object?> payload) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(payload)}.sig';
}

void main() {
  group('hasPermission', () {
    test('a permission covers itself and everything under it', () {
      expect(hasPermission(['system'], 'system:user:view'), isTrue);
      expect(hasPermission(['system:user'], 'system:user:view'), isTrue);
      expect(hasPermission(['system:user:view'], 'system:user:view'), isTrue);
    });

    test('does not match siblings, parents, or bare prefixes', () {
      expect(hasPermission(['system:user:view'], 'system:user'), isFalse);
      expect(hasPermission(['system:group'], 'system:user:view'), isFalse);
      expect(hasPermission(['sys'], 'system:user'), isFalse);
      expect(hasPermission(const [], 'system'), isFalse);
    });

    test('an empty requirement is always covered', () {
      expect(hasPermission(const [], ''), isTrue);
    });
  });

  group('getTokenPermissions', () {
    test('reads a space-separated scope claim', () {
      expect(getTokenPermissions(_jwt({'scope': 'openid  system:user:view system'})), [
        'openid',
        'system:user:view',
        'system',
      ]);
    });

    test('prefers a scopes list claim', () {
      expect(
        getTokenPermissions(
          _jwt({
            'scopes': ['a', 1, 'b'],
            'scope': 'ignored',
          }),
        ),
        ['a', 'b'],
      );
    });

    test('returns nothing for an unreadable token', () {
      expect(getTokenPermissions(null), isEmpty);
      expect(getTokenPermissions('opaque-token'), isEmpty);
      expect(getTokenPermissions('a.!!!.c'), isEmpty);
      expect(getTokenPermissions(_jwt({'sub': 'u1'})), isEmpty);
    });

    test('GrantedPermissionsNotifier checks with the hierarchy', () async {
      final notifier = GrantedPermissionsNotifier(() async => _jwt({'scope': 'system:user'}));
      addTearDown(notifier.dispose);
      expect(notifier.isLoading, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.isLoading, isFalse);
      expect(notifier.can('system:user:view'), isTrue);
      expect(notifier.can('system:group:view'), isFalse);

      final signedOut = GrantedPermissionsNotifier(() async => throw StateError('no token'), signedIn: false);
      addTearDown(signedOut.dispose);
      expect(signedOut.isLoading, isFalse);
      expect(signedOut.permissions, isEmpty);
    });
  });

  group('toManagementErrorMessage', () {
    String t(String key) => 'T($key)';

    test('maps 403 and 404 to their own messages and anything else to the fallback', () {
      const forbidden = IAMApiException(
        ThunderIDErrorCode.forbidden,
        'Failed',
        statusCode: 403,
        operation: 'getRoles',
        responseBody: 'server secret text',
      );
      const notFound = IAMApiException(ThunderIDErrorCode.notFound, 'Failed', statusCode: 404, operation: 'getRole');
      const server = IAMApiException(ThunderIDErrorCode.serverError, 'Failed', statusCode: 500, operation: 'getRole');

      expect(toManagementErrorMessage(t, forbidden, 'fallback'), 'T(admin.common.errors.forbidden)');
      expect(toManagementErrorMessage(t, notFound, 'fallback'), 'T(admin.common.errors.not_found)');
      expect(toManagementErrorMessage(t, server, 'fallback'), 'T(fallback)');
      expect(toManagementErrorMessage(t, StateError('x'), 'fallback'), 'T(fallback)');
      expect(toManagementErrorMessage(t, null, 'fallback'), isNull);
    });
  });

  group('resolveManagedIdentityName', () {
    test('prefers display, then name, then name attributes, then username, then id', () {
      expect(resolveManagedIdentityName(id: 'u1', display: 'Shown', name: 'N'), 'Shown');
      expect(resolveManagedIdentityName(id: 'u1', name: 'N'), 'N');
      expect(resolveManagedIdentityName(id: 'u1', attributes: {'name': 'Full'}), 'Full');
      expect(
        resolveManagedIdentityName(id: 'u1', attributes: {'given_name': 'Ada', 'family_name': 'Lovelace'}),
        'Ada Lovelace',
      );
      expect(resolveManagedIdentityName(id: 'u1', attributes: {'username': 'ada'}), 'ada');
      expect(resolveManagedIdentityName(id: 'u1'), 'u1');
    });
  });

  group('ManagementResources', () {
    test('a mutation reloads the queries it invalidates, and only those', () async {
      var userLoads = 0;
      var roleLoads = 0;
      final client = ThunderIDManagementClient(
        baseUrl: 'https://idp.example.com',
        fetcher: (request) async {
          final path = request.url.path;
          if (request.method == 'GET' && path == '/users') {
            userLoads++;
            return const ManagementResponse(statusCode: 200, body: '{"users":[],"totalResults":0}');
          }
          if (request.method == 'GET' && path == '/roles') {
            roleLoads++;
            return const ManagementResponse(statusCode: 200, body: '{"roles":[],"totalResults":0}');
          }
          return const ManagementResponse(statusCode: 201, body: '{"id":"u1","ouId":"ou1","type":"t"}');
        },
      );
      final resources = ManagementResources(client);
      final users = resources.usersQuery(limit: 20);
      final roles = resources.rolesQuery();
      ManagedUser? created;
      final create = resources.createUserMutation(onSuccess: (user, _) => created = user);
      addTearDown(() {
        users.dispose();
        roles.dispose();
        create.dispose();
      });

      await Future<void>.delayed(Duration.zero);
      expect(users.isLoading, isFalse);
      expect(users.data?.items, isEmpty);
      expect(userLoads, 1);
      expect(roleLoads, 1);

      await create.mutate(const CreateManagedUserRequest(ouId: 'ou1', type: 't'));
      await Future<void>.delayed(Duration.zero);
      expect(created?.id, 'u1');
      expect(userLoads, 2, reason: 'createUser invalidates [users]');
      expect(roleLoads, 1);
    });

    test('a failed query reports its error and a failed mutation does not throw from mutate', () async {
      final client = ThunderIDManagementClient(
        baseUrl: 'https://idp.example.com',
        fetcher: (_) async => const ManagementResponse(statusCode: 403, statusText: 'Forbidden'),
      );
      final resources = ManagementResources(client);
      final roles = resources.rolesQuery();
      final delete = resources.deleteRoleMutation();
      addTearDown(() {
        roles.dispose();
        delete.dispose();
      });

      await Future<void>.delayed(Duration.zero);
      expect((roles.error! as IAMException).code, ThunderIDErrorCode.forbidden);

      await delete.mutate('r1');
      expect((delete.error! as IAMException).code, ThunderIDErrorCode.forbidden);
      await expectLater(delete.mutateAsync('r1'), throwsA(isA<IAMApiException>()));
    });

    test('a disabled query or one without an id does not load', () async {
      var loads = 0;
      final client = ThunderIDManagementClient(
        baseUrl: 'https://idp.example.com',
        fetcher: (_) async {
          loads++;
          return const ManagementResponse(statusCode: 200, body: '{}');
        },
      );
      final resources = ManagementResources(client);
      final role = resources.roleQuery(null);
      final users = resources.usersQuery(enabled: false);
      addTearDown(() {
        role.dispose();
        users.dispose();
      });
      await Future<void>.delayed(Duration.zero);
      expect(loads, 0);
      expect(role.isLoading, isFalse);
    });
  });
}
