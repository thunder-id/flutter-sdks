// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// ThunderID Flutter SDK.
///
/// Provides identity management (sign-in, sign-up, token management, user profile, and
/// administration of users, user types, groups, roles, agents, agent types, applications,
/// organization units, resource servers, connections, flows, notification templates, design,
/// translations, server configuration, gateways, variables, secrets and configuration versions)
/// for Flutter apps by bridging to the native iOS and Android
/// ThunderID Platform SDKs via Flutter platform channels.
library thunderid_flutter;

export 'src/flow_template_resolver.dart';
export 'src/management/account_lifecycle.dart';
export 'src/management/administration_flows.dart';
export 'src/management/configuration.dart';
export 'src/management/connections.dart';
export 'src/management/design.dart';
export 'src/management/flows.dart';
export 'src/management/gateways.dart';
export 'src/management/management_display.dart';
export 'src/management/management_filter.dart';
export 'src/management/management_transport.dart';
export 'src/management/notification_templates.dart';
export 'src/management/organization_units.dart';
export 'src/management/permissions.dart';
export 'src/management/resource_servers.dart';
export 'src/management/server_config.dart';
export 'src/management/sharing.dart';
export 'src/management/thunderid_management_client.dart';
export 'src/management/translations.dart';
export 'src/management/variables.dart';
export 'src/models/attribute_verification.dart';
export 'src/models/backend.dart';
export 'src/models/flow_models.dart' hide KeyValuePair;
export 'src/models/http_request.dart';
export 'src/models/management/administration.dart';
export 'src/models/management/agent.dart';
export 'src/models/management/application.dart';
export 'src/models/management/configuration.dart';
export 'src/models/management/connection.dart';
export 'src/models/management/design.dart';
export 'src/models/management/entity_type.dart';
export 'src/models/management/flow_definition.dart';
export 'src/models/management/gateway.dart';
export 'src/models/management/group.dart';
export 'src/models/management/managed_user.dart';
export 'src/models/management/management_page.dart';
export 'src/models/management/notification_template.dart';
export 'src/models/management/organization_unit.dart';
export 'src/models/management/resource_server.dart';
export 'src/models/management/resource_usage.dart';
export 'src/models/management/role.dart';
export 'src/models/management/server_config.dart';
export 'src/models/management/sharing_policy.dart';
export 'src/models/management/translation.dart';
export 'src/models/management/variable.dart';
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
export 'src/widgets/account/change_credential.dart';
export 'src/widgets/account/user_avatar.dart';
export 'src/widgets/account/user_dropdown.dart';
export 'src/widgets/account/user_object.dart';
export 'src/widgets/account/user_profile.dart';
export 'src/widgets/account/user_profile_verification.dart';
export 'src/widgets/account/verify_attribute.dart' hide VerifiedProfileSink;
export 'src/widgets/admin/admin_render_state.dart';
export 'src/widgets/admin/agent_create.dart';
export 'src/widgets/admin/agent_details.dart';
export 'src/widgets/admin/agent_list.dart';
export 'src/widgets/admin/application_create.dart';
export 'src/widgets/admin/application_details.dart';
export 'src/widgets/admin/application_list.dart';
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
export 'src/widgets/auth/buttons/sign_in_button.dart';
export 'src/widgets/auth/buttons/sign_out_button.dart';
export 'src/widgets/auth/buttons/sign_up_button.dart';
export 'src/widgets/auth/callback.dart';
export 'src/widgets/auth/guards/loading.dart';
export 'src/widgets/auth/guards/signed_in.dart';
export 'src/widgets/auth/guards/signed_out.dart';
export 'src/widgets/auth/sign_in.dart';
export 'src/widgets/auth/sign_up.dart';
export 'src/widgets/common/language_switcher.dart';
export 'src/widgets/common/logo/avatar_logo.dart';
export 'src/widgets/common/logo/curated_logo_icons.dart';
export 'src/widgets/common/logo/logo_spec.dart';
export 'src/widgets/common/logo/thunderid_logo.dart';
export 'src/widgets/thunderid_provider.dart';
