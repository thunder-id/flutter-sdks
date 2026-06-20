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

/// ThunderID Flutter SDK.
///
/// Provides identity management (sign-in, sign-up, token management, user profile)
/// for Flutter apps by bridging to the native iOS and Android
/// ThunderID Platform SDKs via Flutter platform channels.
library thunderid_flutter;

export 'src/thunderid_client.dart';
export 'src/models/thunderid_config.dart';
export 'src/models/user.dart';
export 'src/models/user_profile.dart' hide UserProfile;
export 'src/models/token_response.dart';
export 'src/models/thunderid_error.dart';
export 'src/models/flow_models.dart';
export 'src/models/sign_in_options.dart';
export 'src/models/sign_out_options.dart';
export 'src/models/sign_up_options.dart';
export 'src/models/token_exchange_config.dart';
export 'src/models/preferences.dart';
export 'src/widgets/thunderid_provider.dart';
export 'src/widgets/thunderid_sign_in_button.dart';
export 'src/widgets/thunderid_sign_out_button.dart';
export 'src/widgets/thunderid_sign_up_button.dart';
export 'src/widgets/thunderid_callback.dart';
export 'src/widgets/thunderid_signed_in.dart';
export 'src/widgets/thunderid_signed_out.dart';
export 'src/widgets/thunderid_loading.dart';
export 'src/widgets/thunderid_sign_in.dart';
export 'src/widgets/thunderid_sign_up.dart';
export 'src/widgets/thunderid_user.dart';
export 'src/widgets/thunderid_user_dropdown.dart';
export 'src/widgets/thunderid_user_profile.dart';
export 'src/widgets/thunderid_language_switcher.dart';
export 'src/flow_template_resolver.dart';
