// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/paged_select.dart';
import 'package:thunderid_flutter/src/models/user_select.dart';

void main() {
  group('toUserSelectOption default chain (display -> username -> email -> id)', () {
    test('prefers display when set and distinct from the id', () {
      const user = ManagedUser(id: 'u1', display: 'Jane Doe');
      expect(toUserSelectOption(user), const PagedSelectOption('Jane Doe', 'u1'));
    });

    test('display equal to the id is treated as unset, falls back to username', () {
      const user = ManagedUser(id: 'u1', display: 'u1', attributes: {'username': 'jane'});
      expect(toUserSelectOption(user)?.label, 'jane');
    });

    test('falls back to email when there is no username', () {
      const user = ManagedUser(id: 'u1', attributes: {'email': 'jane@example.com'});
      expect(toUserSelectOption(user)?.label, 'jane@example.com');
    });

    test('falls back to the id when nothing else is set', () {
      const user = ManagedUser(id: 'u1');
      expect(toUserSelectOption(user), const PagedSelectOption('u1', 'u1'));
    });

    test('a blank username is treated as unset', () {
      const user = ManagedUser(id: 'u1', attributes: {'username': '   ', 'email': 'jane@example.com'});
      expect(toUserSelectOption(user)?.label, 'jane@example.com');
    });

    test('a non-string attribute is ignored rather than cast', () {
      const user = ManagedUser(id: 'u1', attributes: {'username': 42});
      expect(toUserSelectOption(user)?.label, 'u1');
    });
  });

  group('toUserSelectOption with a custom mapping', () {
    test('overrides the default chain', () {
      const user = ManagedUser(id: 'u1', display: 'Jane Doe', attributes: {'email': 'jane@example.com'});
      const mapping = UserSelectOptionMapping(
        label: _emailAttribute,
        value: _emailAttribute,
      );
      expect(toUserSelectOption(user, mapping: mapping), const PagedSelectOption('jane@example.com', 'jane@example.com'));
    });

    test('drops a user the mapping has no value for', () {
      const user = ManagedUser(id: 'u1');
      const mapping = UserSelectOptionMapping(label: _emailAttribute, value: _emailAttribute);
      expect(toUserSelectOption(user, mapping: mapping), null);
    });
  });

  group('toUserSelectOptions', () {
    test('drops users the mapping has no value for, keeps the rest', () {
      const users = [
        ManagedUser(id: 'u1', display: 'Jane'),
        ManagedUser(id: 'u2'),
      ];
      const mapping = UserSelectOptionMapping(label: _idIfU1, value: _idIfU1);
      final options = toUserSelectOptions(users, mapping: mapping);
      expect(options.map((o) => o.value), ['u1']);
    });
  });

  group('toUserSelectPage', () {
    test('next offset derives from the backend count, not the surviving options', () {
      final response = ManagedUserListResponse(
        totalResults: 100,
        startIndex: 0,
        count: 30,
        users: List.generate(30, (i) => ManagedUser(id: 'u$i', display: 'User $i')),
      );
      final page = toUserSelectPage(response, 0);
      expect(page.options, hasLength(30));
      expect(page.nextOffset, 30);
      expect(page.totalResults, 100);
    });

    test('the last page has a null next offset', () {
      final response = ManagedUserListResponse(
        totalResults: 90,
        startIndex: 60,
        count: 30,
        users: List.generate(30, (i) => ManagedUser(id: 'u$i')),
      );
      expect(toUserSelectPage(response, 60).nextOffset, null);
    });

    test('a mapping that drops every user still advances by the backend count', () {
      final response = ManagedUserListResponse(
        totalResults: 100,
        startIndex: 0,
        count: 30,
        users: List.generate(30, (i) => ManagedUser(id: 'u$i')),
      );
      const mapping = UserSelectOptionMapping(label: _none, value: _none);
      final page = toUserSelectPage(response, 0, mapping: mapping);
      expect(page.options, isEmpty);
      expect(page.nextOffset, 30);
    });
  });

  group('ManagedUser.fromMap', () {
    test('parses a full map', () {
      final user = ManagedUser.fromMap({
        'id': 'u1',
        'ouId': 'ou1',
        'type': 'Person',
        'attributes': {'username': 'jane'},
        'display': 'Jane Doe',
        'isReadOnly': true,
      });
      expect(user.id, 'u1');
      expect(user.ouId, 'ou1');
      expect(user.type, 'Person');
      expect(user.attributes?['username'], 'jane');
      expect(user.display, 'Jane Doe');
      expect(user.isReadOnly, true);
    });

    test('a missing id defaults to an empty string rather than throwing', () {
      expect(ManagedUser.fromMap(const {}).id, '');
    });
  });
}

String? _emailAttribute(ManagedUser user) => user.attributes?['email'] as String?;
String? _idIfU1(ManagedUser user) => user.id == 'u1' ? user.id : null;
String? _none(ManagedUser user) => null;
