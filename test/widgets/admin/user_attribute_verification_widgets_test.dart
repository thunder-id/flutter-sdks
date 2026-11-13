// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// Answers `GET /users/u-1` with [user] (read again after every send), groups with an empty page,
/// the `customer` user type with [_schemaJson], and `POST /flow/execute` with [execution]. Every
/// request is recorded.
class _Server {
  Map<String, Object?> user;
  Object? execution;

  /// When set, `POST /flow/execute` answers only once it completes.
  Completer<void>? hold;
  final List<ManagementRequest> requests = [];

  /// The `merged` layer of `GET /server-config/flow`; set [configStatus] to fail the read.
  Map<String, Object?> flowConfig = {
    'adminAttributeVerificationFlow': {'defaultHandle': 'configured-verify'},
  };
  int configStatus = 200;

  /// Status of the user type reads; anything else fails them.
  int typeStatus = 200;

  /// The handle the user type read reports.
  String typeHandle = 'customer';

  _Server({required this.user, this.execution});

  ManagementResponse _json(Object? body) =>
      ManagementResponse(statusCode: 200, statusText: 'OK', body: jsonEncode(body));

  Future<ManagementResponse> fetch(ManagementRequest request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/server-config/flow') {
      return configStatus == 200
          ? _json({'merged': flowConfig})
          : ManagementResponse(statusCode: configStatus, statusText: 'Error', body: '{}');
    }
    if (path == '/flow/execute') {
      await hold?.future;
      return _json(execution);
    }
    if (path.startsWith('/user-types')) {
      if (typeStatus != 200) {
        return ManagementResponse(statusCode: typeStatus, statusText: 'Error', body: '{}');
      }
      return path == '/user-types'
          ? _json({
              'totalResults': 1,
              'count': 1,
              'types': [
                {'id': 't-1', 'handle': 'customer', 'ouId': 'ou-1'},
              ],
            })
          : _json({'id': 't-1', 'handle': typeHandle, 'ouId': 'ou-1', 'schema': _schemaJson});
    }
    if (path == '/users/u-1') return _json(user);
    if (path.endsWith('/groups')) return _json({'totalResults': 0, 'groups': <Object?>[]});
    return const ManagementResponse(statusCode: 404, statusText: 'Not Found');
  }

  List<Object?> get executions => [
        for (final r in requests)
          if (r.url.path == '/flow/execute') jsonDecode(r.body!),
      ];

  int get typeReads => requests.where((r) => r.url.path.startsWith('/user-types')).length;

  int get userReads => requests.where((r) => r.method == 'GET' && r.url.path == '/users/u-1').length;
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

