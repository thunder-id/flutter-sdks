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
      statusText: status == 403 ? 'Forbidden' : 'OK',
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

Widget _bare(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Map<String, Object?> _application({bool readOnly = false, bool publicClient = false}) => {
      'id': 'app1',
      'ouId': 'ou1',
      'name': 'Shop',
      'description': 'Storefront',
      'type': 'browser',
      'url': 'https://shop.example.com',
      'isReadOnly': readOnly,
      'status': {'value': 'ACTIVE'},
      'metadata': {'team': 'retail'},
      'inboundAuthConfig': [
        {
          'type': 'oauth2',
          'config': {
            'clientId': 'shop-client',
            'grantTypes': ['authorization_code'],
            'responseTypes': ['code'],
            'redirectUris': ['https://shop.example.com/cb'],
            'publicClient': publicClient,
            'tokenEndpointAuthMethod': 'client_secret_basic',
          },
        },
      ],
    };

Finder _key(String key) => find.byKey(Key(key));

/// Scrolls [finder] into view before tapping it, since the forms are taller than the test screen.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

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

  group('ApplicationList', () {
    testWidgets('renders name, client ID, type and status, and reports selection', (tester) async {
      server.on('GET', '/applications', {
        'totalResults': 2,
        'count': 2,
        'applications': [
          {'id': 'app1', 'name': 'Shop', 'clientId': 'shop-client', 'type': 'browser', 'status': {'value': 'ACTIVE'}},
          {'id': 'app2', 'name': 'Billing', 'type': 'm2m', 'template': 'Backend', 'status': {'value': 'SUSPENDED'}},
        ],
      });
      BasicApplication? selected;
      await tester.pumpWidget(_app(server, ApplicationList(onSelect: (app) => selected = app)));
      await tester.pumpAndSettle();

      expect(find.text('Applications'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('shop-client'), findsOneWidget);
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Backend'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Suspended'), findsOneWidget);
      expect(server.requests.single.url.queryParameters, {'limit': '20', 'offset': '0'});

      await _tap(tester, _key('thunderid-admin-application-list-row-app2'));
      expect(selected?.id, 'app2');
    });

    testWidgets('shows the translated forbidden message, never the server text', (tester) async {
      server.on('GET', '/applications', {'description': 'Insufficient scope: system'}, status: 403);
      await tester.pumpWidget(_app(server, const ApplicationList()));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to do this.'), findsOneWidget);
      expect(find.textContaining('Insufficient scope'), findsNothing);
    });

    testWidgets('BaseApplicationList hands rows and paging to a builder', (tester) async {
      AdminListState<BasicApplication>? state;
      await tester.pumpWidget(
        _bare(
          BaseApplicationList(
            applications: const [BasicApplication(id: 'a', name: 'Shop')],
            totalResults: 41,
            offset: 20,
            onPageChange: (_) {},
            builder: (context, s) {
              state = s;
              return Text('custom ${s.rows.single.name} ${s.totalResults}');
            },
          ),
        ),
      );

      expect(find.text('custom Shop 41'), findsOneWidget);
      expect(state?.offset, 20);
      expect(state?.onPageChange, isNotNull);
      expect(state?.onSearch, isNull);
    });
  });

  group('ApplicationCreate', () {
    testWidgets('creates the application with OAuth defaults and shows the secret once', (tester) async {
      server.on('POST', '/applications', {
        ..._application(),
        'inboundAuthConfig': [
          {
            'type': 'oauth2',
            'config': {'clientId': 'shop-client', 'clientSecret': 'only-now'},
          },
        ],
      });
      ApplicationCreateResult? created;
      var done = 0;
      await tester.pumpWidget(
        _app(
          server,
          ApplicationCreate(ouId: 'ou1', onCreated: (result) => created = result, onDone: () => done++),
        ),
      );
      await tester.pumpAndSettle();

      final submit = _key('thunderid-action-application-create-submit');
      expect(tester.widget<TextButton>(submit).onPressed, isNull, reason: 'name and redirect URI are required');

      await tester.enterText(_key('thunderid-field-application-create-name'), 'Shop');
      await tester.enterText(_key('thunderid-field-application-create-redirectUris'), 'https://shop.example.com/cb');
      await tester.pump();
      await _tap(tester, submit);
      await tester.pumpAndSettle();

      expect(server.lastBody('POST', '/applications'), {
        'name': 'Shop',
        'type': 'browser',
        'ouId': 'ou1',
        'inboundAuthConfig': [
          {
            'type': 'oauth2',
            'config': {
              'redirectUris': ['https://shop.example.com/cb'],
              'grantTypes': ['authorization_code', 'refresh_token'],
              'responseTypes': ['code'],
              'tokenEndpointAuthMethod': 'client_secret_basic',
              'publicClient': false,
            },
          },
        ],
      });
      expect(created?.application.id, 'app1');
      expect(created?.clientSecret, 'only-now');
      expect(find.text('only-now'), findsOneWidget);
      expect(find.text('Copy this secret now. It will not be shown again.'), findsOneWidget);

      await _tap(tester, _key('thunderid-action-application-create-secret-done'));
      await tester.pumpAndSettle();

      expect(find.text('only-now'), findsNothing);
      expect(done, 1);
      expect(_key('thunderid-field-application-create-name'), findsOneWidget);
    });

    testWidgets('a public client gets PKCE and cannot ask for client credentials', (tester) async {
      ApplicationCreateSubmission? submitted;
      await tester.pumpWidget(_bare(BaseApplicationCreate(onSubmit: (s) => submitted = s)));

      await tester.enterText(_key('thunderid-field-application-create-name'), 'Mobile');
      await tester.enterText(_key('thunderid-field-application-create-redirectUris'), 'com.example.app:/cb');
      await _tap(tester, _key('thunderid-field-application-create-publicClient'));
      await _tap(tester, _key('thunderid-field-application-create-grantTypes-client_credentials'));
      await tester.pump();

      final submit = _key('thunderid-action-application-create-submit');
      expect(tester.widget<TextButton>(submit).onPressed, isNull);

      await _tap(tester, _key('thunderid-field-application-create-grantTypes-client_credentials'));
      await tester.pump();
      await _tap(tester, submit);

      expect(submitted?.publicClient, isTrue);
      final config = submitted!.toRequest(ouId: 'ou1').inboundAuthConfig!.single.config;
      expect(config.pkceRequired, isTrue);
      expect(config.tokenEndpointAuthMethod, 'none');
      expect(config.redirectUris, ['com.example.app:/cb']);
    });

    testWidgets('refuses a redirect URI that is not an absolute URL', (tester) async {
      await tester.pumpWidget(_bare(BaseApplicationCreate(onSubmit: (_) {})));

      await tester.enterText(_key('thunderid-field-application-create-name'), 'Shop');
      await tester.enterText(_key('thunderid-field-application-create-redirectUris'), 'not a url');
      await tester.pump();

      expect(tester.widget<TextButton>(_key('thunderid-action-application-create-submit')).onPressed, isNull);
    });

    testWidgets('BaseApplicationCreate hands values, setters and the secret to a builder', (tester) async {
      ApplicationCreateFormState? state;
      var dismissed = false;
      await tester.pumpWidget(
        _bare(
          BaseApplicationCreate(
            onSubmit: (_) {},
            clientSecret: 's3cret',
            onSecretDismissed: () => dismissed = true,
            builder: (context, s) {
              state = s;
              return Text('custom ${s.type} ${s.grantTypes.join(',')} ${s.clientSecret}');
            },
          ),
        ),
      );

      expect(find.text('custom browser authorization_code,refresh_token s3cret'), findsOneWidget);
      expect(state?.isValid, isFalse);
      expect(state?.applicationTypes.map((o) => o.value), contains('m2m'));
      state!.onSecretDismissed!();
      expect(dismissed, isTrue);

      state!.onNameChanged('Shop');
      state!.onGrantTypeChanged('authorization_code', false);
      await tester.pump();
      expect(state?.grantTypes, ['refresh_token']);
      expect(state?.isValid, isTrue);
    });
  });

  group('ApplicationDetails', () {
    testWidgets('is read-only by default', (tester) async {
      server.on('GET', '/applications/app1', _application());
      await tester.pumpWidget(_app(server, const ApplicationDetails(applicationId: 'app1')));
      await tester.pumpAndSettle();

      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('shop-client'), findsOneWidget);
      expect(find.text('https://shop.example.com/cb'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(_key('thunderid-action-application-details-delete'), findsNothing);
      expect(_key('thunderid-action-application-details-edit'), findsNothing);
      expect(_key('thunderid-action-application-details-regenerateSecret'), findsNothing);
    });

    testWidgets('asks for confirmation before deleting', (tester) async {
      server
        ..on('GET', '/applications/app1', _application())
        ..on('DELETE', '/applications/app1', null);
      var deleted = false;
      await tester.pumpWidget(
        _app(server, ApplicationDetails(applicationId: 'app1', deletable: true, onDeleted: () => deleted = true)),
      );
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-application-details-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Shop?'), findsOneWidget);
      expect(server.where('DELETE', '/applications/app1'), isEmpty);

      await _tap(tester, _key('thunderid-action-application-details-delete-confirm'));
      await tester.pumpAndSettle();
      expect(server.where('DELETE', '/applications/app1'), hasLength(1));
      expect(deleted, isTrue);
    });

    testWidgets('regenerates the client secret after confirmation and shows it once', (tester) async {
      server
        ..on('GET', '/applications/app1', _application())
        ..on('PUT', '/applications/app1', _application());
      await tester.pumpWidget(_app(server, const ApplicationDetails(applicationId: 'app1', secretRegenerable: true)));
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-application-details-regenerateSecret'));
      await tester.pumpAndSettle();
      expect(server.where('PUT', '/applications/app1'), isEmpty);

      await _tap(tester, _key('thunderid-action-application-details-regenerateSecret-confirm'));
      await tester.pumpAndSettle();

      final body = server.lastBody('PUT', '/applications/app1')! as Map<String, Object?>;
      final config = ((body['inboundAuthConfig']! as List).single as Map)['config'] as Map;
      final secret = config['clientSecret'] as String;
      expect(secret, isNotEmpty);
      expect(find.text(secret), findsOneWidget);

      await _tap(tester, _key('thunderid-action-application-details-secret-done'));
      await tester.pumpAndSettle();
      expect(find.text(secret), findsNothing);
    });

    testWidgets('offers no secret regeneration for a public client', (tester) async {
      server.on('GET', '/applications/app1', _application(publicClient: true));
      await tester.pumpWidget(_app(server, const ApplicationDetails(applicationId: 'app1', secretRegenerable: true)));
      await tester.pumpAndSettle();

      expect(_key('thunderid-action-application-details-regenerateSecret'), findsNothing);
    });

    testWidgets('saves edits as a full update that keeps the other fields', (tester) async {
      server
        ..on('GET', '/applications/app1', _application())
        ..on('PUT', '/applications/app1', _application());
      await tester.pumpWidget(_app(server, const ApplicationDetails(applicationId: 'app1', editable: true)));
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-application-details-edit'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('thunderid-field-application-details-name'), 'Shop 2');
      await tester.enterText(
        _key('thunderid-field-application-details-redirectUris'),
        'https://shop.example.com/cb\nhttps://shop.example.com/cb2',
      );
      await _tap(tester, _key('thunderid-field-application-details-grantTypes-refresh_token'));
      await tester.pump();
      await _tap(tester, _key('thunderid-action-application-details-edit-save'));
      await tester.pumpAndSettle();

      final body = server.lastBody('PUT', '/applications/app1')! as Map<String, Object?>;
      expect(body['name'], 'Shop 2');
      expect(body['ouId'], 'ou1');
      expect(body['metadata'], {'team': 'retail'});
      expect(body.containsKey('id'), isFalse);
      final config = ((body['inboundAuthConfig']! as List).single as Map)['config'] as Map;
      expect(config['clientId'], 'shop-client');
      expect(config['redirectUris'], ['https://shop.example.com/cb', 'https://shop.example.com/cb2']);
      expect(config['grantTypes'], ['authorization_code', 'refresh_token']);
      expect(config['responseTypes'], ['code']);
    });

    testWidgets('BaseApplicationDetails gives a builder no write actions for a read-only application', (tester) async {
      ApplicationDetailsState? state;
      Widget details(Map<String, Object?> json) => _bare(
            BaseApplicationDetails(
              application: Application.fromJson(json),
              onDelete: () {},
              onUpdate: (_) {},
              onRegenerateSecret: () {},
              builder: (context, s) {
                state = s;
                return Text('custom ${s.application?.name}');
              },
            ),
          );

      await tester.pumpWidget(details(_application(readOnly: true)));
      expect(find.text('custom Shop'), findsOneWidget);
      expect(state?.onDelete, isNull);
      expect(state?.onUpdate, isNull);
      expect(state?.onRegenerateSecret, isNull);

      await tester.pumpWidget(details(_application()));
      expect(state?.onDelete, isNotNull);
      expect(state?.onUpdate, isNotNull);
      expect(state?.onRegenerateSecret, isNotNull);
    });
  });
}
