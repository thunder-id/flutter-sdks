// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

final RegExp _errorCode = RegExp(r'^[A-Z][A-Z0-9_]*-\d+$');

/// A plain word in a link's path, kept as it is; any other segment can be an id or a token.
final RegExp _plainSegment = RegExp(r'^[A-Za-z_-]{1,40}$');

/// What an application's own event name must look like: lower-case words of letters, digits and `-`,
/// separated by `.`, with at least a type and an action.
final RegExp _eventName = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*(?:\.[a-z0-9]+(?:-[a-z0-9]+)*)+$');

/// A value that could be personal: an email address, a URL, a query or fragment, or free text.
final RegExp _personalValue = RegExp(r'[@?#\s]|://');

/// Event names: `[prefix.]<type>.<action>`, the type singular and a multi-word action
/// hyphenated, a failure ending in `-failed` and a page ending in `-view`. Also matches the
/// `exclude` patterns.
abstract final class TelemetryNames {
  /// Whether [value] matches [pattern]: `*` matches the rest of one path segment, `**` the rest
  /// of the value, and anything else must be equal.
  static bool matches(String value, String pattern) {
    final expression = StringBuffer('^');
    for (var index = 0; index < pattern.length; index++) {
      final char = pattern[index];
      if (char == '*' && index + 1 < pattern.length && pattern[index + 1] == '*') {
        expression.write('.*');
        index++;
      } else if (char == '*') {
        expression.write('[^/]*');
      } else {
        expression.write(RegExp.escape(char));
      }
    }
    expression.write(r'$');
    return RegExp(expression.toString()).hasMatch(value);
  }

  /// Whether [value] matches any of [patterns].
  static bool matchesAny(String value, List<String> patterns) => patterns.any((pattern) => matches(value, pattern));

  /// The singular of a collection's path segment: `applications` is `application`, `policies` is
  /// `policy`, and a word that is not a collection stays as it is.
  static String singular(String segment) {
    // A word ending in `-ss` (`access`) or `-us` (`status`) is not a plural.
    if (segment.endsWith('ss') || segment.endsWith('us')) return segment;
    if (segment.endsWith('ies')) return '${segment.substring(0, segment.length - 3)}y';
    if (segment.endsWith('sses') || segment.endsWith('xes')) return segment.substring(0, segment.length - 2);
    if (segment.endsWith('s')) return segment.substring(0, segment.length - 1);
    return segment;
  }

  /// A link's path with only its first segment kept, when it is a plain word; every later segment is
  /// `{id}`, so a token, an id or a name in the path, such as in a reset link, is never sent.
  /// `/guides/getting-started` is `/guides/{id}`, and empty segments stay as they are.
  static String linkPath(String path) {
    final segments = path.split('/');
    return [
      for (var index = 0; index < segments.length; index++)
        segments[index].isEmpty || (index == 1 && _plainSegment.hasMatch(segments[index])) ? segments[index] : '{id}',
    ].join('/');
  }

  /// Whether an application's own event name is lower-case `<type>.<action>` words.
  static bool isValidName(String name) => _eventName.hasMatch(name);

  /// An application's event data without any value that could be personal: one longer than 64
  /// characters, or containing `@`, `://`, `?`, `#` or whitespace.
  static Map<String, String> safeData(Map<String, String> data) => {
        for (final entry in data.entries)
          if (entry.value.length <= 64 && !_personalValue.hasMatch(entry.value)) entry.key: entry.value,
      };

  /// Whether a path segment names a collection: a plural word.
  static bool isCollection(String segment) => singular(segment) != segment;

  /// Whether a route segment is a parameter, such as `:id` or `{id}`.
  static bool isParameter(String segment) =>
      segment.startsWith(':') || (segment.startsWith('{') && segment.endsWith('}')) || segment == '*';

  /// The name of a screen from its route pattern, before the prefix: `/applications` is
  /// `application.list-view`, `/applications/:id` is `application.detail-view`,
  /// `/applications/create` is `application.create-view`, and `/` is `app.home-view`.
  static String pageName(String pattern) {
    final segments = pattern.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) return 'app.home-view';
    String owner(int before) {
      for (var index = before; index >= 0; index--) {
        if (!isParameter(segments[index])) return singular(segments[index]);
      }
      return 'app';
    }

    final last = segments.last;
    if (isParameter(last)) return '${owner(segments.length - 2)}.detail-view';
    if (isCollection(last)) return '${singular(last)}.list-view';
    return '${owner(segments.length - 2)}.$last-view';
  }
}

/// A call that is reported: its name before the prefix, its path template and its codes.
class TelemetryApiCall {
  final String name;
  final String route;
  final Map<String, String> data;

