// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

class SignInOptions {
  final String? prompt;
  final String? loginHint;
  final String? fidp;

  /// Bounds the sign-in to this organization unit: redirect mode authorizes at
  /// `{baseUrl}/ou/{organizationUnitId}/oauth2/authorize` and redeems the code at
  /// `{baseUrl}/ou/{organizationUnitId}/oauth2/token`, and sign-in on a backend passes it to the
  /// backend's sign-in endpoint as the `ouId` query parameter. Unset, sign-in is not bounded.
  final String? organizationUnitId;
  final Map<String, dynamic> extra;

  const SignInOptions({this.prompt, this.loginHint, this.fidp, this.organizationUnitId, this.extra = const {}});

  /// A copy with the given fields replaced.
  SignInOptions copyWith({String? prompt, String? loginHint, String? fidp, String? organizationUnitId}) =>
      SignInOptions(
        prompt: prompt ?? this.prompt,
        loginHint: loginHint ?? this.loginHint,
        fidp: fidp ?? this.fidp,
        organizationUnitId: organizationUnitId ?? this.organizationUnitId,
        extra: extra,
      );

  Map<String, dynamic> toMap() => {
        if (prompt != null) 'prompt': prompt,
        if (loginHint != null) 'loginHint': loginHint,
        if (fidp != null) 'fidp': fidp,
        ...extra,
        // After extra, so an extra parameter cannot unbind a unit-bounded sign-in.
        if (organizationUnitId != null) 'organizationUnitId': organizationUnitId,
      };
}
