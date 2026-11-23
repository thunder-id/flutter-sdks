// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry_config.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry_encoder.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry_rules.dart';

const _user = '11111111-1111-4111-8111-111111111111';
const _org = '22222222-2222-4222-8222-222222222222';

({List<List<Map<String, Object?>>> sent, Telemetry telemetry}) _build(TelemetryConfig config) {
  final sent = <List<Map<String, Object?>>>[];
  final telemetry = Telemetry(
    config,
    apiBases: const ['https://api.example.com'],
    identity: () async => (userId: _user, organizationId: _org),
    send: (body) async => sent.add((jsonDecode(body) as List).cast<Map<String, Object?>>()),
  );
  return (sent: sent, telemetry: telemetry);
}

List<String> _names(List<Map<String, Object?>> batch) => batch.map((event) => event['name']! as String).toList();

void main() {
  group('TelemetryNames', () {
    test('names a screen from its route pattern', () {
      expect(TelemetryNames.pageName('/organizations/:org/applications'), 'application.list-view');
      expect(TelemetryNames.pageName('/applications/:id'), 'application.detail-view');
      expect(TelemetryNames.pageName('/applications/{id}'), 'application.detail-view');
      expect(TelemetryNames.pageName('/applications/create'), 'application.create-view');
      expect(TelemetryNames.pageName('/applications/:id/settings'), 'setting.list-view');
      expect(TelemetryNames.pageName('/applications/:id/status'), 'application.status-view');
      expect(TelemetryNames.pageName('/policies'), 'policy.list-view');
      expect(TelemetryNames.pageName('/'), 'app.home-view');
    });

    test('reads plurals by English spelling, with no list of words', () {
      expect(TelemetryNames.singular('applications'), 'application');
      expect(TelemetryNames.singular('policies'), 'policy');
      expect(TelemetryNames.singular('addresses'), 'address');
      expect(TelemetryNames.singular('boxes'), 'box');
      expect(TelemetryNames.isCollection('access'), isFalse);
      expect(TelemetryNames.isCollection('status'), isFalse);
      expect(TelemetryNames.isCollection('settings'), isTrue);
    });

    test('keeps only plain words in a link path', () {
      expect(TelemetryNames.linkPath('/guides/getting-started'), '/guides/{id}');
      expect(TelemetryNames.linkPath('/users/alice'), '/users/{id}');
      expect(TelemetryNames.linkPath('/reset/abcdefghijklmnop/confirm'), '/reset/{id}/{id}');
      expect(TelemetryNames.linkPath('/a/'), '/a/');
      expect(TelemetryNames.linkPath('/12345/orders'), '/{id}/{id}');
      expect(TelemetryNames.linkPath('/orders/12345/'), '/orders/{id}/');
    });

    test('accepts only lower-case <type>.<action> names, and drops data that could be personal', () {
      expect(TelemetryNames.isValidName('application.template-pick'), isTrue);
      expect(TelemetryNames.isValidName('user.alice@example.com'), isFalse);
      expect(TelemetryNames.isValidName('Application.Create'), isFalse);
      expect(TelemetryNames.isValidName('single'), isFalse);
      expect(
        TelemetryNames.safeData({
          'email': 'a@b.com',
          'long': 'x' * 65,
          'text': 'two words',
          'type': 'spa',
          'url': 'https://x.com',
        }),
        {'type': 'spa'},
      );
    });

    test('never accepts a trailing line break in a whole-string pattern', () {
      expect(TelemetryNames.isValidName('application.create\n'), isFalse);
      expect(TelemetryNames.matches('/roles\n', '/roles'), isFalse);
      expect(TelemetryNames.linkPath('/guides\n'), '/{id}');
      expect(TelemetryApiRules.isErrorCode('APP-1023\n'), isFalse);
      expect(TelemetryApiRules.failureData(409, '{"code":"APP-1023\\n"}'), {'status': '409'});
    });

    test('matches one segment with * and the rest with **', () {
      expect(TelemetryNames.matches('/settings/general', '/settings/*'), isTrue);
      expect(TelemetryNames.matches('/settings/general/advanced', '/settings/*'), isFalse);
      expect(TelemetryNames.matches('/settings/general/advanced', '/settings/**'), isTrue);
      expect(TelemetryNames.matches('https://abcXcom/x', 'https://abc.com/*'), isFalse);
    });
  });

  group('TelemetryApiRules', () {
    const api = 'https://api.example.com';
    const id = '019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b';
    final rules = TelemetryApiRules(
      [api, 'https://env.example.com/v1'],
      kinds: ['connections'],
      addressWords: ['tree'],
      actions: ['suspend'],
    );
    final plain = TelemetryApiRules([api]);
    TelemetryApiCall? classify(String method, String url) => rules.classify(method, Uri.parse(url));
    String? name(String method, String path) => classify(method, '$api$path')?.name;
    void expectCall(TelemetryApiCall? call, String name, String route, Map<String, String> data) {
      expect([call?.name, call?.route, call?.data], [name, route, data]);
    }

    test('names creates, updates and deletes from the collection, with a path template', () {
      expectCall(classify('POST', '$api/applications'), 'application.create', '/applications', {
        'resource_type': 'application',
      });
      expectCall(classify('DELETE', '$api/roles/$id'), 'role.delete', '/roles/{id}', {'resource_type': 'role'});
      expect(name('PATCH', '/organization-units/$id'), 'organization-unit.update');
      expect(name('PUT', '/variables/API_KEY'), 'variable.update');
      expect(name('DELETE', '/secrets'), 'secret.delete');
      expect(classify('POST', '$api/applications/a1/credentials?x=1')!.route, '/applications/{id}/credentials');
    });

    test('names every kind of resource the same way, whatever the shape of its path', () {
      const cases = <(String, String, String, Map<String, String>)>[
        ('POST', '/connections/google', 'connection.create', {'kind': 'google', 'resource_type': 'connection'}),
        (
          'PUT',
          '/connections/sms-gateway/$id',
          'connection.update',
          {'kind': 'sms-gateway', 'resource_type': 'connection'},
        ),
        ('POST', '/design/themes', 'theme.create', {'resource_type': 'theme'}),
        (
          'DELETE',
          '/openid4vci/credential-configurations/$id',
          'credential-configuration.delete',
          {'resource_type': 'credential-configuration'},
        ),
        ('POST', '/scim/v2/Users', 'user.create', {'resource_type': 'user'}),
        ('PUT', '/server-config/branding', 'server-config.update', {'resource_type': 'server-config'}),
        (
          'POST',
          '/resource-servers/$id/resources/$id/actions',
          'action.create',
          {'parent_type': 'resource', 'resource_type': 'action'},
        ),
        (
          'POST',
          '/notification-templates/email/templates',
          'template.create',
          {'parent_type': 'notification-template', 'resource_type': 'template'},
        ),
        (
          'PUT',
          '/organization-units/tree/engineering/backend',
          'organization-unit.update',
          {'resource_type': 'organization-unit'},
        ),
        ('PUT', '/users/me', 'user.update', {'resource_type': 'user'}),
      ];
      for (final (method, path, expected, data) in cases) {
        final call = classify(method, '$api$path');
        expect([path, call?.name, call?.data], [path, expected, data]);
      }
    });

    test('names a sub-resource for itself, with its parent, unless configured as a parent action', () {
      expectCall(
        classify('POST', '$api/applications/$id/sharing-policies'),
        'sharing-policy.create',
        '/applications/{id}/sharing-policies',
        {'parent_type': 'application', 'resource_type': 'sharing-policy'},
      );
      const parentActions = {
        'sharing-policies': {'create': 'share', 'delete': 'unshare', 'update': 'share-update'},
      };
      final configured = TelemetryApiRules([api], parentActions: parentActions, kinds: ['connections']);
      expectCall(
        configured.classify('POST', Uri.parse('$api/applications/$id/sharing-policies')),
        'application.share',
        '/applications/{id}/sharing-policies',
        {'resource_type': 'application'},
      );
      expect(configured.classify('PUT', Uri.parse('$api/roles/$id/sharing-policies/$id'))?.name, 'role.share-update');
      expect(
        configured.classify('DELETE', Uri.parse('$api/connections/oidc/$id/sharing-policies/$id'))?.name,
        'connection.unshare',
      );
    });

    test('names actions on a resource for what they act on', () {
      expect(name('POST', '/applications/$id/client-secret/regenerate'), 'application.client-secret-regenerate');
      expect(name('POST', '/users/$id/update-credentials'), 'user.update-credentials');
      expect(name('POST', '/flows/$id/restore'), 'flow.restore');
      expect(name('POST', '/users/me/agents/$id/suspend'), 'agent.suspend');
      expect(name('PUT', '/projects/$id/auto-sync'), 'project.auto-sync-update');
      expectCall(classify('POST', '$api/groups/$id/members/add'), 'group.member-add', '/groups/{id}/members/add', {
        'resource_type': 'group',
        'sub_type': 'member',
      });
      expect(name('POST', '/groups/$id/members/remove'), 'group.member-remove');
      expect(name('POST', '/roles/$id/assignments/add'), 'role.assignment-add');
      expect(name('POST', '/users/me/agents/suspend'), 'user.agent-suspend');
    });

    test('names an action on an item from its words, and keeps words after a word item out of the name', () {
      expect(name('POST', '/gateways/$id/apply'), 'gateway.apply');
      expect(name('POST', '/gateways/$id/revert'), 'gateway.revert');
      expectCall(
        classify('POST', 'https://env.example.com/v1/environments/dev/apply'),
        'environment.create',
        '/environments/{id}/{path}',
        {'resource_type': 'environment'},
      );
      expect(name('POST', '/promotions'), 'promotion.create');
    });

    test('names a call with no resource type from its words', () {
      expectCall(classify('POST', '$api/import'), 'api.import', '/import', {});
      expect(name('POST', '/import/managed'), 'api.import-managed');
      expect(name('POST', '/export'), 'api.export');
      expect(name('DELETE', '/maintenance'), 'api.maintenance-delete');
      expectCall(classify('PUT', '$api/dcr/register/c1d2e3f4a5b6c7d8e9f0'), 'api.call', '/dcr/{id}/{id}', {
        'method': 'PUT',
      });
    });

    test('reports any other change as api.call, keeping no value from the path', () {
      expectCall(classify('POST', '$api/import/$id/retry-later'), 'api.call', '/import/{id}/{id}', {'method': 'POST'});
    });

    test('skips a label and its value in front of a sub-collection', () {
      expectCall(
        classify('DELETE', '$api/i18n/languages/en/translations/ns/auth/keys/login.title'),
        'key.delete',
        '/i18n/languages/{id}/translations/ns/{id}/keys/{id}',
        {'parent_type': 'translation', 'resource_type': 'key'},
      );
      expect(name('POST', '/i18n/languages/en/translations/ns/auth/keys/login.title'), 'key.create');
      expect(name('POST', '/i18n/languages/en/translations/ns/auth/keys'), 'key.create');
    });

    test('reads a word after a top-level collection as a kind only for a configured collection', () {
      expectCall(classify('POST', '$api/connections/google'), 'connection.create', '/connections/google', {
        'kind': 'google',
        'resource_type': 'connection',
      });
      expectCall(
        plain.classify('POST', Uri.parse('$api/connections/google')),
        'connection.create',
        '/connections/{id}',
        {'resource_type': 'connection'},
      );
      expectCall(classify('POST', '$api/users/alice'), 'user.create', '/users/{id}', {'resource_type': 'user'});
      expectCall(
        classify('PUT', '$api/groups/$id/members/sms-gateway/$id'),
        'member.update',
        '/groups/{id}/members/{id}/{path}',
        {'parent_type': 'group', 'resource_type': 'member'},
      );
    });

    test('keeps every word after a configured address word out of the name', () {
      expectCall(
        classify('PUT', '$api/organization-units/tree/engineering/operations'),
        'organization-unit.update',
        '/organization-units/tree/{path}',
        {'resource_type': 'organization-unit'},
      );
      expect(name('POST', '/organization-units/tree/engineering/operations'), 'organization-unit.create');
      expect(name('DELETE', '/organization-units/tree/engineering'), 'organization-unit.delete');
      expectCall(
        classify('PUT', '$api/organization-units/tree'),
        'organization-unit.update',
        '/organization-units/tree/{path}',
        {'resource_type': 'organization-unit'},
      );
      expectCall(
        plain.classify('PUT', Uri.parse('$api/organization-units/tree/engineering/operations')),
        'organization-unit.update',
        '/organization-units/{id}/{path}',
        {'resource_type': 'organization-unit'},
      );
    });

    test('reads a word ending a POST to a sub-collection as an action only for change words and actions', () {
      expect(name('POST', '/groups/$id/members/add'), 'group.member-add');
      expect(name('POST', '/users/me/agents/suspend'), 'user.agent-suspend');
      expectCall(classify('POST', '$api/groups/$id/members/alice'), 'member.create', '/groups/{id}/members/{id}', {
        'parent_type': 'group',
        'resource_type': 'member',
      });
      expectCall(
        plain.classify('POST', Uri.parse('$api/users/me/agents/suspend')),
        'agent.create',
        '/users/{id}/agents/{id}',
        {'parent_type': 'user', 'resource_type': 'agent'},
      );
    });

    test('keeps only the first segment in the route of a call no rule names', () {
      expectCall(classify('POST', '$api/import/$id/retry-later'), 'api.call', '/import/{id}/{id}', {'method': 'POST'});
      expect(classify('PUT', '$api/v2/12ab/members2')?.route, '/v2/{id}/{id}');
      expect(classify('PUT', '$api/1a2b/v2')?.route, '/{id}/{id}');
    });

    test('reads the path below the longest matching watched base', () {
      final nested = TelemetryApiRules([api, '$api/v2']);
      expectCall(nested.classify('POST', Uri.parse('$api/v2/applications')), 'application.create', '/applications', {
        'resource_type': 'application',
      });
      expect(nested.literalPath(Uri.parse('$api/v2/Roles/R1')), '/roles/r1');
    });

    test('names only changes, and only on a watched API', () {
      expect(name('GET', '/applications'), isNull);
      expect(name('HEAD', '/applications'), isNull);
      expect(name('OPTIONS', '/applications'), isNull);
      expect(classify('POST', 'https://other.example.com/applications'), isNull);
      expect(classify('POST', 'https://env.example.com/applications'), isNull);
    });

    test('reports a failure with its status and only a well-formed error code', () {
      expect(
        TelemetryApiRules.failureData(409, '{"code":"APP-1023","message":"Name taken"}'),
        {'status': '409', 'error_code': 'APP-1023'},
      );
      expect(TelemetryApiRules.failureData(500, '{"code":"typed by the user"}'), {'status': '500'});
      expect(TelemetryApiRules.failureData(null, null), {'status': 'network'});
    });
  });

  group('TelemetryEncoder', () {
    const event = TelemetryEvent(
      id: 'e1',
      name: 'acme.application.create',
      kind: TelemetryEventKind.api,
      timestamp: '2026-01-02T03:04:05.000Z',
      data: {'resource_type': 'application'},
      route: '/applications',
      userId: 'not-a-uuid',
      organizationId: 'B3A1C2D4-0000-4000-8000-000000000001',
      context: {'platform': 'Acme'},
    );

    test('encodes OpenTelemetry log records', () {
      final body =
          jsonDecode(const TelemetryEncoder(TelemetryFormat.otlp).encode([event]).single) as Map<String, Object?>;
      final resourceLog = (body['resourceLogs']! as List).first as Map<String, Object?>;
      final scopeLog = (resourceLog['scopeLogs']! as List).first as Map<String, Object?>;
      final record = (scopeLog['logRecords']! as List).first as Map<String, Object?>;
      expect(record['eventName'], 'acme.application.create');
      expect(
        record['attributes'],
        contains(
          equals({
            'key': 'event.data.resource_type',
            'value': {'stringValue': 'application'},
          }),
        ),
      );
      final resource = resourceLog['resource']! as Map<String, Object?>;
      expect((resource['attributes']! as List).map((a) => (a as Map)['key']), contains('platform'));
    });

    test('reshapes events with a mapping, its filters and spreads', () {
      const encoder = TelemetryEncoder(
        TelemetryFormat.mapping,
        TelemetryMapping(
          tables: {
            'features': {
              'acme.application.create': {'category': 'application', 'tier': 'core'},
            },
          },
          template: {
            'action_name': '{{name}}',
            'company_id': '{{attributes.organization.id | uuid}}',
            'user_id': '{{attributes.user.id | uuid}}',
            'metadata': {
              '...': '{{attributes.data}}',
              '...context': '{{context}}',
              '...feature': '{{name | lookup: features}}',
              'missing': 'x-{{attributes.nothing}}',
            },
            'request': {'time': '{{timestamp}}', 'when': '{{timestamp | date}}'},
          },
        ),
      );
      expect(jsonDecode(encoder.encode([event]).single), [
        {
          'action_name': 'acme.application.create',
          'company_id': 'b3a1c2d4-0000-4000-8000-000000000001',
          'metadata': {'resource_type': 'application', 'platform': 'Acme', 'category': 'application', 'tier': 'core'},
          'request': {
            'time': '2026-01-02T03:04:05.000Z',
            'when': DateTime.parse(event.timestamp).millisecondsSinceEpoch,
          },
        },
      ]);
    });

    test('sends each event on its own when the mapping asks, and nothing for no events', () {
      const encoder = TelemetryEncoder(
        TelemetryFormat.mapping,
        TelemetryMapping(template: {'n': '{{name}}'}, batch: TelemetryBatch.each),
      );
      expect(encoder.encode([event, event]), ['{"n":"acme.application.create"}', '{"n":"acme.application.create"}']);
      expect(encoder.encode([]), isEmpty);
    });
  });

  group('Telemetry', () {
    test('reports every kind with the prefix, the ids and the context, batched', () async {
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          prefix: 'acme',
          context: {'platform': 'Acme'},
        ),
      );
      built.telemetry
        ..page('/applications')
        ..api('POST', Uri.parse('https://api.example.com/applications'), '{}', ok: true)
        ..api(
          'POST',
          Uri.parse('https://api.example.com/groups'),
          '{}',
          ok: false,
          status: 409,
          responseBody: '{"code":"GRP-1004"}',
        )
        ..auth(TelemetryAuthAction.signIn)
        ..link(Uri.parse('https://docs.example.com/guides/start?ref=x#top'))
        ..track('application.template-pick', {'type': 'spa'});
      await built.telemetry.flush();

      expect(_names(built.sent.single), [
        'acme.application.list-view',
        'acme.application.create',
        'acme.group.create-failed',
        'acme.auth.sign-in',
        'acme.link.open',
        'acme.application.template-pick',
      ]);
      final events = built.sent.single;
      expect(
        (events[2]['attributes']! as Map)['data'],
        {'resource_type': 'group', 'status': '409', 'error_code': 'GRP-1004'},
      );
      expect((events[4]['attributes']! as Map)['data'], {'host': 'docs.example.com', 'path': '/guides/{id}'});
      expect((events[0]['attributes']! as Map)['user'], {'id': _user});
      expect((events[0]['attributes']! as Map)['organization'], {'id': _org});
      expect(events[0]['context'], {'platform': 'Acme'});
    });

    test('leaves out excluded and disabled kinds, and renames', () async {
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          apiEvents: TelemetryApiEventsConfig(exclude: ['role.*']),
          authEvents: TelemetryKindConfig(exclude: ['session-expired']),
          links: TelemetryKindConfig(names: {'https://example.com/pricing': 'plan.upgrade-click'}),
          pages: TelemetryKindConfig(exclude: ['/settings/**'], names: {'/home': 'organization.overview-view'}),
        ),
      );
      built.telemetry
        ..page('/settings/general/advanced')
        ..page('/home')
        ..api('DELETE', Uri.parse('https://api.example.com/roles/r1'), null, ok: true)
        ..auth(TelemetryAuthAction.sessionExpired)
        ..link(Uri.parse('https://example.com/pricing'))
        ..link(Uri.parse('mailto:someone@example.com'))
        ..track('user.alice@example.com');
      await built.telemetry.flush();
      expect(_names(built.sent.single), ['organization.overview-view', 'plan.upgrade-click']);

      final off = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          pages: TelemetryKindConfig(enabled: false),
        ),
      );
      off.telemetry.page('/home');
      await off.telemetry.flush();
      expect(off.sent, isEmpty);
    });

    test('names an API event from config first, then from the API, then by the built-in rules', () async {
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          apiEvents: TelemetryApiEventsConfig(
            names: {'POST /import/*': 'configuration.import', 'role.delete': 'role.remove'},
          ),
        ),
      );
      Uri url(String path) => Uri.parse('https://api.example.com$path');
      built.telemetry
        ..api('POST', url('/import/managed'), '{}', ok: true, event: 'import.run')
        ..api('POST', url('/applications/a1/invitations'), '{}', ok: true, event: 'application.invite')
        ..api('POST', url('/applications/a1/invitations'), '{}', ok: true, event: 'Not A Name')
        ..api('DELETE', url('/roles/r1'), null, ok: true)
        ..api('POST', url('/export'), '{}', ok: true)
        ..api('GET', url('/applications'), null, ok: true, event: 'application.list');
      await built.telemetry.flush();
      expect(
        built.sent.single.map((event) => [event['name'], (event['attributes']! as Map)['route']]).toList(),
        [
          ['configuration.import', '/import/{id}'],
          ['application.invite', '/applications/{id}/invitations'],
          ['invitation.create', '/applications/{id}/invitations'],
          ['role.remove', '/roles/{id}'],
          ['api.export', '/export'],
        ],
      );
    });

    test('takes every API-specific rule from configuration', () async {
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          apiEvents: TelemetryApiEventsConfig(
            exclude: ['/oauth2/**', '/**/.search'],
            names: {
              'POST /gateways/*/apply': 'deployment.deploy',
              'POST /gateways/*/apply ?origin': 'deployment.promote',
              'POST /promotions': 'deployment.promote',
            },
            parentActions: {
              'sharing-policies': {'create': 'share', 'delete': 'unshare', 'update': 'share-update'},
            },
            skipWhen: ['dryRun', 'preview'],
          ),
        ),
      );
      Uri url(String path) => Uri.parse('https://api.example.com$path');
      built.telemetry
        ..api('POST', url('/gateways/g1/apply'), '{"origin":"g0"}', ok: true)
        ..api('POST', url('/gateways/g1/apply'), '{}', ok: true)
        ..api('POST', url('/gateways/g1/apply'), '{"dryRun":true}', ok: true)
        ..api('POST', url('/promotions'), '{"preview":true}', ok: true)
        ..api('POST', url('/promotions'), '{}', ok: true)
        ..api('POST', url('/applications/a1/sharing-policies'), '{}', ok: true)
        ..api('POST', url('/oauth2/token'), '{}', ok: true)
        ..api('POST', url('/scim/v2/Users/.search'), '{}', ok: true)
        ..api('POST', url('/users/search'), '{}', ok: true, event: 'none');
      await built.telemetry.flush();
      expect(
        built.sent.single.map((event) => [event['name'], (event['attributes']! as Map)['route']]).toList(),
        [
          ['deployment.promote', '/gateways/{id}/apply'],
          ['deployment.deploy', '/gateways/{id}/apply'],
          ['deployment.promote', '/promotions'],
          ['application.share', '/applications/{id}/sharing-policies'],
        ],
      );
    });

    test('reads the event name from a response header, whatever its case', () {
      expect(telemetryEventFromHeaders({'X-Telemetry-Event': 'application.share'}), 'application.share');
      expect(telemetryEventFromHeaders({'x-telemetry-event': 'role.share'}), 'role.share');
      expect(telemetryEventFromHeaders({'content-type': 'application/json'}), isNull);
    });

    test('skips a call whose URL, literal path, masked path, rules name or final name is excluded', () async {
      Uri url(String path) => Uri.parse('https://api.example.com$path');
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          apiEvents: TelemetryApiEventsConfig(
            exclude: ['/roles/r1', 'group.create', 'theme.renamed'],
            names: {'theme.create': 'theme.renamed'},
          ),
        ),
      );
      built.telemetry
        ..api('DELETE', url('/roles/r1'), null, ok: true)
        ..api('DELETE', url('/roles/r2'), null, ok: true)
        ..api('POST', url('/groups'), '{}', ok: false, status: 409)
        ..api('POST', url('/themes'), '{}', ok: true)
        ..api('POST', url('/applications'), '{}', ok: true, event: 'group.create');
      await built.telemetry.flush();
      expect(_names(built.sent.single), ['role.delete']);
    });

    test('excludes an auth event by its exact action name only', () async {
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          authEvents: TelemetryKindConfig(exclude: ['sign-*', 'sign-out']),
        ),
      );
      built.telemetry
        ..auth(TelemetryAuthAction.signIn)
        ..auth(TelemetryAuthAction.signOut);
      await built.telemetry.flush();
      expect(_names(built.sent.single), ['auth.sign-in']);
    });

    test('puts configuration before the API header when naming a call', () async {
      Uri url(String path) => Uri.parse('https://api.example.com$path');
      final built = _build(
        const TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          apiEvents: TelemetryApiEventsConfig(
            names: {'invitation.create': 'invitation.send', 'role.share': 'role.shared'},
          ),
        ),
      );
      built.telemetry
        ..api('POST', url('/applications/a1/invitations'), '{}', ok: true, event: 'application.invite')
        ..api('POST', url('/roles/r1/grants'), '{}', ok: true, event: 'role.share')
        ..api('POST', url('/roles/r1/grants'), '{}', ok: true, event: 'none');
      await built.telemetry.flush();
      expect(_names(built.sent.single), ['invitation.send', 'role.shared']);
    });

    test('reads the identity when an event is recorded, not when it is sent', () async {
      var user = 'user-a';
      final sent = <List<Map<String, Object?>>>[];
      final telemetry = Telemetry(
        const TelemetryConfig(endpoint: 'https://t.example.com', format: TelemetryFormat.json),
        apiBases: const [],
        identity: () async => (userId: user, organizationId: null),
        send: (body) async => sent.add((jsonDecode(body) as List).cast<Map<String, Object?>>()),
      );
      telemetry.track('a.first');
      user = 'user-b';
      telemetry.track('a.second');
      await telemetry.flush();
      expect(sent.single.map((event) => (event['attributes']! as Map)['user']).toList(), [
        {'id': 'user-a'},
        {'id': 'user-b'},
      ]);
    });

    test('holds events until consent, then sends them', () async {
      var allowed = false;
      final built = _build(
        TelemetryConfig(endpoint: 'https://t.example.com', format: TelemetryFormat.json, consent: () => allowed),
      );
      built.telemetry.page('/home');
      await built.telemetry.flush();
      expect(built.sent, isEmpty);
      allowed = true;
      await built.telemetry.flush();
      expect(built.sent, hasLength(1));
    });

    test('never lets a failed send or identity read reach the app', () async {
      var identityReads = 0;
      var sends = 0;
      final telemetry = Telemetry(
        const TelemetryConfig(endpoint: 'https://t.example.com'),
        apiBases: const [],
        identity: () async {
          identityReads++;
          throw StateError('no session');
        },
        send: (_) async {
          sends++;
          throw StateError('down');
        },
      );
      telemetry.page('/home');
      await expectLater(telemetry.flush(), completes);
      expect([identityReads, sends], [1, 1]);
    });

    test('drops a batch that cannot be encoded and keeps reporting', () async {
      final sent = <String>[];
      final template = <String, Object?>{'n': '{{name}}', 'at': DateTime(2026)};
      final telemetry = Telemetry(
        TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.mapping,
          mapping: TelemetryMapping(template: template),
        ),
        apiBases: const [],
        identity: () async => (userId: null, organizationId: null),
        send: (body) async => sent.add(body),
      );
      telemetry.page('/home');
      await expectLater(telemetry.flush(), completes);
      expect(sent, isEmpty);
      template['at'] = 'fixed';
      telemetry.track('a.b');
      await expectLater(telemetry.flush(), completes);
      await expectLater(telemetry.dispose(), completes);
      expect(sent.map(jsonDecode).toList(), [
        [
          {'n': 'a.b', 'at': 'fixed'},
        ],
      ]);
    });

    group('with a mapping that sends each event alone', () {
      ({List<String> sent, Telemetry telemetry, List<Completer<void>> opened}) build(bool Function() consent) {
        final sent = <String>[];
        final opened = <Completer<void>>[];
        final telemetry = Telemetry(
          TelemetryConfig(
            endpoint: 'https://t.example.com',
            format: TelemetryFormat.mapping,
            mapping: const TelemetryMapping(template: {'n': '{{name}}'}, batch: TelemetryBatch.each),
            consent: consent,
          ),
          apiBases: const [],
          identity: () async => (userId: null, organizationId: null),
          send: (body) {
            sent.add((jsonDecode(body) as Map)['n'] as String);
            final request = Completer<void>();
            opened.add(request);
            return request.future;
          },
        );
        return (sent: sent, telemetry: telemetry, opened: opened);
      }

      Future<void> track(Telemetry telemetry) async {
        telemetry
          ..track('item.a')
          ..track('item.b')
          ..track('item.c');
      }

      /// Lets the open request finish and the next start, if it will.
      Future<void> settle(List<Completer<void>> opened) async {
        for (var round = 0; round < 10; round++) {
          for (final request in opened) {
            if (!request.isCompleted) request.complete();
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      test('sends every body in order while consent holds', () async {
        final built = build(() => true);
        await track(built.telemetry);
        final flushed = built.telemetry.flush();
        await settle(built.opened);
        await flushed;
        expect(built.sent, ['item.a', 'item.b', 'item.c']);
      });

      test('checks consent before each request, keeps the unsent events, and leaves the open one alone', () async {
        var allowed = true;
        final built = build(() => allowed);
        await track(built.telemetry);
        final flushed = built.telemetry.flush();
        await Future<void>.delayed(Duration.zero);
        expect(built.sent, ['item.a']);
        allowed = false;
        await settle(built.opened);
        await flushed;
        expect(built.sent, ['item.a']);
        expect(built.opened.single.isCompleted, isTrue);

        allowed = true;
        final resumed = built.telemetry.flush();
        await settle(built.opened);
        await resumed;
        expect(built.sent, ['item.a', 'item.b', 'item.c']);
        await built.telemetry.dispose();
      });

      test('drops the unsent events when consent is withdrawn while disposing', () async {
        var allowed = true;
        final built = build(() => allowed);
        await track(built.telemetry);
        final disposed = built.telemetry.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(built.sent, ['item.a']);
        allowed = false;
        await settle(built.opened);
        await disposed;
        allowed = true;
        await built.telemetry.flush();
        await settle(built.opened);
        expect(built.sent, ['item.a']);
      });
    });

    test('sends an event without its identity when the identity read does not settle', () async {
      final sent = <List<Map<String, Object?>>>[];
      final telemetry = Telemetry(
        const TelemetryConfig(endpoint: 'https://t.example.com', format: TelemetryFormat.json),
        apiBases: const [],
        identity: () => Completer<TelemetryIdentity>().future,
        send: (body) async => sent.add((jsonDecode(body) as List).cast<Map<String, Object?>>()),
        identityTimeout: const Duration(milliseconds: 20),
      );
      telemetry.track('item.a');
      await expectLater(telemetry.flush(), completes);
      final event = sent.single.single;
      expect(event['name'], 'item.a');
      expect((event['attributes']! as Map).containsKey('user'), isFalse);
    });

    test('schedules one drain for events reported behind a stalled identity read', () async {
      final identity = Completer<TelemetryIdentity>();
      var consentChecks = 0;
      final sent = <List<Map<String, Object?>>>[];
      final telemetry = Telemetry(
        TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          consent: () {
            consentChecks++;
            return true;
          },
        ),
        apiBases: const [],
        identity: () => identity.future,
        send: (body) async => sent.add((jsonDecode(body) as List).cast<Map<String, Object?>>()),
      );
      for (var index = 0; index < 5000; index++) {
        telemetry.track('item.n$index');
        if (index % 500 == 0) await Future<void>.delayed(Duration.zero);
      }
      expect(consentChecks, 0);
      identity.complete((userId: null, organizationId: null));
      await telemetry.flush();
      await telemetry.dispose();
      final names = sent.expand(_names).toList();
      expect(names, [for (var index = 4800; index < 5000; index++) 'item.n$index']);
      // One drain ran, so consent was checked a few times, not once for each report.
      expect(consentChecks, lessThan(20));
    });

    test('keeps at most 200 waiting events while the identity read stalls, dropping the oldest', () async {
      final identity = Completer<TelemetryIdentity>();
      var allowed = false;
      final sent = <List<Map<String, Object?>>>[];
      final telemetry = Telemetry(
        TelemetryConfig(endpoint: 'https://t.example.com', format: TelemetryFormat.json, consent: () => allowed),
        apiBases: const [],
        identity: () => identity.future,
        send: (body) async => sent.add((jsonDecode(body) as List).cast<Map<String, Object?>>()),
      );
      for (var index = 0; index < 250; index++) {
        telemetry.track('item.n$index');
      }
      identity.complete((userId: null, organizationId: null));
      for (var index = 250; index < 260; index++) {
        telemetry.track('item.n$index');
      }
      allowed = true;
      await telemetry.flush();
      final names = sent.expand(_names).toList();
      expect(names, hasLength(200));
      expect(names.first, 'item.n60');
      expect(names.last, 'item.n259');
    });

    test('sends nothing after dispose when consent was not given', () async {
      var allowed = false;
      final built = _build(
        TelemetryConfig(endpoint: 'https://t.example.com', format: TelemetryFormat.json, consent: () => allowed),
      );
      built.telemetry.page('/home');
      await built.telemetry.dispose();
      allowed = true;
      built.telemetry.page('/other');
      await built.telemetry.flush();
      expect(built.sent, isEmpty);
    });
  });
}
