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

class User {
  final String sub;
  final String? username;
  final String? email;
  final String? displayName;
  final String? profilePicture;
  final bool? isNewUser;
  final Map<String, dynamic>? claims;

  const User({
    required this.sub,
    this.username,
    this.email,
    this.displayName,
    this.profilePicture,
    this.isNewUser,
    this.claims,
  });

  Map<String, dynamic> toMap() => {
        'sub': sub,
        if (username != null) 'username': username,
        if (email != null) 'email': email,
        if (displayName != null) 'displayName': displayName,
        if (profilePicture != null) 'profilePicture': profilePicture,
        if (isNewUser != null) 'isNewUser': isNewUser,
        if (claims != null) 'claims': claims,
      };

  factory User.fromMap(Map<dynamic, dynamic> map) => User(
        sub: map['sub'] as String,
        username: map['username'] as String?,
        email: map['email'] as String?,
        displayName: map['displayName'] as String?,
        profilePicture: map['profilePicture'] as String?,
        isNewUser: map['isNewUser'] as bool?,
        claims: (map['claims'] as Map?)?.cast<String, dynamic>(),
      );
}
