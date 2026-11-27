// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'telemetry_config.dart';

final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
final RegExp _expression = RegExp(r'\{\{([^}]+)\}\}');
final RegExp _wholeExpression = RegExp(r'^\{\{([^}]+)\}\}$');

/// Encodes a batch of events into request bodies for the configured format.
class TelemetryEncoder {
  final TelemetryFormat format;
  final TelemetryMapping? mapping;

  const TelemetryEncoder(this.format, [this.mapping]);

  /// The request bodies for a batch: one, or one per event for a mapping that sends each alone.
  List<String> encode(List<TelemetryEvent> events) {
    if (events.isEmpty) return const [];
    switch (format) {
      case TelemetryFormat.json:
        return [jsonEncode(events.map((event) => event.toJson()).toList())];
      case TelemetryFormat.mapping:
        final mapped = events.map(map).toList();
        return mapping?.batch == TelemetryBatch.each ? mapped.map(jsonEncode).toList() : [jsonEncode(mapped)];
      case TelemetryFormat.otlp:
        return [jsonEncode(_otlp(events))];
    }
  }

  /// One event reshaped by the mapping's template.
  Object? map(TelemetryEvent event) => _render(mapping?.template ?? const {}, event.toJson());

  /// OpenTelemetry log records (OTLP/HTTP JSON): one record per event, named by `event.name`, with
  /// the event's codes as attributes and the context as resource attributes.
  static Map<String, Object?> _otlp(List<TelemetryEvent> events) {
    List<Map<String, Object?>> attributes(Map<String, String?> values) => [
          for (final entry in values.entries)
            if (entry.value != null)
              {
                'key': entry.key,
                'value': {'stringValue': entry.value},
              },
        ];

    return {
      'resourceLogs': [
        {
          'resource': {
            'attributes': attributes({'service.name': 'unknown_service', ...events.first.context}),
          },
          'scopeLogs': [
            {
              'logRecords': [
                for (final event in events)
                  {
                    'attributes': attributes({
                      'event.id': event.id,
                      'event.kind': event.kind.name,
                      'event.name': event.name,
                      'organization.id': event.organizationId,
                      'url.template': event.route,
                      'user.id': event.userId,
                      'os.name': event.os?.name,
                      'os.version': event.os?.version,
                      for (final entry in event.data.entries) 'event.data.${entry.key}': entry.value,
                    }),
                    'body': {'stringValue': event.name},
                    'eventName': event.name,
                    'timeUnixNano': '${DateTime.parse(event.timestamp).microsecondsSinceEpoch}000',
                  },
              ],
              'scope': {'name': 'telemetry'},
            },
          ],
        },
      ],
    };
  }

  Object? _render(Object? node, Map<String, Object?> event) {
    if (node is String) return _fill(node, event);
    if (node is List) {
      return [
        for (final item in node)
          if (_render(item, event) case final rendered?) rendered,
      ];
    }
    if (node is Map) {
      final result = <String, Object?>{};
      for (final entry in node.entries) {
        final key = '${entry.key}';
        final rendered = _render(entry.value, event);
        if (key.startsWith('...')) {
          if (rendered is Map) result.addAll(rendered.cast<String, Object?>());
        } else if (rendered != null) {
          result[key] = rendered;
        }
      }
      return result;
    }
    return node;
  }

  Object? _fill(String template, Map<String, Object?> event) {
    final whole = _wholeExpression.firstMatch(template);
    if (whole != null) return _evaluate(whole.group(1)!, event);
    var missing = false;
    final filled = template.replaceAllMapped(_expression, (match) {
      final value = _evaluate(match.group(1)!, event);
      if (value == null) {
        missing = true;
        return '';
      }
      return value is String ? value : jsonEncode(value);
    });
    return missing ? null : filled;
  }

  Object? _evaluate(String expression, Map<String, Object?> event) {
    final parts = expression.split('|').map((part) => part.trim()).toList();
    Object? value = event;
    for (final key in parts.first.split('.')) {
      value = value is Map ? value[key] : null;
    }
    for (final filter in parts.skip(1)) {
      value = _filter(filter, value);
    }
    return value;
  }

  /// `uuid`: the value when it is a UUID, lower-cased; `lookup: <table>`: the value's entry in
  /// one of the mapping's tables; `date`: an ISO 8601 time as milliseconds since the epoch.
  Object? _filter(String filter, Object? value) {
    final separator = filter.indexOf(':');
    final name = (separator < 0 ? filter : filter.substring(0, separator)).trim();
    final argument = separator < 0 ? '' : filter.substring(separator + 1).trim();
    switch (name) {
      case 'uuid':
        return value is String && _uuid.hasMatch(value) ? value.toLowerCase() : null;
      case 'lookup':
        return value is String ? (mapping?.tables[argument]?[value]) : null;
      case 'date':
        return value is String ? DateTime.tryParse(value)?.millisecondsSinceEpoch : null;
      default:
        return value;
    }
  }
}
