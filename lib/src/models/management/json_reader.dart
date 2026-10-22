// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

// Lenient readers for management API payloads. Package-internal (not exported): a field of the
// wrong type reads as absent rather than throwing, so one malformed record cannot fail a page.

Map<String, dynamic> readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, v) => MapEntry(key.toString(), v));
  return <String, dynamic>{};
}

String readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : (value?.toString() ?? '');
}

String? readOptionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

bool? readOptionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is bool ? value : null;
}

int readInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

List<Object?> readList(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is List ? value : const <Object?>[];
}

List<String> readStringList(Map<String, dynamic> json, String key) =>
    readList(json, key).whereType<String>().toList(growable: false);

List<String>? readOptionalStringList(Map<String, dynamic> json, String key) =>
    json[key] is List ? readStringList(json, key) : null;
