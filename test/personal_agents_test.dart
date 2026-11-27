// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const Map<String, Object?> _agentJson = {
  'id': 'pa-1',
  'ouId': 'ou-1',
  'type': 'assistant',
  'kind': 'personal-assistant',
  'clientId': 'spend',
  'description': 'Pays bills',
  'owner': {'id': 'usr-1', 'idType': 'uuid', 'isLocal': true},
  'attributes': {
    'name': 'Spending',
    'model': 'planner-v1',
    'limits': {'monthly': 200},
  },
  'inboundAuthConfig': [
    {
      'type': 'oauth2',
      'config': {
        'grantTypes': ['authorization_code', 'refresh_token'],
        'redirectUris': ['https://assistant.example.com/callback'],
      },
    },
  ],
  'status': {
    'value': 'SUSPENDED',
    'details': {
      'appliedBy': ['owner', 'organization'],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.thunderid/sdk');
  late ThunderIDClient client;
  final List<MethodCall> log = [];
  Object? Function(MethodCall call)? respond;

  setUp(() async {
    log.clear();
    respond = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'initialize') return true;
      return respond?.call(call);
    });
    client = ThunderIDClient();
    await client.initialize(const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'app'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Map<Object?, Object?> argsOf(String method) => log.lastWhere((c) => c.method == method).arguments as Map<Object?, Object?>;

  group('ThunderIDClient personal agents', () {
    test('getMeAgents sends the kind and paging, and reads the page', () async {
      respond = (_) => {
            'totalResults': 3,
            'startIndex': 1,
            'count': 1,
            'agents': [_agentJson],
          };

      final page = await client.getMeAgents(kind: AgentKind.personal, limit: 10, offset: 20);

      expect(argsOf('getMeAgents'), {'kind': 'personal-assistant', 'limit': 10, 'offset': 20});
      expect(page.totalResults, 3);
      expect(page.items.single.name, 'Spending');
      expect(page.items.single.isPersonal, isTrue);
    });

    test('getMeAgents sends nothing it was not given', () async {
      respond = (_) => {'totalResults': 0, 'agents': <Object?>[]};

      await client.getMeAgents();

      expect(argsOf('getMeAgents'), isEmpty);
    });

    test('getMeAgent reads the owner, the kind, who holds it suspended and the OAuth settings', () async {
      respond = (_) => _agentJson;

      final agent = await client.getMeAgent('pa-1');

      expect(argsOf('getMeAgent'), {'id': 'pa-1'});
      expect(agent.owner?.id, 'usr-1');
      expect(agent.owner?.idType, AgentOwnerIdType.uuid);
      expect(agent.owner?.isLocal, isTrue);
      expect(agent.kind, AgentKind.personal);
      expect(agent.status?.suspendedBy, [SuspensionAppliedBy.owner, SuspensionAppliedBy.organization]);
      expect(agent.oauthConfig?.grantTypes, ['authorization_code', 'refresh_token']);
      expect(agent.oauthConfig?.redirectUris, ['https://assistant.example.com/callback']);
    });

    test('updateMeAgent sends the whole request, empty lists included', () async {
      respond = (_) => _agentJson;

      await client.updateMeAgent(
        'pa-1',
        const UpdateMeAgentRequest(attributes: {'name': 'Spending'}, grantTypes: [], redirectUris: []),
      );

      expect(argsOf('updateMeAgent'), {
        'id': 'pa-1',
        'request': {
          'attributes': {'name': 'Spending'},
          'grantTypes': <Object?>[],
          'redirectUris': <Object?>[],
        },
      });
    });

    test('delete, suspend and unsuspend send the agent ID', () async {
      await client.deleteMeAgent('pa-1');
      await client.suspendMeAgent('pa-2');
      await client.unsuspendMeAgent('pa-3');

      expect(argsOf('deleteMeAgent'), {'id': 'pa-1'});
      expect(argsOf('suspendMeAgent'), {'id': 'pa-2'});
      expect(argsOf('unsuspendMeAgent'), {'id': 'pa-3'});
    });

    test('a deletion refreshes the deleted agent and the lists, admin views included, and no other agent', () async {
      final resources = PersonalAgentResources(client);
      final refreshed = <String>[];
      final list = [
        ManagementQueryKeys.meAgents,
        {'kind': 'personal-assistant', 'limit': 20, 'offset': 0},
      ];
      resources.invalidator.subscribe([ManagementQueryKeys.meAgent, 'pa-1'], () => refreshed.add('details'));
      resources.invalidator.subscribe(list, () => refreshed.add('list'));
      resources.invalidator.subscribe([ManagementQueryKeys.meAgent, 'pa-2'], () => refreshed.add('other agent'));
      resources.invalidator.subscribe([ManagementQueryKeys.agent, 'pa-1'], () => refreshed.add('admin details'));
      resources.invalidator.subscribe([ManagementQueryKeys.agents, {'limit': 20}], () => refreshed.add('admin list'));
      resources.invalidator.subscribe([ManagementQueryKeys.agent, 'pa-2'], () => refreshed.add('other admin details'));

      await resources.deleteMeAgentMutation().mutate('pa-1');

      expect(refreshed, unorderedEquals(['details', 'list', 'admin details', 'admin list']));
    });

    test('suspendAllMeAgents reads how many agents it suspended', () async {
      respond = (_) => {'suspendedCount': 2};

      final result = await client.suspendAllMeAgents();

      expect(result.suspendedCount, 2);
    });

    test('maps a native refusal to its error code', () async {
      respond = (_) => throw PlatformException(code: 'FORBIDDEN', message: 'Forbidden');

      await expectLater(
        client.getMeAgent('pa-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.forbidden)),
      );
    });

    test('maps a native not-found to its own error code', () async {
      respond = (_) => throw PlatformException(code: 'NOT_FOUND', message: 'Not found');

      await expectLater(
        client.getMeAgent('pa-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.notFound)),
      );
    });

    test('refuses before initialization', () async {
      await expectLater(
        ThunderIDClient().getMeAgents(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );
    });
  });

  group('Agent', () {
    test('reads the name from the display, then the name attribute', () {
      expect(Agent.fromJson(const {'id': 'a', 'display': 'Shown', 'attributes': {'name': 'Stored'}}).name, 'Shown');
      expect(Agent.fromJson(const {'id': 'a', 'attributes': {'name': 'Stored'}}).name, 'Stored');
      expect(Agent.fromJson(const {'id': 'a'}).name, 'a');
    });

    test('prefers the display to a top-level name, and skips an empty one', () {
      expect(Agent.fromJson(const {'id': 'a', 'name': 'Internal', 'display': 'Public'}).name, 'Public');
      expect(Agent.fromJson(const {'id': 'a', 'name': '', 'display': 'Public'}).name, 'Public');
      expect(Agent.fromJson(const {'id': 'a', 'display': '', 'attributes': {'name': 'Stored'}}).name, 'Stored');
      expect(Agent.fromJson(const {'id': 'a', 'name': 'Legacy'}).name, 'Legacy');
    });

    test('reads an ordinary agent with no owner or kind', () {
      final agent = Agent.fromJson(const {'id': 'a', 'ouId': 'ou', 'type': 'bot'});

      expect(agent.owner, isNull);
      expect(agent.kind, isNull);
      expect(agent.isPersonal, isFalse);
      expect(agent.oauthConfig, isNull);
      expect(agent.status?.suspendedBy ?? const <String>[], isEmpty);
    });

    test('sends the owner as an object', () {
      const request = CreateAgentRequest(
        name: 'Spending',
        ouId: 'ou-1',
        type: 'assistant',
        owner: AgentOwner(id: 'usr-1'),
        kind: AgentKind.personal,
      );

      expect(request.toJson()['owner'], {'id': 'usr-1'});
      expect(request.toJson()['kind'], 'personal-assistant');
      expect(const UpdateAgentRequest(owner: AgentOwner(id: 'usr-2', isLocal: true)).toJson()['owner'], {
        'id': 'usr-2',
        'isLocal': true,
      });
    });
  });

  group('MeAgentSuspensionAction', () {
    test('offers unsuspend only while the owner holds the agent suspended', () {
      AccessStatus suspendedBy(List<String> parties) => AccessStatus(
            value: AccessStatusValue.suspended,
            details: AccessStatusDetails(appliedBy: parties),
          );

      expect(MeAgentSuspensionAction.available(suspendedBy(['owner'])), MeAgentSuspensionAction.unsuspend);
      expect(MeAgentSuspensionAction.available(suspendedBy(['organization'])), MeAgentSuspensionAction.suspend);
      expect(MeAgentSuspensionAction.available(suspendedBy(['cascade'])), MeAgentSuspensionAction.suspend);
      expect(
        MeAgentSuspensionAction.available(const AccessStatus(value: AccessStatusValue.active)),
        MeAgentSuspensionAction.suspend,
      );
      expect(MeAgentSuspensionAction.available(null), MeAgentSuspensionAction.suspend);
    });

    test('reads no suspending party unless the agent is suspended', () {
      const active = AccessStatus(
        value: AccessStatusValue.active,
        details: AccessStatusDetails(appliedBy: ['owner']),
      );

      expect(active.suspendedBy, isEmpty);
    });
  });

  group('PersonalAgentFormValues', () {
    final agent = Agent.fromJson(_agentJson);

    test('starts from the agent, editing only its text attributes', () {
      final values = PersonalAgentFormValues.fromAgent(agent);

      expect(values.name, 'Spending');
      expect(values.description, 'Pays bills');
      expect(values.attributes, {'model': 'planner-v1'});
      expect(values.grantTypes, ['authorization_code', 'refresh_token']);
      expect(values.redirectUris, 'https://assistant.example.com/callback');
    });

    test('reads one redirect URI per line, keeping commas inside a URI', () {
      final values = PersonalAgentFormValues.fromAgent(agent)
          .copyWith(redirectUris: ' https://a.example/cb?pair=a,b\n\nhttps://b.example \nhttps://c.example ');

      expect(values.redirectUriList, ['https://a.example/cb?pair=a,b', 'https://b.example', 'https://c.example']);
    });

    test('round-trips a redirect URI that holds a comma', () {
      final withComma = Agent.fromJson({
        ..._agentJson,
        'inboundAuthConfig': [
          {
            'type': 'oauth2',
            'config': {
              'grantTypes': ['authorization_code'],
              'redirectUris': ['https://a.example/cb?pair=a,b', 'https://b.example/cb'],
            },
          },
        ],
      });

      expect(PersonalAgentFormValues.fromAgent(withComma).updateRequest(withComma).redirectUris, [
        'https://a.example/cb?pair=a,b',
        'https://b.example/cb',
      ]);
    });

    test('needs a name, and a redirect URI for the authorization code grant', () {
      final values = PersonalAgentFormValues.fromAgent(agent);

      expect(values.isValid, isTrue);
      expect(values.copyWith(name: '  ').isValid, isFalse);
      expect(values.copyWith(redirectUris: '').isValid, isFalse);
      expect(values.copyWith(redirectUris: '', grantTypes: [PersonalAgentGrantTypes.ciba]).isValid, isTrue);
    });

    test('builds the update request, sending back the attributes the form does not edit', () {
      final request = PersonalAgentFormValues.fromAgent(agent)
          .copyWith(name: ' Spender ', description: ' Pays ', attributes: {'model': 'planner-v2'})
          .updateRequest(agent);

      expect(request.attributes, {
        'name': 'Spender',
        'model': 'planner-v2',
        'limits': {'monthly': 200},
      });
      expect(request.description, 'Pays');
      expect(request.grantTypes, ['authorization_code', 'refresh_token']);
      expect(request.redirectUris, ['https://assistant.example.com/callback']);
    });
  });

  group('getAccountLifecycleActions for an agent', () {
    const flows = {'agentSuspendFlow': 'f-suspend', 'agentUnsuspendFlow': 'f-unsuspend'};
    const kind = AccountLifecycleSubjectKind.agent;

    test('offers the organization its own suspension when only others hold the agent suspended', () {
      expect(
        getAccountLifecycleActions(kind, AccessStatusValue.suspended, flows, appliedBy: ['owner']),
        [AccountLifecycleAction.suspend],
      );
      expect(
        getAccountLifecycleActions(kind, AccessStatusValue.suspended, flows, appliedBy: ['owner', 'cascade']),
        [AccountLifecycleAction.suspend],
      );
    });

    test('offers unsuspend while the organization holds a suspension, or when no party is named', () {
      expect(
        getAccountLifecycleActions(kind, AccessStatusValue.suspended, flows, appliedBy: ['owner', 'organization']),
        [AccountLifecycleAction.unsuspend],
      );
      expect(getAccountLifecycleActions(kind, AccessStatusValue.suspended, flows), [AccountLifecycleAction.unsuspend]);
      expect(
        getAccountLifecycleActions(kind, AccessStatusValue.suspended, flows, appliedBy: const []),
        [AccountLifecycleAction.unsuspend],
      );
    });
  });
}
