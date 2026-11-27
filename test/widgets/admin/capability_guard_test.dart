// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'capabilities_support.dart';

/// Answers `GET /capabilities` with [status] and [capabilities], records every request, and
/// serves [routes] for the rest.
class _Server {
  final List<ManagementRequest> requests = [];
  final Map<String, Object?> routes = {};
  Map<String, Object?> capabilities;
  int status;
  Duration delay = Duration.zero;

  _Server(this.capabilities, {this.status = 200});

  Future<ManagementResponse> fetch(ManagementRequest request) async {
    requests.add(request);
    if (request.url.path == '/capabilities') {
      await Future<void>.delayed(delay);
      return ManagementResponse(statusCode: status, statusText: 'x', body: jsonEncode(capabilities));
    }
    final body = routes['${request.method} ${request.url.path}'];
    return body == null
        ? const ManagementResponse(statusCode: 404, statusText: 'Not Found')
        : ManagementResponse(statusCode: 200, statusText: 'OK', body: jsonEncode(body));
  }

  int get capabilityReads => requests.where((r) => r.url.path == '/capabilities').length;
}

Widget _app(_Server server, Widget child) => MaterialApp(
      home: ThunderIDProvider(
        config: ThunderIDConfig(
          baseUrl: 'https://idp.example.com',
          clientId: 'test',
          http: ThunderIDHttpConfig(fetcher: server.fetch),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

Map<String, Object?> _only(Map<String, Map<String, bool>> resources) => {
      'scope': {'type': 'deployment'},
      'resources': resources,
    };

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), signedInChannel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('CapabilityGuard', () {
    testWidgets('renders the child when allowed, and the denied fallback otherwise; one read for both',
        (tester) async {
      final server = _Server(
        _only({
          'app': {'view': true, 'create': false},
        }),
      );
      await tester.pumpWidget(
        _app(
          server,
          const Column(
            children: [
              CapabilityGuard(resource: 'app', child: Text('apps')),
              CapabilityGuard(resource: 'app', action: 'create', denied: Text('no create'), child: Text('create')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('apps'), findsOneWidget);
      expect(find.text('create'), findsNothing);
      expect(find.text('no create'), findsOneWidget);
      expect(server.capabilityReads, 1);
    });

    testWidgets('anyOf allows when any one pair is allowed', (tester) async {
      final server = _Server(
        _only({
          'user': {'create': true},
        }),
      );
      await tester.pumpWidget(
        _app(
          server,
          const Column(
            children: [
              CapabilityGuard(anyOf: [('app', 'create'), ('user', 'create')], child: Text('any')),
              CapabilityGuard(anyOf: [('app', 'create'), ('role', 'create')], child: Text('none')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('any'), findsOneWidget);
      expect(find.text('none'), findsNothing);
    });

    testWidgets('renders nothing by default when denied, loading, or failed', (tester) async {
      final server = _Server(_only(const {}), status: 500);
      await tester.pumpWidget(_app(server, const CapabilityGuard(resource: 'app', child: Text('apps'))));
      await tester.pumpAndSettle();
      expect(find.text('apps'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('shows loading first, then error with retry, then the child', (tester) async {
      final server = _Server(
        _only({
          'app': {'view': true},
        }),
        status: 500,
      )..delay = const Duration(seconds: 1);
      await tester.pumpWidget(
        _app(
          server,
          CapabilityGuard(
            resource: 'app',
            loading: const Text('loading'),
            denied: const Text('denied'),
            error: (context, capabilities) => GestureDetector(onTap: capabilities.retry, child: const Text('retry')),
            child: const Text('apps'),
          ),
        ),
      );
      // The provider initializes, then the guard's first load starts the read.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('loading'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('retry'), findsOneWidget);
      expect(find.text('denied'), findsNothing);
      expect(find.text('apps'), findsNothing);

      server.status = 200;
      await tester.tap(find.text('retry'));
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('apps'), findsOneWidget);
      expect(server.capabilityReads, 2);
    });
  });

  group('admin component gating', () {
    testWidgets('a create component renders nothing without create', (tester) async {
      final server = _Server(
        _only({
          'group': {'view': true, 'create': false},
          'role': {'create': true},
        }),
      );
      await tester.pumpWidget(
        _app(server, const Column(children: [GroupCreate(ouId: 'ou-1'), RoleCreate(ouId: 'ou-1')])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BaseGroupCreate), findsNothing);
      expect(find.byType(BaseRoleCreate), findsOneWidget);
      expect(server.capabilityReads, 1);
    });

    Future<void> details(WidgetTester tester, Map<String, Object?> user, Map<String, bool> actions) async {
      final server = _Server(_only({'user': actions}));
      server.routes['GET /users/u-1'] = user;
      await tester.pumpWidget(
        _app(server, const UserDetails(userId: 'u-1', deletable: true, editable: true, lifecycleActions: true)),
      );
      await tester.pumpAndSettle();
    }

    BaseUserDetails base(WidgetTester tester) => tester.widget<BaseUserDetails>(find.byType(BaseUserDetails));

    const user = {'id': 'u-1', 'ouId': 'ou-1', 'type': 'customer'};

    testWidgets('details offer edit and delete when the user may update and delete', (tester) async {
      await details(tester, user, {'view': true, 'update': true, 'delete': true});
      expect(base(tester).onDelete, isNotNull);
      expect(base(tester).onUpdate, isNotNull);
    });

    testWidgets('details are read-only without update, and offer no delete without delete', (tester) async {
      await details(tester, user, {'view': true});
      expect(base(tester).onDelete, isNull);
      expect(base(tester).onUpdate, isNull);
      expect(base(tester).onLifecycleAction, isNull);
    });

    testWidgets('a server-locked record offers no edit or delete even with every action', (tester) async {
      await details(tester, {...user, 'isReadOnly': true}, {'view': true, 'update': true, 'delete': true});
      expect(base(tester).onDelete, isNull);
      expect(base(tester).onUpdate, isNull);
    });

    testWidgets('group members are editable only with update on group', (tester) async {
      final server = _Server(
        _only({
          'group': {'view': true},
        }),
      );
      await tester.pumpWidget(_app(server, const GroupMembers(groupId: 'g-1', editable: true)));
      await tester.pumpAndSettle();
      final members = tester.widget<BaseGroupMembers>(find.byType(BaseGroupMembers));
      expect(members.onAdd, isNull);
      expect(members.onRemove, isNull);
    });
  });
}
