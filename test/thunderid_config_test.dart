// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

void main() {
  group('ThunderIDConfig.toMap', () {
    test('passes the discovery document URL to the native SDK', () {
      const wellKnown =
          'https://idp.example.com/t/acme/oauth2/token/.well-known/openid-configuration';
      const config = ThunderIDConfig(
        baseUrl: 'https://idp.example.com/t/acme',
        clientId: 'client',
        endpoints: EndpointsConfig(wellKnown: wellKnown),
      );

      expect(config.toMap()['wellKnown'], wellKnown);
    });

    test('leaves the discovery document URL out when it is not set', () {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        endpoints: EndpointsConfig(users: 'https://localhost:8090/users'),
      );

      expect(config.toMap().containsKey('wellKnown'), isFalse);
      expect(config.toMap().containsKey('users'), isFalse);
    });
  });
}
