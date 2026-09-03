// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

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
  'userProfile.edit': 'Edit',
  'userProfile.cancel': 'Cancel',
  'userProfile.changePassword': 'Change Password',
  'userProfile.loading': 'Loading profile\u2026',
  'userProfile.error.load': 'Failed to load profile.',
  'userProfile.error.save': 'Failed to save changes.',
  'userProfile.validation.required': 'This field is required.',
  'userProfile.validation.pattern': 'This value is not valid.',

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
