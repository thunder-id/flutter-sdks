/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

class TokenResponse {
  final String accessToken;
  final String tokenType;
  final int? expiresIn;
  final String? refreshToken;
  final String? idToken;
  final String? scope;

  const TokenResponse({
    required this.accessToken,
    required this.tokenType,
    this.expiresIn,
    this.refreshToken,
    this.idToken,
    this.scope,
  });

  factory TokenResponse.fromMap(Map<dynamic, dynamic> map) => TokenResponse(
        accessToken: map['accessToken'] as String,
        tokenType: map['tokenType'] as String,
        expiresIn: map['expiresIn'] as int?,
        refreshToken: map['refreshToken'] as String?,
        idToken: map['idToken'] as String?,
        scope: map['scope'] as String?,
      );
}
