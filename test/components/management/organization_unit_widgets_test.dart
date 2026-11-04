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
      statusText: status == 200 ? 'OK' : 'Error',
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

  Object? lastBody(String method, String path) => jsonDecode(where(method, path).last.body!);
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

Widget _bare(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _key(String key) => find.byKey(Key(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Map<String, Object?> _error(String code) => {'code': code, 'message': 'server text', 'description': 'never shown'};

const _engineering = {'id': 'ou-eng', 'handle': 'engineering', 'name': 'Engineering', 'description': 'Builders'};
const _sales = {'id': 'ou-sales', 'handle': 'sales', 'name': 'Sales'};

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      null,
    );
  });

  group('OrganizationUnitList', () {
    testWidgets('lists the root units and reports selection', (tester) async {
      server.on('GET', '/organization-units', {
        'totalResults': 2,
        'organizationUnits': [_engineering, _sales],
      });
      BasicOrganizationUnit? selected;
      await tester.pumpWidget(_app(server, OrganizationUnitList(onSelect: (unit) => selected = unit)));
      await tester.pumpAndSettle();

      expect(find.text('Organization units'), findsOneWidget);
      expect(find.text('Engineering'), findsOneWidget);
      await _tap(tester, _key('thunderid-admin-organization-unit-list-row-ou-sales'));
      expect(selected?.handle, 'sales');
    });

    testWidgets('lists the children of parentId', (tester) async {
      server.on('GET', '/organization-units/ou-eng/ous', {
        'totalResults': 1,
        'organizationUnits': [
          {'id': 'ou-platform', 'handle': 'platform', 'name': 'Platform'},
        ],
      });
      await tester.pumpWidget(_app(server, const OrganizationUnitList(parentId: 'ou-eng')));
      await tester.pumpAndSettle();

      expect(find.text('Platform'), findsOneWidget);
      expect(server.where('GET', '/organization-units'), isEmpty);
    });

    testWidgets('hands rows to a custom builder', (tester) async {
      server.on('GET', '/organization-units', {
        'totalResults': 1,
        'organizationUnits': [_engineering],
      });
      await tester.pumpWidget(
        _app(
          server,
          OrganizationUnitList(
            builder: (context, list) => Column(children: [for (final u in list.rows) Text('unit ${u.handle}')]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('unit engineering'), findsOneWidget);
      expect(_key('thunderid-admin-organization-unit-list'), findsNothing);
    });
  });

  group('OrganizationUnitCreate', () {
    testWidgets('creates the unit under a fixed parent', (tester) async {
      server.on('POST', '/organization-units', {'id': 'ou-new', 'handle': 'platform', 'name': 'Platform'});
      OrganizationUnit? created;
      await tester.pumpWidget(
        _app(server, OrganizationUnitCreate(parentId: 'ou-eng', onCreated: (unit) => created = unit)),
      );
      await tester.pumpAndSettle();
      expect(_key('thunderid-field-organization-unit-create-parent'), findsNothing);
      expect(server.where('GET', '/organization-units'), isEmpty, reason: 'no parents to pick');

      await tester.enterText(_key('thunderid-field-organization-unit-create-name'), 'Platform');
      await tester.enterText(_key('thunderid-field-organization-unit-create-handle'), 'platform');
      await tester.pump();
      await _tap(tester, _key('thunderid-action-organization-unit-create-submit'));

      expect(server.lastBody('POST', '/organization-units'), {
        'handle': 'platform',
        'name': 'Platform',
        'parent': 'ou-eng',
      });
      expect(created?.id, 'ou-new');
    });

    testWidgets('offers the root units as parents, or none', (tester) async {
      server
        ..on('GET', '/organization-units', {
          'totalResults': 1,
          'organizationUnits': [_engineering],
        })
        ..on('POST', '/organization-units', {'id': 'ou-new', 'handle': 'emea', 'name': 'EMEA'});
      await tester.pumpWidget(_app(server, const OrganizationUnitCreate()));
      await tester.pumpAndSettle();

      await tester.enterText(_key('thunderid-field-organization-unit-create-name'), 'EMEA');
      await tester.enterText(_key('thunderid-field-organization-unit-create-handle'), 'emea');
      await tester.pump();
      await _tap(tester, _key('thunderid-action-organization-unit-create-submit'));
      expect((server.lastBody('POST', '/organization-units')! as Map)['parent'], isNull);

      await _tap(tester, _key('thunderid-field-organization-unit-create-parent'));
      await tester.tap(find.text('Engineering').last);
      await tester.pumpAndSettle();
      await _tap(tester, _key('thunderid-action-organization-unit-create-submit'));
      expect((server.lastBody('POST', '/organization-units')! as Map)['parent'], 'ou-eng');
    });

    for (final (code, message) in [
      ('OU-1004', 'An organization unit with this name already exists here.'),
      ('OU-1008', 'An organization unit with this handle already exists here.'),
    ]) {
      testWidgets('maps $code to its own message', (tester) async {
        server.on('POST', '/organization-units', _error(code), status: 409);
        await tester.pumpWidget(_app(server, const OrganizationUnitCreate(parentId: 'ou-eng')));
        await tester.pumpAndSettle();

        await tester.enterText(_key('thunderid-field-organization-unit-create-name'), 'Platform');
        await tester.enterText(_key('thunderid-field-organization-unit-create-handle'), 'platform');
        await tester.pump();
        await _tap(tester, _key('thunderid-action-organization-unit-create-submit'));
        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('server text'), findsNothing);
      });
    }

    testWidgets('BaseOrganizationUnitCreate hands its values to a custom builder', (tester) async {
      CreateOrganizationUnitRequest? submitted;
      OrganizationUnitFormState? form;
      await tester.pumpWidget(
        _bare(
          BaseOrganizationUnitCreate(
            parents: const [AdminSelectOption(value: 'ou-eng', label: 'Engineering')],
            onSubmit: (request) => submitted = request,
            builder: (context, state) {
              form = state;
              return Text('valid: ${state.isValid}, parents: ${state.parents.length}');
            },
          ),
        ),
      );
      expect(find.text('valid: false, parents: 1'), findsOneWidget);
      form!
        ..onNameChanged('Platform')
        ..onHandleChanged('platform');
      form!.onParentChanged!('ou-eng');
      await tester.pump();
      form!.submit();
      expect(submitted?.toJson(), {'handle': 'platform', 'name': 'Platform', 'parent': 'ou-eng'});
    });
  });

  group('OrganizationUnitDetails', () {
    void serveUnit() {
      server
        ..on('GET', '/organization-units/ou-eng', {..._engineering, 'parent': 'ou-root', 'themeId': 'theme-1'})
        ..on('GET', '/organization-units/ou-eng/ous', {
          'totalResults': 1,
          'organizationUnits': [
            {'id': 'ou-platform', 'handle': 'platform', 'name': 'Platform'},
          ],
        })
        ..on('GET', '/organization-units/ou-eng/users', {
          'totalResults': 1,
          'users': [
            {'id': 'u1', 'display': 'Ada Lovelace'},
          ],
        })
        ..on('GET', '/organization-units/ou-eng/groups', {
          'totalResults': 1,
          'groups': [
            {'id': 'g1', 'name': 'Admins'},
          ],
        })
        ..on('GET', '/organization-units/ou-eng/roles', {
          'totalResults': 1,
          'roles': [
            {'id': 'r1', 'name': 'Auditor'},
          ],
        });
    }

    testWidgets('shows the overview, children, users, groups and roles, read only by default', (tester) async {
      serveUnit();
      BasicOrganizationUnit? opened;
      await tester.pumpWidget(
        _app(server, OrganizationUnitDetails(organizationUnitId: 'ou-eng', onSelectChild: (u) => opened = u)),
      );
      await tester.pumpAndSettle();

      expect(find.text('engineering'), findsWidgets);
      expect(find.text('ou-root'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Admins'), findsOneWidget);
      expect(find.text('Auditor'), findsOneWidget);
      expect(_key('thunderid-action-organization-unit-details-edit'), findsNothing);
      expect(_key('thunderid-action-organization-unit-details-delete'), findsNothing);

      await _tap(tester, _key('thunderid-admin-organization-unit-details-children-row-ou-platform'));
      expect(opened?.id, 'ou-platform');
    });

    testWidgets('saves an edit as a full update that keeps the other settings', (tester) async {
      serveUnit();
      server.on('PUT', '/organization-units/ou-eng', {..._engineering, 'name': 'Eng'});
      await tester.pumpWidget(
        _app(server, const OrganizationUnitDetails(organizationUnitId: 'ou-eng', editable: true)),
      );
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-organization-unit-details-edit'));
      await tester.enterText(_key('thunderid-field-organization-unit-details-name'), 'Eng');
      await tester.pump();
      await _tap(tester, _key('thunderid-action-organization-unit-details-save'));

      expect(server.lastBody('PUT', '/organization-units/ou-eng'), {
        'handle': 'engineering',
        'name': 'Eng',
        'description': 'Builders',
        'themeId': 'theme-1',
        'parent': 'ou-root',
      });
    });

    testWidgets('maps OU-1012 on an update to the declarative message', (tester) async {
      serveUnit();
      server.on('PUT', '/organization-units/ou-eng', _error('OU-1012'), status: 400);
      await tester.pumpWidget(
        _app(server, const OrganizationUnitDetails(organizationUnitId: 'ou-eng', editable: true)),
      );
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-organization-unit-details-edit'));
      await _tap(tester, _key('thunderid-action-organization-unit-details-save'));
      expect(
        find.text('This organization unit is defined in declarative configuration and cannot be changed.'),
        findsOneWidget,
      );
    });

    testWidgets('deletes only after confirmation, and maps OU-1006 to the children message', (tester) async {
      serveUnit();
      server.on('DELETE', '/organization-units/ou-eng', _error('OU-1006'), status: 400);
      var deleted = false;
      await tester.pumpWidget(
        _app(
          server,
          OrganizationUnitDetails(organizationUnitId: 'ou-eng', deletable: true, onDeleted: () => deleted = true),
        ),
      );
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-organization-unit-details-delete'));
      expect(server.where('DELETE', '/organization-units/ou-eng'), isEmpty, reason: 'the first tap only asks');
      await _tap(tester, _key('thunderid-action-organization-unit-details-delete-confirm'));

      expect(server.where('DELETE', '/organization-units/ou-eng'), hasLength(1));
      expect(deleted, isFalse);
      expect(
        find.text('This organization unit still has child units, users, groups or other resources. Remove them first.'),
        findsOneWidget,
      );
      expect(find.textContaining('server text'), findsNothing);
    });

    testWidgets('a custom builder gets the members and the actions only when enabled', (tester) async {
      serveUnit();
      OrganizationUnitDetailsState? state;
      await tester.pumpWidget(
        _app(
          server,
          OrganizationUnitDetails(
            organizationUnitId: 'ou-eng',
            builder: (context, details) {
              state = details;
              return Text('${details.unit?.name}: ${details.children.length} child');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Engineering: 1 child'), findsOneWidget);
      expect(state?.users.single.display, 'Ada Lovelace');
      expect(state?.onUpdate, isNull);
      expect(state?.onDelete, isNull);
    });
  });
}
