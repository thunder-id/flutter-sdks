// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// How events are encoded for the endpoint.
enum TelemetryFormat {
  /// OpenTelemetry log records (OTLP/HTTP JSON), for an OpenTelemetry Collector.
  otlp,

  /// The events as they are, in an array.
  json,

  /// Each event reshaped by [TelemetryConfig.mapping], for any other API.
  mapping,
}

/// How a mapped batch is sent.
enum TelemetryBatch {
  /// Every event of the batch in one array.
  array,

  /// One request per event.
  each,
}

/// The settings every automatic kind shares.
class TelemetryKindConfig {
  /// Whether this kind is reported.
  final bool enabled;

  /// What is never reported: route patterns for pages; for API events, URLs, paths below the API
  /// as called or with values masked (`/oauth2/**`), and event names, so an excluded name also stops
  /// its `-failed` form; URLs for links. For these `*` matches the rest of one path segment and `**`
  /// the rest of the value. For auth events, exact action names without the prefix, such as
  /// `session-expired`.
  final List<String> exclude;

  /// Renames, from a route pattern, a URL or an automatic name to the name to report instead.
  final Map<String, String> names;

  const TelemetryKindConfig({this.enabled = true, this.exclude = const [], this.names = const {}});
}

/// API events: what the app's calls through the SDK change.
///
/// Its [names] rename API events. A key is either an automatic name, such as `group.create` or
/// `api.call`, or a method and a path, such as `POST /import`, where `*` matches one segment and
/// `**` the rest, which names any call that matches, including one the built-in rules do not name.
/// A path key may end with `?<field>` to match only when the request body sets that field, such as
/// `POST /promotions ?origin`. The body is read for that alone and never sent. A path key comes
/// first, then a rename of the built-in rules' name, then a name the API gives in its
/// `X-Telemetry-Event` response header (itself renamed when a key names it), then the rules' name.
/// Configuration always comes before the header.
class TelemetryApiEventsConfig extends TelemetryKindConfig {
  /// More APIs to watch with the same rules as the SDK's own API: base URLs whose creates, updates
  /// and deletes are reported.
  final List<String> apis;

  /// Sub-collections reported as an action on their parent, by change (`create`, `update` or
  /// `delete`): `{'sharing-policies': {'create': 'share', 'update': 'share-update', 'delete':
  /// 'unshare'}}` reports `POST /applications/{id}/sharing-policies` as `application.share`.
  final Map<String, Map<String, String>> parentActions;

  /// Request body fields that mean a call changes nothing, such as `dryRun` or `preview`: a call
  /// whose body sets one is not reported.
  final List<String> skipWhen;

  /// Top-level collections whose next path word is a kind, such as `['connections']`:
  /// `POST /connections/google` is then `connection.create` with `kind: google` and route
  /// `/connections/google`. Under any other collection that word is an item value: `{id}` in the
  /// route, and never in a name or the data.
  final List<String> kinds;

  /// Words that, right after a collection, start an address, such as `['tree']`:
  /// `PUT /organization-units/tree/engineering/operations` is then `organization-unit.update` with
  /// route `/organization-units/tree/{path}`. No word of the address reaches a name, a type or the
  /// data.
  final List<String> addressWords;

  /// Words that end a POST to a sub-collection as an action on the parent, besides `add`, `create`,
  /// `delete`, `remove` and `update`, such as `['suspend']`: `POST /users/me/agents/suspend` is then
  /// `user.agent-suspend`. Any other word there is an id the caller chose:
  /// `POST /groups/{id}/members/alice` is `member.create`.
  final List<String> actions;

  const TelemetryApiEventsConfig({
    super.enabled,
    super.exclude,
    super.names,
    this.apis = const [],
    this.parentActions = const {},
    this.skipWhen = const [],
    this.kinds = const [],
    this.addressWords = const [],
    this.actions = const [],
  });
}

/// A template that reshapes each event for an API that does not take OpenTelemetry.
class TelemetryMapping {
  /// The shape of one event. Strings may hold `{{path}}` expressions read from the event, with
  /// filters (`{{attributes.user.id | uuid}}`). A key starting with `...` spreads an object value
  /// into its parent. An expression that reads nothing leaves its key out.
  final Map<String, Object?> template;

  /// Lookup tables, for the `lookup` filter: `{{name | lookup: features}}` reads
  /// `tables['features'][name]`.
  final Map<String, Map<String, Object?>> tables;

  /// How a batch is sent.
  final TelemetryBatch batch;