  const TelemetryApiCall({required this.name, required this.route, this.data = const {}});
}

/// A plain word in a path: letters and hyphens. Anything else, such as a UUID or a name, is a value.
final RegExp _word = RegExp(r'^[A-Za-z][A-Za-z-]{0,39}$');

/// A path segment kept in a template: a word that may hold a version digit, such as `v2` or `oauth2`.
final RegExp _templateWord = RegExp(r'^\.?[A-Za-z][A-Za-z0-9-]{0,39}$');

/// An API version in a path, such as `v2`.
final RegExp _version = RegExp(r'^v\d{1,2}$');

/// The words of the naming scheme itself. A hyphenated segment that starts with one, such as
/// `update-credentials`, is an action and not a collection, even though it ends in `s`.
const Set<String> _changeWords = {'add', 'create', 'delete', 'remove', 'update'};

/// Sub-collections reported as an action on their parent, by change (`create`, `update` or
/// `delete`): `{'sharing-policies': {'create': 'share'}}` reports
/// `POST /applications/{id}/sharing-policies` as `application.share`.
typedef TelemetryParentActions = Map<String, Map<String, String>>;

/// Names an API call from its method and path alone, the same way for any REST API, with no
/// knowledge of a particular API:
///
/// - `POST /<collection>` is `<type>.create`; `PUT` or `PATCH /<collection>/{id}` is
///   `<type>.update`; `DELETE /<collection>/{id}` is `<type>.delete`. Words in front of the first
///   collection, such as `design` in `/design/themes`, are skipped.
/// - A word between a top-level collection listed in `kinds` and its item, as in
///   `/connections/google/{id}`, is reported as `kind`. Under any other collection it is an item
///   value: `POST /users/alice` is `user.create` with route `/users/{id}`.
/// - A word listed in `addressWords` right after a collection starts an address: everything after
///   it is `{path}`, as in `/organization-units/tree/{path}`, and never part of a name.
/// - A sub-resource is named for itself and carries `parent_type`:
///   `POST /resource-servers/{id}/actions` is `action.create`, unless `parentActions` reports it as
///   an action on the parent.
/// - A change word, or a word listed in `actions`, ending a POST to a sub-collection is an action
///   on the parent: `POST /groups/{id}/members/add` is `group.member-add`, with `sub_type: member`.
///   Words after an id are an action on the item:
///   `POST /applications/{id}/client-secret/regenerate` is `application.client-secret-regenerate`.
/// - Words after an item that is itself a word are part of its address and never part of a name.
/// - A path of words alone is named from them: `POST /import` is `api.import`.
/// - Any other change is `api.call`, with its method and a route that keeps only its first
///   segment, so nothing is lost.
///
/// Only `POST`, `PUT`, `PATCH` and `DELETE` are named. Which calls to skip, and any name an API
/// needs beyond these rules, come from configuration.
class TelemetryApiRules {
  final List<Uri> _bases;
  final TelemetryParentActions _parentActions;
  final Set<String> _kinds;
  final Set<String> _addressWords;
  final Set<String> _actions;

  /// [kinds] are the top-level collections whose next word is a kind, such as `connections` in
  /// `/connections/google`. [addressWords] are words after a collection that start an address,
  /// such as `tree` in `/organization-units/tree/a/b`. [actions] are words that end a POST to a
  /// sub-collection as an action on the parent, besides the change words, such as `suspend`.
  TelemetryApiRules(
    List<String> bases, {
    TelemetryParentActions parentActions = const {},
    List<String> kinds = const [],
    List<String> addressWords = const [],
    List<String> actions = const [],
  })  : _bases = bases.map(Uri.tryParse).whereType<Uri>().where((uri) => uri.hasScheme).toList(),
        _parentActions = parentActions,
        _kinds = {for (final word in kinds) word.toLowerCase()},
        _addressWords = {for (final word in addressWords) word.toLowerCase()},
        _actions = {for (final word in actions) word.toLowerCase()};

  /// Whether [code] is a well-formed error code, such as `APP-1023`.
  static bool isErrorCode(String code) => _errorCode.hasMatch(code);

  /// Whether a request body sets [field] to a value other than `false`, `null` or an empty string.
  /// Only read here, never sent.
  static bool sets(String? body, String field) {
    final value = _parse(body)?[field];
    return value != null && value != false && value != '';
  }

  /// What a failed call is reported with: the HTTP status and the API's own error code, when it
  /// gave one. Never the message, which can quote what the user typed.
  static Map<String, String> failureData(int? status, String? responseBody) {
    final data = <String, String>{'status': status == null || status == 0 ? 'network' : '$status'};
    final code = _parse(responseBody)?['code'];
    if (code is String && _errorCode.hasMatch(code)) data['error_code'] = code;
    return data;
  }

