// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/management/management_display.dart';
import '../../models/management/application.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_inputs.dart';
import 'internal/admin_parts.dart';
import 'internal/application_form.dart';
import 'internal/create_placement.dart';

/// What [BaseApplicationCreate] submits.
class ApplicationCreateSubmission {
  final String name;
  final String? description;
  final String? url;
  final String? logoUrl;

  /// One of `browser`, `mobile`, `fullstack`, `m2m`, `mcp`, `custom`.
  final String type;
  final List<String> grantTypes;
  final List<String> redirectUris;
  final bool publicClient;

  const ApplicationCreateSubmission({
    required this.name,
    required this.type,
    required this.grantTypes,
    required this.redirectUris,
    required this.publicClient,
    this.description,
    this.url,
    this.logoUrl,
  });

  /// The create request for an application in [ouId] (or, without one, in the root organization
  /// unit of [projectId]), with one OAuth client: the `code` response
  /// type for the authorization code grant, and PKCE with no client authentication for a public
  /// client.
  CreateApplicationRequest toRequest({String? ouId, String? projectId}) => CreateApplicationRequest(
        name: name,
        description: description,
        url: url,
        logoUrl: logoUrl,
        type: type,
        ouId: ouId,
        projectId: projectId,
        inboundAuthConfig: [
          InboundAuthConfig(
            config: OAuth2Config(
              grantTypes: grantTypes,
              responseTypes: grantTypes.contains(OAuth2GrantTypes.authorizationCode) ? const [OAuth2ResponseTypes.code] : const [],
              redirectUris: redirectUris,
              publicClient: publicClient,
              pkceRequired: publicClient ? true : null,
              tokenEndpointAuthMethod:
                  publicClient ? TokenEndpointAuthMethods.none : TokenEndpointAuthMethods.clientSecretBasic,
            ),
          ),
        ],
      );
}

/// The result [ApplicationCreate] reports: the created application and, when the server issued
/// one, its client secret. This is the only time the secret can be read.
class ApplicationCreateResult {
  final Application application;
  final String? clientSecret;

  const ApplicationCreateResult({required this.application, this.clientSecret});
}

/// Presentational application form: name, description, URL, logo, type, and the OAuth basics
/// (grant types, redirect URIs, public client). Hands the values to [onSubmit]; it makes no
/// request itself. Use [ApplicationCreate] to have it create the application.
///
/// While [clientSecret] is set, the secret is shown once, with copy and done actions, in place of
/// the form; done calls [onSecretDismissed].
class BaseApplicationCreate extends StatefulWidget {
  final ValueChanged<ApplicationCreateSubmission> onSubmit;
  final bool isSubmitting;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final VoidCallback? onCancel;
  final String? clientSecret;
  final VoidCallback? onSecretDismissed;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form, from the values and their setters, the submit action, the submission state and the client secret to show once.
  final AdminWidgetBuilder<ApplicationCreateFormState>? builder;

  const BaseApplicationCreate({
    super.key,
    required this.onSubmit,
    this.isSubmitting = false,
    this.error,
    this.onCancel,
    this.clientSecret,
    this.onSecretDismissed,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<BaseApplicationCreate> createState() => _BaseApplicationCreateState();
}

class _BaseApplicationCreateState extends State<BaseApplicationCreate> {
  String _name = '';
  String _description = '';
  String _url = '';
  String _logoUrl = '';
  String _type = applicationTypes.first;
  List<String> _grantTypes = const [OAuth2GrantTypes.authorizationCode, OAuth2GrantTypes.refreshToken];
  String _redirectUris = '';
  bool _publicClient = false;

  void _setGrantType(String grantType, bool selected) => setState(() {
        _grantTypes = [
          for (final grant in applicationGrantTypes)
            if (grant == grantType ? selected : _grantTypes.contains(grant)) grant,
        ];
      });

  static String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final redirectUris = parseRedirectUris(_redirectUris);
    final isValid = _name.trim().isNotEmpty &&
        isValidOAuthSetup(grantTypes: _grantTypes, redirectUris: redirectUris, publicClient: _publicClient);
    final canSubmit = isValid && !widget.isSubmitting;
    void submit() {
      if (!canSubmit) return;
      widget.onSubmit(
        ApplicationCreateSubmission(
          name: _name.trim(),
          description: _optional(_description),
          url: _optional(_url),
          logoUrl: _optional(_logoUrl),
          type: _type,
          grantTypes: _grantTypes,
          redirectUris: redirectUris,
          publicClient: _publicClient,
        ),
      );
    }

    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        ApplicationCreateFormState(
          name: _name,
          onNameChanged: (value) => setState(() => _name = value),
          description: _description,
          onDescriptionChanged: (value) => setState(() => _description = value),
          url: _url,
          onUrlChanged: (value) => setState(() => _url = value),
          logoUrl: _logoUrl,
          onLogoUrlChanged: (value) => setState(() => _logoUrl = value),
          applicationTypes: applicationTypeOptions(ac),
          type: _type,
          onTypeChanged: (value) => setState(() => _type = value),
          availableGrantTypes: applicationGrantTypeOptions(ac),
          grantTypes: _grantTypes,
          onGrantTypeChanged: _setGrantType,
          redirectUris: _redirectUris,
          onRedirectUrisChanged: (value) => setState(() => _redirectUris = value),
          publicClient: _publicClient,
          onPublicClientChanged: (value) => setState(() => _publicClient = value),
          isValid: isValid,
          isSubmitting: widget.isSubmitting,
          error: widget.error,
          submit: submit,
          onCancel: widget.onCancel,
          clientSecret: widget.clientSecret,
          onSecretDismissed: widget.clientSecret == null ? null : widget.onSecretDismissed,
        ),
      );
    }