  const TelemetryMapping({required this.template, this.tables = const {}, this.batch = TelemetryBatch.array});
}

/// The token the telemetry endpoint gets.
sealed class TelemetryToken {
  const TelemetryToken();

  /// The app's own access token, only for an endpoint on the origin of `baseUrl`; none elsewhere.
  static const TelemetryToken appToken = _AppToken();

  /// No token.
  static const TelemetryToken none = _NoToken();

  /// This token only; the app's own token is never sent.
  const factory TelemetryToken.value(String token) = TelemetryTokenValue;
}

class _AppToken extends TelemetryToken {
  const _AppToken();
}

class _NoToken extends TelemetryToken {
  const _NoToken();
}

/// A fixed token for the telemetry endpoint.
class TelemetryTokenValue extends TelemetryToken {
  final String token;

  const TelemetryTokenValue(this.token);
}

/// Telemetry: what people do in the app, reported to an endpoint the deployment configures. Off
/// until [endpoint] is set. Only codes are sent: route patterns, path templates, ids and error
/// codes; never a URL with its query, a name or anything a user typed.
class TelemetryConfig {
  /// Where events are sent: an `https` URL. Unset or empty: telemetry is off.
  final String? endpoint;

  /// The encoding.
  final TelemetryFormat format;

  /// The mapping, for [TelemetryFormat.mapping].
  final TelemetryMapping? mapping;

  /// A product prefix added to every name, such as `acme` for `acme.application.create`.
  final String? prefix;

  /// Codes added to every event, such as the product, the plan tier or the region.
  final Map<String, String> context;

  /// When set, nothing is sent until it returns true. Events wait in memory until then.
  final bool Function()? consent;

  /// The ID token claim holding the user's id.
  final String userClaim;

  /// The ID token claim holding the organization's id.
  final String organizationClaim;

  /// The token the endpoint gets.
  final TelemetryToken token;

  /// Screen views, named from the route.
  final TelemetryKindConfig pages;

  /// Creates, updates, deletes and other changes, and their failures.
  final TelemetryApiEventsConfig apiEvents;

  /// `auth.sign-in`, `auth.sign-in-failed`, `auth.sign-out` and `auth.session-expired`.
  final TelemetryKindConfig authEvents;

  /// Links that leave the app, opened through the SDK, reported as `link.open`.
  final TelemetryKindConfig links;

  const TelemetryConfig({
    this.endpoint,
    this.format = TelemetryFormat.otlp,
    this.mapping,
    this.prefix,
    this.context = const {},
    this.consent,
    this.userClaim = 'sub',
    this.organizationClaim = 'ouId',
    this.token = TelemetryToken.appToken,
    this.pages = const TelemetryKindConfig(),
    this.apiEvents = const TelemetryApiEventsConfig(),
    this.authEvents = const TelemetryKindConfig(),
    this.links = const TelemetryKindConfig(),
  });

  /// Whether this configuration turns telemetry on.
  bool get isEnabled => endpoint != null && endpoint!.trim().isNotEmpty;
}

/// The operating system an event comes from.
typedef TelemetryOs = ({String name, String version});

/// The kinds of event the SDK reports.
enum TelemetryEventKind { page, api, auth, link, custom }

/// One reported event, before it is encoded.
class TelemetryEvent {
  final String id;
  final String name;
  final TelemetryEventKind kind;

  /// When it happened, as an ISO 8601 string.
  final String timestamp;

  /// Codes about the event: a resource type, an HTTP status, an error code, a link's host.
  final Map<String, String> data;

  /// The route pattern of a screen, or the path template of an API call.
  final String? route;
  final String? userId;
  final String? organizationId;

  /// The operating system and its version.
  final TelemetryOs? os;
  final Map<String, String> context;

  const TelemetryEvent({
    required this.id,
    required this.name,
    required this.kind,
    required this.timestamp,
    this.data = const {},
    this.route,
    this.userId,
    this.organizationId,
    this.os,
    this.context = const {},
  });

  /// The event as the JSON format and the mapping read it.
  Map<String, Object?> toJson() => {
        'attributes': {
          'data': data,
          if (organizationId != null) 'organization': {'id': organizationId},
          if (route != null) 'route': route,
          if (userId != null) 'user': {'id': userId},
          if (os != null) 'os': {'name': os!.name, 'version': os!.version},
        },
        'context': context,
        'id': id,
        'kind': kind.name,
        'name': name,
        'timestamp': timestamp,
      };
}