  /// The path template of a call no rule names, or `null` when the URL is not under a watched base.
  /// Only the first segment is kept, when it is a word; every later segment, which can be an id, a
  /// handle or a name someone chose, is `{id}`.
  String? route(Uri url) {
    final path = _pathBelowBase(url);
    if (path == null) return null;
    return _join([
      for (var index = 0; index < path.length; index++)
        index == 0 && _templateWord.hasMatch(path[index]) ? path[index].toLowerCase() : '{id}',
    ]);
  }

  /// The path of a URL below a watched base as it was called, in lower case, with no value
  /// replaced, or `null` when the URL is not under one. Used only to match `exclude`; never sent.
  String? literalPath(Uri url) {
    final path = _pathBelowBase(url);
    return path == null ? null : _join([for (final segment in path) segment.toLowerCase()]);
  }

  /// The path of a URL below a watched base, in lower case, with only what cannot be a word
  /// replaced by `{id}`, or `null` when the URL is not under one. Used only to match configured
  /// patterns; never sent.
  String? path(Uri url) {
    final path = _pathBelowBase(url);
    return path == null ? null : _shape(path);
  }

  static String _shape(List<String> path) =>
      _join([for (final segment in path) _templateWord.hasMatch(segment) ? segment.toLowerCase() : '{id}']);

  /// Names a call, or returns `null` when it is not reported.
  TelemetryApiCall? classify(String method, Uri url) {
    final verb = method.toUpperCase();
    if (_change(verb) == null) return null;
    final path = _pathBelowBase(url);
    if (path == null || path.isEmpty) return null;
    return _name(verb, path) ?? TelemetryApiCall(name: 'api.call', route: route(url)!, data: {'method': verb});
  }

  /// Names a change from its method and path segments, or returns `null` when no rule fits.
  TelemetryApiCall? _name(String verb, List<String> path) {
    final change = _change(verb)!;
    final route = <String>[];
    var index = 0;

    // Words in front of the first collection, such as `design` in `/design/themes`.
    while (index < path.length && !_isCollection(path[index])) {
      if (!_templateWord.hasMatch(path[index])) break;
      route.add(path[index].toLowerCase());
      index++;
    }
    if (index == path.length || !_isCollection(path[index])) {
      // No collection: `PUT /server-config/{name}` is a change to `server-config`.
      if (path.length == 2 && change != 'create' && _word.hasMatch(path[0])) {
        final type = path[0].toLowerCase();
        return TelemetryApiCall(name: '$type.$change', route: '/$type/{id}', data: {'resource_type': type});
      }
      // No resource type, only words: `POST /import` is `api.import`, `POST /import/managed` is
      // `api.import-managed`, and `PUT /maintenance` is `api.maintenance-update`. Only letter words
      // and versions such as `v2` make a name, so an id with digits, such as a client id, never does.
      if (index == path.length &&
          path.every((segment) => _word.hasMatch(segment) || _version.hasMatch(segment.toLowerCase()))) {
        return TelemetryApiCall(
          name: 'api.${route.join('-')}${verb == 'POST' ? '' : '-$change'}',
          route: _join(route),
        );
      }
      return null;
    }

    String? parent;
    for (;;) {
      final collection = path[index].toLowerCase();
      final type = TelemetryNames.singular(collection);
      route.add(collection);
      index++;
      final data = <String, String>{if (parent != null) 'parent_type': parent};

      // The collection itself: `POST /groups`, or `PUT /flows/{id}/variables` for all of them.
      if (index == path.length) return _changeOf(change, type, collection, parent, data, route);

      // A configured address word, such as `tree` in `/organization-units/tree/a/b`: everything after
      // it addresses the item and never reaches a name, a type or the data.
      if (_addressWords.contains(path[index].toLowerCase())) {
        route.addAll([path[index].toLowerCase(), '{path}']);
        return _changeOf(change, type, collection, parent, data, route);
      }

      // A change word or a configured action that ends a POST to a sub-collection is an action on the
      // parent: `POST /groups/{id}/members/add` is `group.member-add`. Any other word there is an id
      // the caller chose: `POST /groups/{id}/members/alice` is `member.create`.
      if (parent != null &&
          verb == 'POST' &&
          index == path.length - 1 &&
          _word.hasMatch(path[index]) &&
          (_isChangeWord(path[index]) || _actions.contains(path[index].toLowerCase()))) {
        final action = path[index].toLowerCase();
        route.add(action);
        return TelemetryApiCall(
          name: '$parent.$type-$action',
          route: _join(route),
          data: {'resource_type': parent, 'sub_type': type},
        );
      }

      // A kind between a configured top-level collection and the item: `/connections/google/{id}`,
      // or `POST /connections/google` for a new one of that kind. Under any other collection the
      // word is an item value.
      final segment = path[index];
      final isKind = parent == null && _kinds.contains(collection) && _word.hasMatch(segment);
      final itemData = isKind ? {...data, 'kind': segment.toLowerCase()} : data;

      // A label and its value in front of a sub-collection, under another sub-collection, such as
      // `ns/{namespace}` in `/languages/{id}/translations/ns/{namespace}/keys`: the label is kept and
      // the value is not.
      if (parent != null &&
          !isKind &&
          _word.hasMatch(segment) &&
          !_isChangeWord(segment) &&
          index + 2 < path.length &&
          _isCollection(path[index + 2])) {
        route.addAll([segment.toLowerCase(), '{id}']);
        index += 2;
        parent = type;
        continue;
      }

      if (isKind) {
        route.add(segment.toLowerCase());
        index++;
        if (index == path.length) return _changeOf(change, type, collection, parent, itemData, route);
      }

      // The item: an id, or a word that a collection or an action follows, such as `me` or `en`.
      final itemIsWord = _word.hasMatch(path[index]);
      route.add('{id}');
      index++;
      if (index == path.length) {
        // `POST /<collection>/{id}` creates one at an id the caller chose.
        return _changeOf(change, type, collection, parent, itemData, route);
      }

      final rest = [for (final part in path.sublist(index)) part.toLowerCase()];

      // A sub-resource of the item.
      if (_isCollection(path[index])) {
        parent = type;
        continue;
      }

      // Words after an item that is itself a word, as in `/organization-units/tree/eng/backend`, can
      // be values someone chose, such as handles in a path, so they are part of the item's address
      // and never part of a name. One segment that starts with a change word, such as
      // `/users/me/update-credentials`, is still an action.
      if (itemIsWord && !(rest.length == 1 && _isChangeWord(rest[0]))) {
        route.add('{path}');
        return _changeOf(change, type, collection, parent, itemData, route);
      }

      // An action on the item: `client-secret/regenerate`, `restore`, `update-credentials`, or a
      // setting such as `PUT /projects/{id}/auto-sync`.
      if (!rest.every(_word.hasMatch)) return null;
      route.addAll(rest);
      return TelemetryApiCall(
        name: '$type.${rest.join('-')}${verb == 'POST' ? '' : '-$change'}',
        route: _join(route),
        data: {...itemData, 'resource_type': type},
      );
    }
  }

