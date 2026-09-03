// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/user.dart';
import 'package:thunderid_flutter/src/models/user_profile.dart' as model;
import 'package:thunderid_flutter/src/widgets/user_profile.dart';

model.UserProfile _profile(Map<String, dynamic> attributes) =>
    model.UserProfile(id: 'user-1', attributes: attributes);

void main() {
  group('buildProfileFields', () {
    test('skips credential attributes', () {
      final fields = buildProfileFields(
        const {
          'password': model.AttributeSchema(credential: true),
          'email': model.AttributeSchema(type: 'STRING'),
        },
        _profile({'email': 'ada@example.com'}),
      );

      expect(fields.map((f) => f.name), ['email']);
    });

    test('sorts fields by attribute name', () {
      final fields = buildProfileFields(
        const {
          'zip': model.AttributeSchema(),
          'age': model.AttributeSchema(),
          'name': model.AttributeSchema(),
        },
        _profile(const {}),
      );

      expect(fields.map((f) => f.name), ['age', 'name', 'zip']);
    });

    test('derives readonly from readOnly, mutability and the readonly list', () {
      final fields = buildProfileFields(
        const {
          'a': model.AttributeSchema(readOnly: true),
          'b': model.AttributeSchema(mutability: 'READ_ONLY'),
          'username': model.AttributeSchema(),
          'nickname': model.AttributeSchema(),
        },
        _profile(const {}),
      );

      final readonly = {for (final f in fields) f.name: f.isReadonly};
      expect(readonly, {
        'a': true,
        'b': true,
        'username': true,
        'nickname': false,
      });
    });

    test('flags list values as multi-valued', () {
      final fields = buildProfileFields(
        const {
          'emails': model.AttributeSchema(),
          'displayName': model.AttributeSchema(),
        },
        _profile({
          'emails': ['a@example.com', 'b@example.com'],
          'displayName': 'Ada',
        }),
      );

      final multi = {for (final f in fields) f.name: f.isMultiValued};
      expect(multi, {'emails': true, 'displayName': false});
    });

    test('keeps schema attributes absent from the profile', () {
      final fields = buildProfileFields(
        const {'phone': model.AttributeSchema()},
        _profile(const {}),
      );

      expect(fields.single.name, 'phone');
      expect(fields.single.rawValue, isNull);
    });
  });

  group('validateField', () {
    test('rejects a blank required value', () {
      expect(
        validateField(const model.AttributeSchema(required: true), '   '),
        'userProfile.validation.required',
      );
    });

    test('allows a blank optional value', () {
      expect(validateField(const model.AttributeSchema(), ''), isNull);
    });

    test('rejects a value that fails the pattern', () {
      expect(
        validateField(const model.AttributeSchema(regex: r'^\d+$'), 'abc'),
        'userProfile.validation.pattern',
      );
    });

    test('accepts a value that matches the pattern', () {
      expect(
        validateField(const model.AttributeSchema(regex: r'^\d+$'), '42'),
        isNull,
      );
    });

    test('skips the pattern when the value is blank and optional', () {
      expect(
        validateField(const model.AttributeSchema(regex: r'^\d+$'), ''),
        isNull,
      );
    });

    test('checks required before the pattern', () {
      expect(
        validateField(
          const model.AttributeSchema(required: true, regex: r'^\d+$'),
          '',
        ),
        'userProfile.validation.required',
      );
    });

    test('ignores a pattern that cannot be compiled', () {
      expect(
        validateField(const model.AttributeSchema(regex: '['), 'anything'),
        isNull,
      );
    });
  });

  group('formatClaim', () {
    test('formats scalars', () {
      expect(formatClaim('Ada'), 'Ada');
      expect(formatClaim(true), 'Yes');
      expect(formatClaim(false), 'No');
      expect(formatClaim(42), '42');
    });

    test('joins list values', () {
      expect(formatClaim(['a', 'b']), 'a, b');
    });

    test('drops empty and unsupported values', () {
      expect(formatClaim(''), isNull);
      expect(formatClaim(null), isNull);
      expect(formatClaim(<String>[]), isNull);
      expect(formatClaim({'nested': 'map'}), isNull);
    });
  });

  group('claimLabel', () {
    test('humanizes snake_case', () {
      expect(claimLabel('given_name'), 'Given Name');
    });

    test('humanizes camelCase', () {
      expect(claimLabel('displayName'), 'Display Name');
    });

    test('capitalizes a single word', () {
      expect(claimLabel('email'), 'Email');
    });
  });

  group('claimsDisplayName', () {
    test('prefers given and family name', () {
      expect(
        claimsDisplayName(
          const User({'given_name': 'Ada', 'family_name': 'Lovelace'}),
        ),
        'Ada Lovelace',
      );
    });

    test('falls back through displayName, username then email', () {
      expect(claimsDisplayName(const User({'displayName': 'Ada'})), 'Ada');
      expect(claimsDisplayName(const User({'username': 'ada'})), 'ada');
      expect(
        claimsDisplayName(const User({'email': 'ada@example.com'})),
        'ada@example.com',
      );
    });

    test('falls back to Guest', () {
      expect(claimsDisplayName(null), 'Guest');
      expect(claimsDisplayName(const User({})), 'Guest');
    });
  });

  group('buildProfileFieldsFromClaims', () {
    test('excludes reserved protocol claims', () {
      final fields = buildProfileFieldsFromClaims(
        const User({'sub': 'abc', 'iss': 'thunderid', 'email': 'a@b.c'}),
      );

      expect(fields.map((f) => f.name), ['email']);
    });

    test('renders every field read-only', () {
      final fields = buildProfileFieldsFromClaims(
        const User({'email': 'a@b.c', 'displayName': 'Ada'}),
      );

      expect(fields.every((f) => f.isReadonly), isTrue);
    });

    test('sorts by humanized label', () {
      final fields = buildProfileFieldsFromClaims(
        const User({'zoneinfo': 'UTC', 'displayName': 'Ada'}),
      );

      expect(fields.map((f) => f.label), ['Display Name', 'Zoneinfo']);
    });

    test('returns nothing for a signed-out user', () {
      expect(buildProfileFieldsFromClaims(null), isEmpty);
    });
  });

  group('mapAttribute', () {
    test('resolves through the default mapping order', () {
      expect(
        mapAttribute('email', const {}, _profile({'email': 'a@b.c'})),
        'a@b.c',
      );
    });

    test('resolves a nested attribute path', () {
      expect(
        mapAttribute(
          'firstName',
          const {},
          _profile({
            'name': {'givenName': 'Ada'},
          }),
        ),
        'Ada',
      );
    });

    test('prefers a caller-supplied mapping', () {
      expect(
        mapAttribute(
          'email',
          const {
            'email': ['workEmail'],
          },
          _profile({'workEmail': 'work@b.c', 'email': 'a@b.c'}),
        ),
        'work@b.c',
      );
    });

    test('reads an unmapped key straight off the profile', () {
      expect(
        mapAttribute('nickname', const {}, _profile({'nickname': 'Addie'})),
        'Addie',
      );
    });

    test('returns null when nothing resolves', () {
      expect(mapAttribute('email', const {}, _profile(const {})), isNull);
    });
  });

  group('computeDisplayName', () {
    test('combines first and last name', () {
      expect(
        computeDisplayName(
          const {},
          _profile({
            'name': {'givenName': 'Ada', 'familyName': 'Lovelace'},
          }),
        ),
        'Ada Lovelace',
      );
    });

    test('falls back to username then id', () {
      expect(
        computeDisplayName(const {}, _profile({'userName': 'ada'})),
        'ada',
      );
      expect(computeDisplayName(const {}, _profile(const {})), 'user-1');
    });
  });

  group('stringifyFieldValue', () {
    test('renders scalars, lists, maps and null', () {
      expect(stringifyFieldValue(null), '');
      expect(stringifyFieldValue('Ada'), 'Ada');
      expect(stringifyFieldValue(42), '42');
      expect(stringifyFieldValue(['a', 'b']), 'a, b');
      expect(stringifyFieldValue({'nested': 'map'}), '');
    });
  });

  group('buildUpdatePayload', () {
    test('builds a flat payload', () {
      expect(buildUpdatePayload('displayName', 'Ada', false), {
        'displayName': 'Ada',
      });
    });

    test('nests a dot-separated attribute path', () {
      expect(buildUpdatePayload('name.givenName', 'Ada', false), {
        'name': {'givenName': 'Ada'},
      });
    });

    test('splits a multi-valued attribute on commas', () {
      expect(buildUpdatePayload('emails', 'a@b.c, d@e.f', true), {
        'emails': ['a@b.c', 'd@e.f'],
      });
    });

    test('drops blank entries from a multi-valued attribute', () {
      expect(buildUpdatePayload('emails', 'a@b.c, , ', true), {
        'emails': ['a@b.c'],
      });
    });
  });

  group('buildUpdatePayload BOOLEAN coercion', () {
    test('sends a JSON boolean for a BOOLEAN-typed attribute', () {
      expect(
        buildUpdatePayload('optIn', 'true', false, type: 'BOOLEAN'),
        {'optIn': true},
      );
      expect(
        buildUpdatePayload('optIn', 'false', false, type: 'BOOLEAN'),
        {'optIn': false},
      );
    });

    test('leaves non-BOOLEAN attributes as strings', () {
      expect(
        buildUpdatePayload('displayName', 'true', false, type: 'STRING'),
        {'displayName': 'true'},
      );
      expect(buildUpdatePayload('displayName', 'Ada', false), {'displayName': 'Ada'});
    });
  });

  group('deepMergeAttributes', () {
    test('merges nested maps instead of replacing them', () {
      final merged = deepMergeAttributes(
        {
          'name': {'givenName': 'Ada', 'familyName': 'Lovelace'},
        },
        {
          'name': {'givenName': 'Grace'},
        },
      );

      expect(merged, {
        'name': {'givenName': 'Grace', 'familyName': 'Lovelace'},
      });
    });

    test('carries untouched attributes through', () {
      final merged = deepMergeAttributes(
        {'email': 'a@b.c', 'displayName': 'Ada'},
        {'displayName': 'Grace'},
      );

      expect(merged, {'email': 'a@b.c', 'displayName': 'Grace'});
    });

    test('replaces a scalar with a map and leaves the base untouched', () {
      final base = {'name': 'Ada'};
      final merged = deepMergeAttributes(base, {
        'name': {'givenName': 'Ada'},
      });

      expect(merged, {
        'name': {'givenName': 'Ada'},
      });
      expect(base, {'name': 'Ada'});
    });
  });

  group('UserProfile.fromMap', () {
    test('reads the /users/me envelope', () {
      final profile = model.UserProfile.fromMap(const {
        'id': 'user-1',
        'ouId': 'ou-1',
        'type': 'person',
        'display': 'Ada',
        'isReadOnly': true,
        'attributes': {'email': 'a@b.c'},
      });

      expect(profile.id, 'user-1');
      expect(profile.ouId, 'ou-1');
      expect(profile.type, 'person');
      expect(profile.display, 'Ada');
      expect(profile.isReadOnly, isTrue);
      expect(profile.attributes, {'email': 'a@b.c'});
    });

    test('defaults every optional field', () {
      final profile = model.UserProfile.fromMap(const {'id': 'user-1'});

      expect(profile.ouId, isNull);
      expect(profile.isReadOnly, isFalse);
      expect(profile.attributes, isEmpty);
    });

    test('deep-casts the nested maps the platform channel hands back', () {
      // The channel decodes nested containers as Map<Object?, Object?>, which
      // buildProfileFields and deepMergeAttributes cannot pattern-match on.
      final profile = model.UserProfile.fromMap(<Object?, Object?>{
        'id': 'user-1',
        'attributes': <Object?, Object?>{
          'name': <Object?, Object?>{'givenName': 'Ada'},
        },
      });

      expect(profile.attributes['name'], isA<Map<String, dynamic>>());
      expect(mapAttribute('firstName', const {}, profile), 'Ada');
    });
  });

  group('AttributeSchema.fromMap', () {
    test('reads every documented field', () {
      final schema = model.AttributeSchema.fromMap(const {
        'credential': false,
        'description': 'Work email',
        'displayName': 'Email',
        'mutability': 'READ_WRITE',
        'readOnly': false,
        'regex': r'^\S+@\S+$',
        'required': true,
        'type': 'STRING',
        'unique': true,
        'subAttributes': [
          {'displayName': 'Primary', 'type': 'BOOLEAN'},
        ],
      });

      expect(schema.displayName, 'Email');
      expect(schema.mutability, 'READ_WRITE');
      expect(schema.required, isTrue);
      expect(schema.unique, isTrue);
      expect(schema.subAttributes?.single.displayName, 'Primary');
    });
  });

  group('parallel profile load', () {
    test('a failure on either request does not escape as an unhandled error',
        () async {
      // Mirrors UserProfile._load: both futures must carry an error handler, or the
      // one that is not awaited first reports its failure to the enclosing zone.
      Object? zoneError;
      await runZonedGuarded(
        () async {
          final schema = Future<Object>.error(StateError('schema failed'));
          final profile = Future<Object>.delayed(
            const Duration(milliseconds: 10),
            () => throw StateError('profile failed'),
          );
          try {
            await Future.wait<Object>([schema, profile]);
          } catch (_) {
            // Handled the same way the widget handles it.
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        },
        (error, stack) => zoneError = error,
      );

      expect(zoneError, isNull);
    });
  });
}