Widget _bare(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Finder _key(String key) => find.byKey(Key(key));

const _status = 'thunderid-admin-user-details-verification-status-email';
const _send = 'thunderid-action-user-details-verification-send-email';
const _sent = 'thunderid-admin-user-details-verification-sent';
const _sendWork = 'thunderid-action-user-details-verification-send-workEmail';

const Map<String, Object?> _schemaJson = {
  'username': {'type': 'string'},
  'email': {'type': 'email'},
};

const EntityTypeSchema _schema = _schemaJson;

const EntityTypeSchema _twoEmails = {
  'username': {'type': 'string'},
  'email': {'type': 'email'},
  'workEmail': {'type': 'email'},
  'mobile': {'type': 'mobile'},
};

ManagedUser _user({
  Map<String, VerifiedAttribute>? verified = const {},
  bool isReadOnly = false,
  Map<String, dynamic> attributes = const {'username': 'aiko', 'email': 'aiko@example.com'},
}) =>
    ManagedUser(
      id: 'u-1',
      ouId: 'ou-1',
      type: 'customer',
      display: 'Aiko Tanaka',
      isReadOnly: isReadOnly,
      attributes: attributes,
      verifiedAttributes: verified,
    );

ManagedUser _twoEmailUser() => _user(
      attributes: const {
        'username': 'aiko',
        'email': 'aiko@example.com',
        'workEmail': 'aiko@work.example.com',
        'mobile': '+94771234567',
      },
    );

const _verified = {'email': VerifiedAttribute(verifiedAt: '2026-11-03T10:00:00Z')};

Map<String, Object?> _userJson({Map<String, Object?>? verified = const {}}) => {
      'id': 'u-1',
      'ouId': 'ou-1',
      'type': 'customer',
      'display': 'Aiko Tanaka',
      'attributes': {'username': 'aiko', 'email': 'aiko@example.com'},
      if (verified != null) 'verifiedAttributes': verified,
    };

const Map<String, Object?> _linkSent = {
  'executionId': 'exec-1',
  'flowStatus': 'INCOMPLETE',
  'data': {
    'additionalData': {'channel': 'email', 'emailSent': 'true', 'maskedDestination': 'a***@example.com'},
  },
};

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async => call.method == 'initialize' ? true : (call.method == 'isSignedIn' ? false : null),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('BaseUserDetails verification', () {
    testWidgets('shows an unverified email as Not verified, and sends a link for it', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(_bare(BaseUserDetails(user: _user(), userSchema: _schema, onSendVerification: sent.add)));

      expect(find.descendant(of: _key(_status), matching: find.text('Not verified')), findsOneWidget);
      expect(find.text('aiko@example.com'), findsOneWidget);
      await tester.tap(_key(_send));
      expect(sent, ['email']);
      expect(find.descendant(of: _key(_send), matching: find.text('Verify')), findsOneWidget);
    });

    testWidgets('shows a verified email as Verified, with no send', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(verified: _verified),
            userSchema: _schema,
            onSendVerification: (_) {},
          ),
        ),
      );

      expect(find.descendant(of: _key(_status), matching: find.text('Verified')), findsOneWidget);
      expect(_key(_send), findsNothing);
    });

    testWidgets('shows no status when the server does not report verification', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(verified: null),
            userSchema: _schema,
            onSendVerification: (_) {},
          ),
        ),
      );

      expect(_key(_status), findsNothing);
      expect(_key(_send), findsNothing);
      expect(find.text('aiko@example.com'), findsOneWidget);
    });

    testWidgets('shows the status but no send without a handler, or for a read-only user', (tester) async {
      await tester.pumpWidget(_bare(BaseUserDetails(user: _user(), userSchema: _schema)));
      expect(_key(_status), findsOneWidget);
      expect(_key(_send), findsNothing);

      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(isReadOnly: true),
            userSchema: _schema,
            onSendVerification: (_) {},
          ),
        ),
      );
      expect(_key(_status), findsOneWidget);
      expect(_key(_send), findsNothing);
    });

    testWidgets('shows no status for a hidden email', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            hiddenAttributes: const {'email'},
            onSendVerification: (_) {},
          ),
        ),
      );

      expect(_key(_status), findsNothing);
      expect(find.text('aiko@example.com'), findsNothing);

      UserDetailsState? state;
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            hiddenAttributes: const {'email'},
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(state!.verifiableAttributes, isEmpty);
    });

    testWidgets('waits for an in-flight save before offering to send a link', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        _bare(BaseUserDetails(user: _user(), userSchema: _schema, onSendVerification: sent.add, isUpdating: true)),
      );

      await tester.tap(_key(_send));
      expect(sent, isEmpty);

      await tester.pumpWidget(_bare(BaseUserDetails(user: _user(), userSchema: _schema, onSendVerification: sent.add)));
      expect(sent, isEmpty);
      await tester.tap(_key(_send));
      expect(sent, ['email']);
    });

    testWidgets('disables the send while a link is being sent', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            onSendVerification: sent.add,
            isSendingVerification: true,
          ),
        ),
      );

      await tester.tap(_key(_send));
      expect(sent, isEmpty);
    });

    testWidgets('names the masked destination of a sent link, or none when it is not reported', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            sentVerification: const UserAttributeVerificationResult(
              channel: 'email',
              maskedDestination: 'a***@example.com',
            ),
          ),
        ),
      );
      expect(
        find.descendant(of: _key(_sent), matching: find.text('Verification link sent to a***@example.com.')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            sentVerification: const UserAttributeVerificationResult(channel: 'email'),
          ),
        ),
      );
      expect(find.text('Verification link sent.'), findsOneWidget);
    });

    testWidgets('shows an error instead of the sent message', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            error: 'Could not send the verification link. Please try again.',
            sentVerification: const UserAttributeVerificationResult(channel: 'email'),
          ),
        ),
      );

      expect(_key(_sent), findsNothing);
      expect(find.text('Could not send the verification link. Please try again.'), findsOneWidget);
    });

    testWidgets('hands a builder the verification state and the send handler', (tester) async {
      UserDetailsState? state;
      final sent = <String>[];
      const result = UserAttributeVerificationResult(channel: 'email', maskedDestination: 'a***@example.com');
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            onSendVerification: sent.add,
            isSendingVerification: true,
            sentVerification: result,
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(state!.verifiableAttributes, ['email']);
      expect(state!.verifiedAttributes, isEmpty);
      expect(state!.sendableAttributes, {'email'});
      expect(state!.isSendingVerification, isTrue);
      expect(state!.sentVerification, same(result));
      expect(state!.onSendVerification, isNull, reason: 'no second send while one runs');
    });

    testWidgets('hands a builder no send handler for a read-only user, and nothing verifiable unreported',
        (tester) async {
      UserDetailsState? readOnly;
      UserDetailsState? unreported;
      await tester.pumpWidget(
        _bare(
          Column(
            children: [
              BaseUserDetails(
                user: _user(isReadOnly: true, verified: _verified),
                userSchema: _schema,
                onSendVerification: (_) {},
                builder: (context, s) {
                  readOnly = s;
                  return const SizedBox();
                },
              ),
              BaseUserDetails(
                user: _user(verified: null),
                userSchema: _schema,
                onSendVerification: (_) {},
                builder: (context, s) {
                  unreported = s;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );

      expect(readOnly!.onSendVerification, isNull);
      expect(readOnly!.verifiableAttributes, ['email']);
      expect(readOnly!.verifiedAttributes, _verified);
      expect(unreported!.verifiableAttributes, isEmpty);
      expect(unreported!.verifiedAttributes, isNull);
    });

    testWidgets('labels the action Verify, and names the attribute to assistive technology', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_bare(BaseUserDetails(user: _user(), userSchema: _schema, onSendVerification: (_) {})));

      expect(find.descendant(of: _key(_send), matching: find.text('Verify')), findsOneWidget);
      expect(find.bySemanticsLabel('Verify email'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('lists contact attributes by schema type, and sends only for unverified email', (tester) async {
      UserDetailsState? state;
      final sent = <String>[];
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _twoEmailUser(),
            userSchema: _twoEmails,
            onSendVerification: sent.add,
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(state!.verifiableAttributes, ['email', 'mobile', 'workEmail']);
      expect(state!.sendableAttributes, {'email', 'workEmail'});
      state!.onSendVerification!('mobile');
      state!.onSendVerification!('username');
      expect(sent, isEmpty, reason: 'names that are not sendable are ignored');
      state!.onSendVerification!('workEmail');
      expect(sent, ['workEmail']);
    });

    testWidgets('without a schema, shows only attributes with a record and sends nothing', (tester) async {
      UserDetailsState? state;
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(verified: _verified),
            onSendVerification: (_) {},
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(state!.verifiableAttributes, ['email']);
      expect(state!.sendableAttributes, isEmpty);
      expect(state!.onSendVerification, isNull);

      await tester.pumpWidget(_bare(BaseUserDetails(user: _user(), onSendVerification: (_) {})));
      expect(_key(_status), findsNothing);
      expect(_key(_send), findsNothing);
    });

    testWidgets('hands a builder no send handler while a save runs', (tester) async {
      UserDetailsState? state;
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            isUpdating: true,
            onSendVerification: (_) {},
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(state!.sendableAttributes, {'email'});
      expect(state!.onSendVerification, isNull);
    });

    testWidgets('shows the spinner only on the row being sent', (tester) async {
      final sent = <String>[];
      Widget details({bool sending = false}) => _bare(
            BaseUserDetails(
              user: _twoEmailUser(),
              userSchema: _twoEmails,
              isSendingVerification: sending,
              onSendVerification: sent.add,
            ),
          );
      await tester.pumpWidget(details());
      await tester.tap(_key(_sendWork));
      expect(sent, ['workEmail']);

      await tester.pumpWidget(details(sending: true));
      expect(find.descendant(of: _key(_sendWork), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.descendant(of: _key(_send), matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(find.descendant(of: _key(_send), matching: find.text('Verify')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(_key(_send)).onPressed, isNull, reason: 'other rows wait');
    });

    testWidgets('shows an error when the flow reports the email was not sent', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _user(),
            userSchema: _schema,
            sentVerification: const UserAttributeVerificationResult(channel: 'email', emailSent: false),
          ),
        ),
      );

      expect(_key(_sent), findsNothing);
      expect(find.text('Could not send the verification link. Please try again.'), findsOneWidget);
    });
  });

  group('UserDetails verification', () {
    testWidgets('reads neither the user type nor the configuration unless attributeVerification is on', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent);
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1')));
      await tester.pumpAndSettle();

      expect(_key(_status), findsNothing);
      expect(_key(_send), findsNothing);
      expect(server.typeReads, 0);
      expect(server.requests.where((r) => r.url.path == '/server-config/flow'), isEmpty);
    });

    testWidgets('shows a recorded status without reading the user type when verification is off', (tester) async {
      final server = _Server(
        user: _userJson(
          verified: {
            'email': {'verifiedAt': '2026-11-03T10:00:00Z'},
          },
        ),
      );
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: _key(_status), matching: find.text('Verified')), findsOneWidget);
      expect(server.typeReads, 0);
    });

    testWidgets('reads no user type when the server does not report verification', (tester) async {
      final server = _Server(user: _userJson(verified: null), execution: _linkSent);
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      expect(server.typeReads, 0);
      expect(_key(_status), findsNothing);
    });

    testWidgets("ignores a user type whose handle is not the user's type", (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent)..typeHandle = 'employee';
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      expect(server.typeReads, greaterThan(0));
      expect(_key(_status), findsNothing);
      expect(_key(_send), findsNothing);
    });

    testWidgets('says the settings could not be loaded when the user type read fails', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent)..typeStatus = 500;
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      expect(server.typeReads, greaterThan(0));
      expect(_key(_send), findsNothing);
      expect(find.text('The verification settings could not be loaded.'), findsOneWidget);
    });

    testWidgets('offers no send when the server configures no verification flow', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent)..flowConfig = {};
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      expect(find.text('Not verified'), findsOneWidget);
      expect(_key(_send), findsNothing);
      expect(find.text('The verification settings could not be loaded.'), findsNothing);
    });

    testWidgets('offers no send, and says why, when the configuration cannot be read', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent)..configStatus = 500;
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      expect(_key(_send), findsNothing);
      expect(find.text('The verification settings could not be loaded.'), findsOneWidget);
    });

    testWidgets('sends through the handle the server configures', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent)
        ..flowConfig = {
          'adminAttributeVerificationFlow': {'defaultHandle': 'another-verify'},
        };
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      await tester.tap(_key(_send));
      await tester.pumpAndSettle();

      expect((server.executions.single as Map)['handle'], 'another-verify');
      expect(
        server.requests.where((r) => r.url.path == '/server-config/flow'),
        hasLength(1),
        reason: 'the handle the widget read is passed on, not read again',
      );
    });

    testWidgets('sends the link through the administrator-initiated flow, then reads the user again', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent);
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();
      expect(server.userReads, 1);

      await tester.tap(_key(_send));
      await tester.pumpAndSettle();

      expect(server.executions, [
        {
          'flowType': 'ADMIN_INITIATED',
          'handle': 'configured-verify',
          'inputs': {'subject': 'u-1', 'attribute': 'email'},
          'verbose': true,
        },
      ]);
      expect(find.text('Verification link sent to a***@example.com.'), findsOneWidget);
      expect(server.userReads, 2, reason: 'sending reloads the user');
    });

    testWidgets('shows Verified once the reloaded user is verified', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent);
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();
      server.user = _userJson(
        verified: {
          'email': {'verifiedAt': '2026-11-03T10:00:00Z'},
        },
      );

      await tester.tap(_key(_send));
      await tester.pumpAndSettle();

      expect(find.descendant(of: _key(_status), matching: find.text('Verified')), findsOneWidget);
      expect(_key(_send), findsNothing);
    });

    testWidgets('shows a translated message when the flow refuses, never the server text', (tester) async {
      final server = _Server(
        user: _userJson(),
        execution: {
          'flowStatus': 'ERROR',
          'error': {
            'code': 'FET-1114',
            'message': {'defaultValue': 'The user is suspended'},
          },
        },
      );
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', attributeVerification: true)));
      await tester.pumpAndSettle();

      await tester.tap(_key(_send));
      await tester.pumpAndSettle();

      expect(find.text('Could not send the verification link. Please try again.'), findsOneWidget);
      expect(find.textContaining('suspended'), findsNothing);
      expect(_key(_sent), findsNothing);
    });

    testWidgets('hands a custom render the send handler, which runs the flow', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent);
      UserDetailsState? state;
      await tester.pumpWidget(
        _app(
          server,
          UserDetails(
            userId: 'u-1',
            attributeVerification: true,
            builder: (context, s) {
              state = s;
              return Text(s.sentVerification?.maskedDestination ?? 'none');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(state!.verifiableAttributes, ['email']);
      state!.onSendVerification!('email');
      await tester.pumpAndSettle();

      expect(server.executions, hasLength(1));
      expect(find.text('a***@example.com'), findsOneWidget);
    });

    testWidgets('reports the send as running until the flow answers', (tester) async {
      final server = _Server(user: _userJson(), execution: _linkSent)..hold = Completer<void>();
      UserDetailsState? state;
      await tester.pumpWidget(
        _app(
          server,
          UserDetails(
            userId: 'u-1',
            attributeVerification: true,
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      state!.onSendVerification!('email');
      await tester.pump();
      expect(state!.isSendingVerification, isTrue);

      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(state!.isSendingVerification, isFalse);
    });
  });
}
