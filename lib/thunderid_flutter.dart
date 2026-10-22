// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// ThunderID Flutter SDK.
///
/// Provides identity management (sign-in, sign-up, token management, user profile, and
/// administration of users, groups, roles, and agents)
/// for Flutter apps by bridging to the native iOS and Android
/// ThunderID Platform SDKs via Flutter platform channels.
library thunderid_flutter;

export 'src/flow_template_resolver.dart';
export 'src/logo/avatar_logo.dart';
export 'src/logo/curated_logo_icons.dart';
export 'src/logo/logo_spec.dart';
export 'src/logo/thunderid_logo.dart';
export 'src/management/management_display.dart';
export 'src/management/management_filter.dart';
export 'src/management/management_transport.dart';
export 'src/management/permissions.dart';
export 'src/management/thunderid_management_client.dart';
export 'src/models/flow_models.dart' hide KeyValuePair;
export 'src/models/management/agent.dart';
export 'src/models/management/group.dart';
export 'src/models/management/managed_user.dart';
export 'src/models/management/management_page.dart';
export 'src/models/management/role.dart';
export 'src/models/preferences.dart';
export 'src/models/sign_in_options.dart';
export 'src/models/sign_out_options.dart';
export 'src/models/sign_up_options.dart';
export 'src/models/thunderid_config.dart';
export 'src/models/thunderid_error.dart';
export 'src/models/token_exchange_config.dart';
export 'src/models/token_response.dart';
export 'src/models/user.dart';
export 'src/models/user_profile.dart' hide UserProfile;
export 'src/state/granted_permissions.dart';
export 'src/state/management_resources.dart';
export 'src/state/resource_notifiers.dart';
export 'src/thunderid_client.dart';
export 'src/widgets/admin/admin_render_state.dart';
export 'src/widgets/admin/agent_create.dart';
export 'src/widgets/admin/agent_details.dart';
export 'src/widgets/admin/agent_list.dart';
export 'src/widgets/admin/group_create.dart';
export 'src/widgets/admin/group_list.dart';
export 'src/widgets/admin/group_members.dart';
export 'src/widgets/admin/identity_candidate.dart';
export 'src/widgets/admin/role_assignments.dart';
export 'src/widgets/admin/role_create.dart';
export 'src/widgets/admin/role_list.dart';
export 'src/widgets/admin/role_permissions.dart';
export 'src/widgets/admin/user_create.dart';
export 'src/widgets/admin/user_details.dart';
export 'src/widgets/admin/user_list.dart';
export 'src/widgets/callback.dart';
export 'src/widgets/change_credential.dart';
export 'src/widgets/language_switcher.dart';
export 'src/widgets/loading.dart';
export 'src/widgets/sign_in.dart';
export 'src/widgets/sign_in_button.dart';
export 'src/widgets/sign_out_button.dart';
export 'src/widgets/sign_up.dart';
export 'src/widgets/sign_up_button.dart';
export 'src/widgets/signed_in.dart';
export 'src/widgets/signed_out.dart';
export 'src/widgets/thunderid_provider.dart';
export 'src/widgets/user_avatar.dart';
export 'src/widgets/user_dropdown.dart';
export 'src/widgets/user_object.dart';
export 'src/widgets/user_profile.dart';
