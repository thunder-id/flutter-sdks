// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// ThunderID Flutter SDK.
///
/// Provides identity management (sign-in, sign-up, token management, user profile)
/// for Flutter apps by bridging to the native iOS and Android
/// ThunderID Platform SDKs via Flutter platform channels.
library thunderid_flutter;

export 'src/flow_template_resolver.dart';
export 'src/logo/avatar_logo.dart';
export 'src/logo/curated_logo_icons.dart';
export 'src/logo/logo_spec.dart';
export 'src/logo/thunderid_logo.dart';
export 'src/management_clients.dart';
export 'src/models/flow_models.dart';
export 'src/models/management_models.dart';
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
export 'src/thunderid_client.dart';
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
