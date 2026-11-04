// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:math';

// Package-internal helpers for the secret regeneration operations.

/// The OAuth grant types that let an agent act on behalf of a signed-in user: authorization code,
/// CIBA and token exchange. An agent holding any of them is delegated, the rule the server
/// applies when it checks an agent's grants.
const List<String> delegationGrantTypes = [
  'authorization_code',
  'urn:openid:params:grant-type:ciba',
  'urn:ietf:params:oauth:grant-type:token-exchange',
];

/// Generates a random secret: 32 bytes from the platform's cryptographically secure generator,
/// encoded as base64url without padding.
String generateSecret([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Whether an agent acts on behalf of a signed-in user, read from the grant types of its OAuth
/// client. The server does not store the flag, so a full agent update has to send it for the
/// agent to stay held to the delegated grant rules.
bool isDelegatedAgent(List<Object?> inboundAuthConfig) {
  for (final inbound in inboundAuthConfig) {
    if (inbound is! Map || inbound['type'] != 'oauth2') continue;
    final config = inbound['config'];
    final grantTypes = config is Map ? config['grantTypes'] : null;
    return grantTypes is List && grantTypes.any(delegationGrantTypes.contains);
  }
  return false;
}
