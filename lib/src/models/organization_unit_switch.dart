// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'flow_models.dart';
import 'user.dart';

/// Options for [ThunderIDClient.switchOrganizationUnit].
class SwitchOrganizationUnitOptions {
  /// Whether the switch may open a system browser session (`ASWebAuthenticationSession` on iOS, a
  /// Custom Tab on Android) for a redirect sign-in bounded to the unit. The server reuses its SSO
  /// session, so normally no credentials are asked.
  ///
  /// When sign-in runs on a backend, the browser opens only when the backend needs the user, and
  /// `false` makes that case fail with [ThunderIDErrorCode.authenticationFailed] instead.
  ///
  /// Otherwise, `true` switches by a redirect sign-in when no device secret can switch silently, and
  /// `false` runs the application's `AUTHENTICATION` flow in app-native mode, which can return
  /// [OrganizationUnitSwitchSignInRequired]. Defaults to `true` unless an [applicationId] is given
  /// here or in [ThunderIDConfig.applicationId].
  final bool? useBrowser;

  /// App-native mode: the application whose `AUTHENTICATION` flow is started. Defaults to
  /// [ThunderIDConfig.applicationId].
  final String? applicationId;

  const SwitchOrganizationUnitOptions({this.useBrowser, this.applicationId});
}

/// What [ThunderIDClient.switchOrganizationUnit] ended with.
sealed class OrganizationUnitSwitchResult {
  const OrganizationUnitSwitchResult();

  /// Reads the native SDK's answer, `{status: switched, user}` or `{status: signInRequired, response}`.
  factory OrganizationUnitSwitchResult.fromMap(Map<String, dynamic> map) {
    final Object? response = map['response'];
    if (map['status'] == 'signInRequired' && response is Map) {
      return OrganizationUnitSwitchSignInRequired(EmbeddedFlowResponse.fromMap(response.cast<String, dynamic>()));
    }
    final Object? user = map['user'];
    return OrganizationUnitSwitched(User.fromMap(user is Map ? user.cast<String, dynamic>() : const {}));
  }
}

/// The session now belongs to the unit, and [user] is the user read again.
class OrganizationUnitSwitched extends OrganizationUnitSwitchResult {
  final User user;

  const OrganizationUnitSwitched(this.user);
}

/// App-native mode: the sign-in bounded to the unit needs the user, such as for credentials the SSO
/// session could not supply. Drive [response] with [ThunderIDClient.signIn] like any embedded flow;
/// the session switches when the flow completes, and the previous one stays until then.
class OrganizationUnitSwitchSignInRequired extends OrganizationUnitSwitchResult {
  final EmbeddedFlowResponse response;

  const OrganizationUnitSwitchSignInRequired(this.response);
}
