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

/// Default English strings for all ThunderID UI component labels.
const Map<String, String> thunderDefaultStrings = {
  // Actions
  'signIn.button': 'Sign In',
  'signOut.button': 'Sign Out',
  'signUp.button': 'Sign Up',

  // Sign-in form
  'signIn.title': 'Sign In',
  'signIn.username': 'Email or username',
  'signIn.password': 'Password',
  'signIn.submit': 'Continue',
  'signIn.loading': 'Signing in\u2026',
  'signIn.error.generic': 'Sign-in failed. Please try again.',

  // Sign-up form
  'signUp.title': 'Create Account',
  'signUp.submit': 'Create Account',
  'signUp.loading': 'Creating account\u2026',
  'signUp.error.generic': 'Registration failed. Please try again.',

  // Accept invite
  'acceptInvite.title': 'Accept Invitation',
  'acceptInvite.submit': 'Accept',

  // Invite user
  'inviteUser.title': 'Invite User',
  'inviteUser.email': 'Email address',
  'inviteUser.submit': 'Send Invitation',

  // User
  'user.anonymous': 'User',

  // User profile
  'userProfile.title': 'Profile',
  'userProfile.save': 'Save Changes',
  'userProfile.changePassword': 'Change Password',
  'userProfile.loading': 'Loading profile\u2026',
  'userProfile.error.load': 'Failed to load profile.',
  'userProfile.error.save': 'Failed to save changes.',

  // Organizations
  'organization.unnamed': 'Organization',
  'organizationList.empty': 'No organizations found.',
  'organizationSwitcher.label': 'Switch Organization',
  'organizationSwitcher.current': 'Current',
  'createOrganization.title': 'Create Organization',
  'createOrganization.name': 'Organization name',
  'createOrganization.submit': 'Create',

  // Language switcher
  'languageSwitcher.label': 'Language',

  // Callback
  'callback.loading': 'Completing sign-in\u2026',
  'callback.error': 'Sign-in could not be completed.',
};
