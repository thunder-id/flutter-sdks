// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// A fake management server: answers by `METHOD path` and records every request.
class _FakeServer {
  final Map<String, ManagementResponse> routes = {};
  final List<ManagementRequest> requests = [];

  void on(String method, String path, Object? body, {int status = 200}) {
    routes['$method $path'] = ManagementResponse(
      statusCode: status,
      statusText: 'OK',
      body: body == null ? '' : jsonEncode(body),
    );
  }

  Future<ManagementResponse> fetch(ManagementRequest request) async {
    requests.add(request);
    return routes['${request.method} ${request.url.path}'] ??
        const ManagementResponse(statusCode: 404, statusText: 'Not Found');
  }

  Iterable<ManagementRequest> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);
}

Widget _app(_FakeServer server, Widget child) => MaterialApp(
      home: ThunderIDProvider(
        config: ThunderIDConfig(
          baseUrl: 'https://idp.example.com',
          clientId: 'test',
          http: ThunderIDHttpConfig(fetcher: server.fetch),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

Widget _base(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

const _granted = [
  RoleResourcePermissions(resourceServerId: 'rs1', permissions: ['orders:read']),
];

void main() {
  late _FakeServer server;

  setUp(() {
    server = _FakeServer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async => call.method == 'initialize' ? true : (call.method == 'isSignedIn' ? false : null),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('BaseRolePermissions', () {
    testWidgets('is read-only without callbacks', (tester) async {
      await tester.pumpWidget(_base(const BaseRolePermissions(permissions: _granted)));

      expect(find.text('orders:read'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-role-permissions-add')), findsNothing);
      expect(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read')), findsNothing);
    });

    testWidgets('adds a permission picked from a resource server, offering only ungranted ones', (tester) async {
      final added = <RolePermission>[];
      await tester.pumpWidget(
        _base(
          BaseRolePermissions(
            permissions: _granted,
            resourceServerNames: const {'rs1': 'Orders API'},
            availablePermissions: const {
              'rs1': ['orders:read', 'orders:write'],
            },
            onAdd: added.add,
          ),
        ),
      );

      expect(find.text('Resource server'), findsOneWidget);
      await tester.tap(find.byKey(const Key('thunderid-field-role-permissions-identity')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('thunderid-field-role-permissions-identity-option-orders:read')), findsNothing);
      await tester.tap(find.text('orders:write').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-add')));
      await tester.pumpAndSettle();

      expect(added, [const RolePermission(resourceServerId: 'rs1', permission: 'orders:write')]);
    });

    testWidgets('removes a permission only after confirmation', (tester) async {
      final removed = <RolePermission>[];
      await tester.pumpWidget(_base(BaseRolePermissions(permissions: _granted, onRemove: removed.add)));

      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read')));
      await tester.pumpAndSettle();
      expect(removed, isEmpty, reason: 'the first tap only asks');
      expect(find.text('Remove orders:read from this role?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read-confirm')));
      await tester.pumpAndSettle();
      expect(removed, [const RolePermission(resourceServerId: 'rs1', permission: 'orders:read')]);
    });

    testWidgets('hands a builder the add and remove callbacks only when editable', (tester) async {
      RolePermissionsState? readOnly;
      RolePermissionsState? editable;
      await tester.pumpWidget(
        _base(
          Column(
            children: [
              BaseRolePermissions(
                permissions: _granted,
                builder: (context, state) {
                  readOnly = state;
                  return const SizedBox();
                },
              ),
              BaseRolePermissions(
                permissions: _granted,
                availablePermissions: const {
                  'rs1': ['orders:write'],
                },
                onAdd: (_) {},
                onRemove: (_) {},
                builder: (context, state) {
                  editable = state;
                  return Text('custom ${state.permissions.single.permissions.single}');
                },
              ),
            ],
          ),
        ),
      );

      expect(find.text('custom orders:read'), findsOneWidget);
      expect(readOnly!.onAdd, isNull);
      expect(readOnly!.onRemove, isNull);
      expect(readOnly!.availablePermissions, isNull);
      expect(editable!.onAdd, isNotNull);
      expect(editable!.onRemove, isNotNull);
      expect(editable!.availablePermissions, {
        'rs1': ['orders:write'],
      });
    });
  });

  group('RolePermissions', () {
    void serve({bool readOnly = false}) {
      server.on('GET', '/roles/r1', {
        'id': 'r1',
        'name': 'Auditor',
        'ouId': 'ou1',
        'description': 'Reads orders',
        'isReadOnly': readOnly,
        'permissions': [
          {
            'resourceServerId': 'rs1',
            'permissions': ['orders:read'],
          },
        ],
      });
      server.on('GET', '/resource-servers', {
        'totalResults': 2,
        'resourceServers': [
          {'id': 'rs1', 'name': 'Orders API', 'identifier': 'orders', 'ouId': 'ou1'},
          {'id': 'rs2', 'name': 'Billing API', 'identifier': 'billing', 'ouId': 'ou1'},
        ],
      });
      server.on('GET', '/resource-servers/rs1/actions', {
        'totalResults': 2,
        'actions': [
          {'id': 'a1', 'name': 'Read', 'handle': 'read', 'permission': 'orders:read'},
          {'id': 'a2', 'name': 'Write', 'handle': 'write', 'permission': 'orders:write'},
        ],
      });
      server.on('GET', '/resource-servers/rs2/actions', {
        'totalResults': 1,
        'actions': [
          {'id': 'a3', 'name': 'Pay', 'handle': 'pay', 'permission': 'billing:pay'},
        ],
      });
      server.on('PUT', '/roles/r1', {'id': 'r1', 'name': 'Auditor', 'ouId': 'ou1'});
    }

    testWidgets('loads no resource servers and offers no editing by default', (tester) async {
      serve();
      await tester.pumpWidget(_app(server, const RolePermissions(roleId: 'r1')));
      await tester.pumpAndSettle();

      expect(find.text('orders:read'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-role-permissions-add')), findsNothing);
      expect(server.where('GET', '/resource-servers'), isEmpty);
    });

    testWidgets('adds a permission through updateRole when editable', (tester) async {
      serve();
      await tester.pumpWidget(_app(server, const RolePermissions(roleId: 'r1', editable: true)));
      await tester.pumpAndSettle();

      expect(find.text('Orders API'), findsWidgets, reason: 'resource server names come from the server');
      await tester.tap(find.byKey(const Key('thunderid-field-role-permissions-identityType')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Billing API').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-field-role-permissions-identity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('billing:pay').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-add')));
      await tester.pumpAndSettle();

      expect(jsonDecode(server.where('PUT', '/roles/r1').single.body!), {
        'name': 'Auditor',
        'ouId': 'ou1',
        'description': 'Reads orders',
        'permissions': [
          {
            'resourceServerId': 'rs1',
            'permissions': ['orders:read'],
          },
          {
            'resourceServerId': 'rs2',
            'permissions': ['billing:pay'],
          },
        ],
      });
      expect(server.where('GET', '/roles/r1').length, 2, reason: 'the update reloads the role');
    });

    testWidgets('removes a permission through updateRole after confirmation', (tester) async {
      serve();
      await tester.pumpWidget(_app(server, const RolePermissions(roleId: 'r1', editable: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read')));
      await tester.pumpAndSettle();
      expect(server.where('PUT', '/roles/r1'), isEmpty);
      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read-confirm')));
      await tester.pumpAndSettle();

      expect((jsonDecode(server.where('PUT', '/roles/r1').single.body!) as Map)['permissions'], isEmpty);
    });

    testWidgets('offers no editing for a read-only role', (tester) async {
      serve(readOnly: true);
      await tester.pumpWidget(_app(server, const RolePermissions(roleId: 'r1', editable: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-action-role-permissions-add')), findsNothing);
      expect(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read')), findsNothing);
    });

    testWidgets('shows a translated message when the update fails', (tester) async {
      serve();
      server.on('PUT', '/roles/r1', {'description': 'raw server text'}, status: 400);
      await tester.pumpWidget(_app(server, const RolePermissions(roleId: 'r1', editable: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Could not update the permissions. Please try again.'), findsOneWidget);
      expect(find.textContaining('raw server text'), findsNothing);
    });

    testWidgets('RoleDetails passes editable through to its permissions', (tester) async {
      serve();
      server.on('GET', '/roles/r1/assignments', {'totalResults': 0, 'assignments': <Object?>[]});
      await tester.pumpWidget(_app(server, const RoleDetails(roleId: 'r1', editable: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-action-role-permissions-add')), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-role-permissions-remove-rs1-orders:read')), findsOneWidget);
    });
  });
}
