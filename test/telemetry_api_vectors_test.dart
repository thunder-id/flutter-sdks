// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry_config.dart';

/// Replays the API naming vectors every SDK shares, so each names, routes and describes a call the
/// same way.
void main() {
  final vectors =
      jsonDecode(File('test/fixtures/telemetry-api-vectors.json').readAsStringSync()) as Map<String, Object?>;
  final apiBase = vectors['apiBase']! as String;
  final configs = (vectors['configs']! as Map).cast<String, Object?>();
  final cases = (vectors['cases']! as List).cast<Map<String, Object?>>();

  List<String> strings(Object? value) => [for (final item in (value as List?) ?? const []) item as String];

  TelemetryApiEventsConfig apiEvents(Map<String, Object?> config) => TelemetryApiEventsConfig(
        exclude: strings(config['exclude']),
        names: ((config['names'] as Map?) ?? const {}).cast<String, String>(),
        parentActions: {
          for (final entry in ((config['parentActions'] as Map?) ?? const {}).entries)
            entry.key as String: (entry.value as Map).cast<String, String>(),
        },
        skipWhen: strings(config['skipWhen']),
        kinds: strings(config['kinds']),
        addressWords: strings(config['addressWords']),
        actions: strings(config['actions']),
      );

  test('names every shared API vector as the other SDKs do', () async {
    final failures = <String>[];
    for (final vector in cases) {
      final sent = <Map<String, Object?>>[];
      final telemetry = Telemetry(
        TelemetryConfig(
          endpoint: 'https://t.example.com',
          format: TelemetryFormat.json,
          apiEvents: apiEvents((configs[vector['config']]! as Map).cast<String, Object?>()),
        ),
        apiBases: [apiBase],
        identity: () async => (userId: null, organizationId: null),
        send: (body) async => sent.addAll((jsonDecode(body) as List).cast<Map<String, Object?>>()),
      );
      final outcome = (vector['outcome']! as Map).cast<String, Object?>();
      final body = vector['body'];
      final responseBody = outcome['responseBody'];
      telemetry.api(
        vector['method']! as String,
        Uri.parse('$apiBase${vector['path']}'),
        body == null ? null : jsonEncode(body),
        ok: outcome['ok']! as bool,
        status: outcome['status'] as int?,
        responseBody: responseBody == null ? null : jsonEncode(responseBody),
      );
      await telemetry.flush();
      final expected = vector['expect'] as Map?;
      final label = '${vector['config']} ${vector['method']} ${vector['path']}';
      // A vector names one event or none, so any other count is a failure before the payload.
      final count = expected == null ? 0 : 1;
      if (sent.length != count) {
        failures.add('$label: expected $count event(s), got ${sent.length}');
        continue;
      }
      final event = sent.isEmpty ? null : sent.single;
      final actual = event == null
          ? null
          : {
              'name': event['name'],
              'route': (event['attributes']! as Map)['route'],
              'data': (event['attributes']! as Map)['data'] ?? const {},
            };
      if (jsonEncode(_sorted(actual)) != jsonEncode(_sorted(expected))) {
        failures.add('$label: expected ${jsonEncode(_sorted(expected))}, got ${jsonEncode(_sorted(actual))}');
      }
    }
    expect(failures, isEmpty, reason: '${failures.length} of ${cases.length} vectors differ:\n${failures.join('\n')}');
  });
}

/// A JSON value with every map's keys in order, so two values compare by content.
Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}
