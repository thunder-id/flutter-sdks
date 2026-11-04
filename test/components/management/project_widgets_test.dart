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

ThunderIDState _thunder(WidgetTester tester) => tester.state<ThunderIDState>(find.byType(ThunderIDProvider));

const _alpha = {'id': 'p-alpha', 'handle': 'alpha', 'displayName': 'Alpha', 'description': 'First project'};
const _beta = {'id': 'p-beta', 'handle': 'beta', 'displayName': 'Beta'};
const _alphaProject = Project(id: 'p-alpha', handle: 'alpha', displayName: 'Alpha');

Map<String, Object?> _error(String code) => {'code': code, 'message': 'server text', 'description': 'never shown'};

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

  group('ProjectList', () {
    testWidgets('renders projects and reports selection', (tester) async {
      server.on('GET', '/projects', {
        'totalResults': 2,
        'projects': [_alpha, _beta],
      });
      Project? selected;
      await tester.pumpWidget(_app(server, ProjectList(onSelect: (project) => selected = project)));
      await tester.pumpAndSettle();

      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(server.requests.single.url.queryParameters, {'limit': '20', 'offset': '0'});

      await _tap(tester, _key('thunderid-admin-project-list-row-p-beta'));
      expect(selected?.handle, 'beta');
    });

    testWidgets('hands rows and paging to a custom builder', (tester) async {
      server.on('GET', '/projects', {
        'totalResults': 3,
        'projects': [_alpha],
      });
      AdminListState<Project>? state;
      await tester.pumpWidget(
        _app(
          server,
          ProjectList(
            limit: 1,
            builder: (context, list) {
              state = list;
              return Column(children: [for (final p in list.rows) Text('custom ${p.displayName}')]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('custom Alpha'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-admin-project-list')), findsNothing);
      expect(state?.totalResults, 3);
      state!.onPageChange!(1);
      await tester.pumpAndSettle();
      expect(server.requests.last.url.queryParameters['offset'], '1');
    });
  });

  group('ProjectCreate', () {
    testWidgets('requires a valid handle and creates the project', (tester) async {
      server.on('POST', '/projects', {..._alpha, 'id': 'p-new'});
      Project? created;
      await tester.pumpWidget(_app(server, ProjectCreate(onCreated: (project) => created = project)));
      await tester.pumpAndSettle();

      final submit = _key('thunderid-action-project-create-submit');
      await tester.enterText(_key('thunderid-field-project-create-handle'), 'Not Valid');
      await tester.enterText(_key('thunderid-field-project-create-displayName'), 'Alpha');
      await tester.pump();
      expect(tester.widget<TextButton>(submit).onPressed, isNull, reason: 'the handle must follow the rule');

      await tester.enterText(_key('thunderid-field-project-create-handle'), 'alpha');
      await tester.pump();
      await _tap(tester, submit);

      expect(server.lastBody('POST', '/projects'), {'handle': 'alpha', 'displayName': 'Alpha'});
      expect(created?.id, 'p-new');
    });

    for (final (code, message) in [
      ('PRJ-1006', 'A project with this ID already exists.'),
      ('PRJ-1012', 'A project with this handle already exists.'),
    ]) {
      testWidgets('maps $code to its own message, never the server text', (tester) async {
        server.on('POST', '/projects', _error(code), status: 409);
        await tester.pumpWidget(_app(server, const ProjectCreate()));
        await tester.pumpAndSettle();

        await tester.enterText(_key('thunderid-field-project-create-handle'), 'alpha');
        await tester.enterText(_key('thunderid-field-project-create-displayName'), 'Alpha');
        await tester.pump();
        await _tap(tester, _key('thunderid-action-project-create-submit'));

        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('server text'), findsNothing);
      });
    }

    testWidgets('BaseProjectCreate hands its values to a custom builder', (tester) async {
      CreateProjectRequest? submitted;
      ProjectFormState? form;
      await tester.pumpWidget(
        _bare(
          BaseProjectCreate(
            onSubmit: (request) => submitted = request,
            builder: (context, state) {
              form = state;
              return Text('valid: ${state.isValid}');
            },
          ),
        ),
      );
      expect(find.text('valid: false'), findsOneWidget);
      form!.onHandleChanged('team-a');
      form!.onDisplayNameChanged(' Team A ');
      form!.onDescriptionChanged('  ');
      await tester.pump();
      expect(find.text('valid: true'), findsOneWidget);
      form!.submit();
      expect(submitted?.toJson(), {'handle': 'team-a', 'displayName': 'Team A'});
    });
  });

  group('ProjectDetails', () {
    void serveProject() => server.on('GET', '/projects/p-alpha', {..._alpha, 'createdAt': '2026-01-02T03:04:05Z'});

    testWidgets('is read-only by default', (tester) async {
      serveProject();
      await tester.pumpWidget(_app(server, const ProjectDetails(projectId: 'p-alpha')));
      await tester.pumpAndSettle();

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('First project'), findsWidgets);
      expect(_key('thunderid-action-project-details-edit'), findsNothing);
      expect(_key('thunderid-action-project-details-delete'), findsNothing);
    });

    testWidgets('edits the display name and keeps the handle', (tester) async {
      serveProject();
      server.on('PUT', '/projects/p-alpha', {..._alpha, 'displayName': 'Alpha 2'});
      await tester.pumpWidget(_app(server, const ProjectDetails(projectId: 'p-alpha', editable: true)));
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-project-details-edit'));
      await tester.enterText(_key('thunderid-field-project-details-displayName'), 'Alpha 2');
      await tester.pump();
      await _tap(tester, _key('thunderid-action-project-details-save'));

      expect(server.lastBody('PUT', '/projects/p-alpha'), {
        'handle': 'alpha',
        'displayName': 'Alpha 2',
        'description': 'First project',
      });
    });

    testWidgets('maps PRJ-1007 on an update to the handle message', (tester) async {
      serveProject();
      server.on('PUT', '/projects/p-alpha', _error('PRJ-1007'), status: 400);
      await tester.pumpWidget(_app(server, const ProjectDetails(projectId: 'p-alpha', editable: true)));
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-project-details-edit'));
      await _tap(tester, _key('thunderid-action-project-details-save'));
      expect(find.text("A project's handle cannot be changed."), findsOneWidget);
    });

    testWidgets('deletes only after confirmation and clears the current project', (tester) async {
      serveProject();
      server.on('DELETE', '/projects/p-alpha', null, status: 204);
      var deleted = false;
      await tester.pumpWidget(
        _app(server, ProjectDetails(projectId: 'p-alpha', deletable: true, onDeleted: () => deleted = true)),
      );
      await tester.pumpAndSettle();
      _thunder(tester).setCurrentProject(_alphaProject);
      await tester.pumpAndSettle();

      await _tap(tester, _key('thunderid-action-project-details-delete'));
      expect(server.where('DELETE', '/projects/p-alpha'), isEmpty, reason: 'the first tap only asks');
      expect(find.text('Delete Alpha?'), findsOneWidget);

      await _tap(tester, _key('thunderid-action-project-details-delete-confirm'));
      expect(server.where('DELETE', '/projects/p-alpha'), hasLength(1));
      expect(deleted, isTrue);
      expect(_thunder(tester).currentProject, isNull);
    });

    testWidgets('a custom builder gets the actions only when enabled', (tester) async {
      serveProject();
      final states = <ProjectDetailsState>[];
      Widget build({required bool enabled}) => _app(
        server,
        ProjectDetails(
          projectId: 'p-alpha',
          editable: enabled,
          deletable: enabled,
          builder: (context, state) {
            states.add(state);
            return Text(state.project?.displayName ?? 'loading');
          },
        ),
      );
      await tester.pumpWidget(build(enabled: false));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(states.last.onUpdate, isNull);
      expect(states.last.onDelete, isNull);

      await tester.pumpWidget(build(enabled: true));
      await tester.pumpAndSettle();
      expect(states.last.onUpdate, isNotNull);
      expect(states.last.onDelete, isNotNull);
    });
  });

  group('ProjectSwitcher', () {
    testWidgets('sets the current project, marks it, and clears it', (tester) async {
      server.on('GET', '/projects', {
        'totalResults': 2,
        'projects': [_alpha, _beta],
      });
      Project? picked;
      await tester.pumpWidget(_app(server, ProjectSwitcher(onSelect: (project) => picked = project)));
      await tester.pumpAndSettle();
      expect(_key('thunderid-action-project-switcher-clear'), findsNothing);

      await _tap(tester, _key('thunderid-admin-project-switcher-row-p-beta'));
      expect(picked?.id, 'p-beta');
      expect(_thunder(tester).currentProject?.id, 'p-beta');
      expect(_key('thunderid-admin-project-switcher-current-p-beta'), findsOneWidget);

      await _tap(tester, _key('thunderid-action-project-switcher-clear'));
      expect(_thunder(tester).currentProject, isNull);
      expect(_key('thunderid-admin-project-switcher-current-p-beta'), findsNothing);
    });

    testWidgets('hands the projects and the current one to a custom builder', (tester) async {
      server.on('GET', '/projects', {
        'totalResults': 1,
        'projects': [_alpha],
      });
      await tester.pumpWidget(
        _app(
          server,
          ProjectSwitcher(
            builder: (context, state) => Column(
              children: [
                Text('current: ${state.currentId}'),
                for (final project in state.projects)
                  TextButton(onPressed: () => state.onSelect(project), child: Text(project.handle)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('current: null'), findsOneWidget);

      await _tap(tester, find.text('alpha'));
      expect(find.text('current: p-alpha'), findsOneWidget);
    });
  });

  group('the current project', () {
    testWidgets('AgentList lists it, hides its search and sends no filter', (tester) async {
      server.on('GET', '/agents', {'totalResults': 0, 'agents': <Object?>[]});
      await tester.pumpWidget(_app(server, const AgentList()));
      await tester.pumpAndSettle();
      expect(_key('thunderid-field-agent-list-search'), findsOneWidget);
      expect(server.where('GET', '/agents').last.url.queryParameters.containsKey('projectId'), isFalse);

      _thunder(tester).setCurrentProject(_alphaProject);
      await tester.pumpAndSettle();

      final query = server.where('GET', '/agents').last.url.queryParameters;
      expect(query['projectId'], 'p-alpha');
      expect(query.containsKey('filter'), isFalse);
      expect(_key('thunderid-field-agent-list-search'), findsNothing);
    });

    testWidgets('AgentList drops an applied search once a project scopes it', (tester) async {
      server.on('GET', '/agents', {'totalResults': 0, 'agents': <Object?>[]});
      await tester.pumpWidget(_app(server, const AgentList()));
      await tester.pumpAndSettle();
      await tester.enterText(_key('thunderid-field-agent-list-search'), 'Concierge');
      await _tap(tester, _key('thunderid-action-agent-list-search'));
      expect(server.where('GET', '/agents').last.url.queryParameters['filter'], 'name eq "Concierge"');

      _thunder(tester).setCurrentProject(_alphaProject);
      await tester.pumpAndSettle();
      final query = server.where('GET', '/agents').last.url.queryParameters;
      expect(query['projectId'], 'p-alpha');
      expect(query.containsKey('filter'), isFalse);
    });

    testWidgets('an explicit AgentList projectId wins and its custom builder gets no search', (tester) async {
      server.on('GET', '/agents', {'totalResults': 0, 'agents': <Object?>[]});
      AdminListState<Agent>? state;
      await tester.pumpWidget(
        _app(
          server,
          AgentList(
            projectId: 'p-explicit',
            builder: (context, list) {
              state = list;
              return const Text('custom agents');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      _thunder(tester).setCurrentProject(_alphaProject);
      await tester.pumpAndSettle();

      expect(server.where('GET', '/agents').map((r) => r.url.queryParameters['projectId']).toSet(), {'p-explicit'});
      expect(state?.onSearch, isNull);
      expect(state?.search, isNull);
    });

    testWidgets('ApplicationList lists it unless the app passes another', (tester) async {
      server.on('GET', '/applications', {'totalResults': 0, 'applications': <Object?>[]});
      await tester.pumpWidget(_app(server, const ApplicationList()));
      await tester.pumpAndSettle();
      expect(server.where('GET', '/applications').last.url.queryParameters.containsKey('projectId'), isFalse);

      _thunder(tester).setCurrentProject(_alphaProject);
      await tester.pumpAndSettle();
      expect(server.where('GET', '/applications').last.url.queryParameters['projectId'], 'p-alpha');

      await tester.pumpWidget(_app(server, const ApplicationList(projectId: 'p-explicit')));
      await tester.pumpAndSettle();
      expect(server.where('GET', '/applications').last.url.queryParameters['projectId'], 'p-explicit');
    });

    testWidgets('AgentCreate sends it as projectId, never as an organization unit', (tester) async {
      server
        ..on('GET', '/agent-types', {
          'totalResults': 1,
          'types': [
            {'id': 't1', 'handle': 'assistant', 'displayName': 'Assistant', 'ouId': 'ou1'},
          ],
        })
        ..on('POST', '/agents', {'id': 'a1', 'name': 'Bot', 'ouId': 'root-ou', 'type': 'assistant'});
      await tester.pumpWidget(_app(server, const AgentCreate()));
      await tester.pumpAndSettle();
      _thunder(tester).setCurrentProject(_alphaProject);
      await tester.pumpAndSettle();

      expect(find.text('Choose an organization unit before creating this item.'), findsNothing);
      await tester.enterText(_key('thunderid-field-agent-create-name'), 'Bot');
      await tester.pump();
      await _tap(tester, _key('thunderid-action-agent-create-submit'));

      final body = server.lastBody('POST', '/agents')! as Map;
      expect(body['projectId'], 'p-alpha');
      expect(body.containsKey('ouId'), isFalse);
    });

    for (final (name, widget, ouId, projectId) in [
      ('sends it as projectId', const ApplicationCreate(), null, 'p-alpha'),
      ('sends an explicit unit instead', const ApplicationCreate(ouId: 'ou-1'), 'ou-1', null),
    ]) {
      testWidgets('ApplicationCreate $name', (tester) async {
        server.on('POST', '/applications', {'id': 'app1', 'name': 'Shop'});
        await tester.pumpWidget(_app(server, widget));
        await tester.pumpAndSettle();
        _thunder(tester).setCurrentProject(_alphaProject);
        await tester.pumpAndSettle();

        await tester.enterText(_key('thunderid-field-application-create-name'), 'Shop');
        await tester.enterText(_key('thunderid-field-application-create-redirectUris'), 'https://shop.example.com/cb');
        await tester.pump();
        await _tap(tester, _key('thunderid-action-application-create-submit'));

        final body = server.lastBody('POST', '/applications')! as Map;
        expect(body['ouId'], ouId);
        expect(body['projectId'], projectId);
      });
    }
  });

  test('toManagementErrorMessage maps listed server codes before the generic messages', () {
    String translate(String key) => thunderDefaultStringsFor(key);
    IAMApiException refusal(String code, int status) => IAMApiException(
      status == 403 ? ThunderIDErrorCode.forbidden : ThunderIDErrorCode.serverError,
      'refused',
      statusCode: status,
      operation: 'test',
      responseBody: jsonEncode(_error(code)),
    );
    const keys = {'OU-1006': 'admin.organization_units.details.delete.has_children'};
    expect(
      toManagementErrorMessage(translate, refusal('OU-1006', 400), 'fallback', codeKeys: keys),
      'admin.organization_units.details.delete.has_children',
    );
    expect(toManagementErrorMessage(translate, refusal('OU-9999', 400), 'fallback', codeKeys: keys), 'fallback');
    expect(
      toManagementErrorMessage(translate, refusal('OU-9999', 403), 'fallback', codeKeys: keys),
      'admin.common.errors.forbidden',
    );
  });
}

/// Returns the key itself, so the assertions name the key a message came from.
String thunderDefaultStringsFor(String key) => key;