    final secret = widget.clientSecret;
    if (secret != null) {
      return AdminSection(
        ac: ac,
        block: 'application-create',
        title: widget.title ?? ac.t('admin.applications.create.title'),
        children: [
          AdminSecretReveal(
            ac: ac,
            block: 'application-create',
            secret: secret,
            onDone: () => widget.onSecretDismissed?.call(),
          ),
        ],
      );
    }

    return AdminSection(
      ac: ac,
      block: 'application-create',
      title: widget.title ?? ac.t('admin.applications.create.title'),
      description: widget.description,
      children: [
        if (widget.error != null) AdminAlert(ac: ac, message: widget.error!, block: 'application-create'),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.applications.fields.name'),
          identifier: 'thunderid-field-application-create-name',
          required: true,
          onChanged: (value) => setState(() => _name = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.applications.fields.description'),
          identifier: 'thunderid-field-application-create-description',
          onChanged: (value) => setState(() => _description = value),
        ),
        AdminDropdown(
          ac: ac,
          label: ac.t('admin.applications.fields.type'),
          identifier: 'thunderid-field-application-create-type',
          value: _type,
          options: applicationTypeOptions(ac),
          onChanged: (value) => setState(() => _type = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.applications.fields.url'),
          identifier: 'thunderid-field-application-create-url',
          keyboardType: TextInputType.url,
          onChanged: (value) => setState(() => _url = value),
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.applications.fields.logo_url'),
          identifier: 'thunderid-field-application-create-logoUrl',
          keyboardType: TextInputType.url,
          onChanged: (value) => setState(() => _logoUrl = value),
        ),
        AdminCheckboxGroup(
          ac: ac,
          label: ac.t('admin.applications.fields.grant_types'),
          identifier: 'thunderid-field-application-create-grantTypes',
          options: applicationGrantTypeOptions(ac),
          selected: _grantTypes,
          onChanged: _setGrantType,
        ),
        AdminTextField(
          ac: ac,
          label: ac.t('admin.applications.fields.redirect_uris'),
          identifier: 'thunderid-field-application-create-redirectUris',
          hint: ac.t('admin.applications.fields.redirect_uris_hint'),
          required: _grantTypes.contains(OAuth2GrantTypes.authorizationCode),
          maxLines: 3,
          onChanged: (value) => setState(() => _redirectUris = value),
        ),
        AdminCheckbox(
          ac: ac,
          label: ac.t('admin.applications.fields.public_client'),
          identifier: 'thunderid-field-application-create-publicClient',
          value: _publicClient,
          onChanged: (value) => setState(() => _publicClient = value),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (widget.onCancel != null)
              AdminButton(
                ac: ac,
                label: ac.t('admin.common.actions.cancel'),
                identifier: 'thunderid-action-application-create-cancel',
                variant: AdminButtonVariant.text,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.applications.create.submit'),
              identifier: 'thunderid-action-application-create-submit',
              isLoading: widget.isSubmitting,
              onPressed: canSubmit ? submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Application form that creates the application through the management API, in [ouId]. When it
/// is omitted, the application goes to the current project (`ThunderIDState.currentProject`, set
/// by a [ProjectSwitcher]), which the server places in the project's root organization unit, or,
/// with no project chosen, to the signed-in user's own organization unit.
///
/// When the server returns a client secret for the new application, it is shown once; [onCreated]
/// receives it too, and it is forgotten when the secret is dismissed. The server guards
/// applications with the root `system` permission.
class ApplicationCreate extends StatefulWidget {
  final String? ouId;
  final ValueChanged<ApplicationCreateResult>? onCreated;

  /// Called when the client secret shown after creation is dismissed.
  final VoidCallback? onDone;
  final VoidCallback? onCancel;
  final String? title;
  final String? description;
  final ThunderIDPreferences? preferences;

  /// Builds custom UI in place of the default form. See [BaseApplicationCreate.builder].
  final AdminWidgetBuilder<ApplicationCreateFormState>? builder;

  const ApplicationCreate({
    super.key,
    this.ouId,
    this.onCreated,
    this.onDone,
    this.onCancel,
    this.title,
    this.description,
    this.preferences,
    this.builder,
  });

  @override
  State<ApplicationCreate> createState() => _ApplicationCreateState();
}

class _ApplicationCreateState extends AdminConnectedState<ApplicationCreate> {
  ResourceMutation<CreateApplicationRequest, Application>? _create;
  int _formGeneration = 0;

  @override
  void bind(ManagementResources resources) {
    _create = own(
      resources.createApplicationMutation(
        onSuccess: (application, _) => widget.onCreated?.call(
          ApplicationCreateResult(application: application, clientSecret: _secretOf(application)),
        ),
      ),
    );
  }

  static String? _secretOf(Application? application) {
    final secret = application?.oauth2Config?.clientSecret;
    return secret == null || secret.isEmpty ? null : secret;
  }

  void _dismissSecret() {
    _create?.reset();
    // A fresh form, so the next application starts from the defaults.
    setState(() => _formGeneration++);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final placement = CreatePlacement.of(widget.ouId, thunder);
    final create = _create;
    return BaseApplicationCreate(
      key: ValueKey(_formGeneration),
      isSubmitting: create?.isLoading ?? false,
      error: placement == null
          ? ac.t('admin.common.errors.no_ou')
          : toManagementErrorMessage(ac.t, create?.error, 'admin.applications.create.error'),
      clientSecret: _secretOf(create?.data),
      onSecretDismissed: _dismissSecret,
      onSubmit: (submission) {
        if (placement == null || create == null) return;
        unawaited(create.mutate(submission.toRequest(ouId: placement.ouId, projectId: placement.projectId)));
      },
      onCancel: widget.onCancel,
      title: widget.title,
      description: widget.description,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