  /// A create, update or delete of a collection's resource, or the parent's action for a
  /// sub-resource that [_parentActions] names, such as a sharing policy.
  TelemetryApiCall _changeOf(
    String change,
    String type,
    String collection,
    String? parent,
    Map<String, String> data,
    List<String> route,
  ) {
    final joined = _join(route);
    final parentAction = parent == null ? null : _parentActions[collection]?[change];
    if (parent != null && parentAction != null) {
      final rest = {...data}..remove('parent_type');
      return TelemetryApiCall(name: '$parent.$parentAction', route: joined, data: {...rest, 'resource_type': parent});
    }
    return TelemetryApiCall(name: '$type.$change', route: joined, data: {...data, 'resource_type': type});
  }

  /// The change a method makes: `create`, `update` or `delete`, or `null` for a read.
  static String? _change(String verb) => switch (verb) {
        'POST' => 'create',
        'PUT' || 'PATCH' => 'update',
        'DELETE' => 'delete',
        _ => null,
      };

  static String _join(List<String> route) => '/${route.join('/')}';

  /// Whether a segment starts with a word of the naming scheme, such as `update-credentials`.
  static bool _isChangeWord(String segment) =>
      _word.hasMatch(segment) && _changeWords.contains(segment.toLowerCase().split('-').first);

  /// Whether a segment names a collection, such as `applications`, and is not an action.
  static bool _isCollection(String segment) =>
      segment.length > 2 &&
      _word.hasMatch(segment) &&
      !_isChangeWord(segment) &&
      TelemetryNames.isCollection(segment.toLowerCase());

  /// The path segments of a URL below the longest watched base it falls under, or `null`.
  List<String>? _pathBelowBase(Uri url) {
    String? longest;
    for (final base in _bases) {
      final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
      final sameOrigin = url.scheme == base.scheme && url.host == base.host && url.port == base.port;
      if (sameOrigin &&
          (prefix.isEmpty || url.path == prefix || url.path.startsWith('$prefix/')) &&
          (longest == null || prefix.length > longest.length)) {
        longest = prefix;
      }
    }
    if (longest == null) return null;
    return url.path.substring(longest.length).split('/').where((segment) => segment.isNotEmpty).toList();
  }

  static Map<String, Object?>? _parse(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
