import Flutter
import ThunderID

/// Routes Flutter method channel calls to the native ThunderIDClient (spec §7.1).
/// All OAuth2/OIDC and token management logic lives in the ThunderID iOS SDK, not here.
@MainActor
final class ThunderIDMethodHandler {
    private let client = ThunderIDClient()
    private let federatedAuthSession = FederatedAuthSession()
    private let passkeyAuthSession = PasskeyAuthSession()

    func handle(method: String, args: [String: Any], result: @escaping FlutterResult) async {
        do {
            switch method {
            case "initialize":
                let config = try buildConfig(from: args)
                let ok = try await client.initialize(config: config)
                result(ok)

            case "reInitialize":
                let ok = try await client.reInitialize(
                    baseUrl: args["baseUrl"] as? String,
                    clientId: args["clientId"] as? String
                )
                result(ok)

            case "signIn":
                let payloadMap = args["payload"] as? [String: Any] ?? [:]
                let requestMap = args["request"] as? [String: Any] ?? [:]
                let payload = buildEmbeddedPayload(from: payloadMap)
                let request = buildFlowRequestConfig(from: requestMap)
                let response = try await client.signIn(payload: payload, request: request)
                result(encodeFlowResponse(response))

            case "continueFederatedAuth":
                await handleContinueFederatedAuth(args, result: result)

            case "performPasskeyAuthentication":
                let requestOptionsJson = args["requestOptionsJson"] as? String ?? ""
                let inputs = try await passkeyAuthSession.authenticate(requestOptionsJson: requestOptionsJson)
                result(inputs)

            case "performPasskeyRegistration":
                let creationOptionsJson = args["creationOptionsJson"] as? String ?? ""
                let inputs = try await passkeyAuthSession.register(creationOptionsJson: creationOptionsJson)
                result(inputs)

            case "buildSignInUrl":
                let url = try client.buildSignInURL()
                result(url.absoluteString)

            case "handleRedirectCallback":
                let urlStr = args["url"] as? String ?? ""
                guard let url = URL(string: urlStr) else {
                    throw ThunderIDError(code: .invalidRedirectUri, message: "Invalid callback URL")
                }
                let user = try await client.handleRedirectCallback(url: url)
                result(encodeUser(user))

            case "signOut":
                let afterUrl = try await client.signOut()
                result(afterUrl)

            case "isSignedIn":
                let signedIn = try await client.isSignedIn()
                result(signedIn)

            case "signUp":
                let payloadMap = args["payload"] as? [String: Any]
                let requestMap = args["request"] as? [String: Any]
                let payload = payloadMap.map { buildEmbeddedPayload(from: $0) }
                let request = requestMap.map { buildFlowRequestConfig(from: $0) }
                let response = try await client.signUp(payload: payload, request: request)
                result(encodeFlowResponse(response))

            case "getAccessToken":
                let token = try await client.getAccessToken()
                result(token)

            case "exchangeToken":
                let configMap = args["config"] as? [String: Any] ?? [:]
                let config = buildTokenExchangeConfig(from: configMap)
                let tokenResponse = try await client.exchangeToken(config: config)
                result(encodeTokenResponse(tokenResponse))

            case "decodeJwtToken":
                let token = args["token"] as? String ?? ""
                let claims = try client.decodeJwtToken(token) as [String: AnyCodable]
                result(claims.mapValues { "\($0.value)" })

            case "clearSession":
                client.clearSession()
                result(nil)

            case "getUser":
                let user = try await client.getUser()
                result(encodeUser(user))

            case "setCachedUser":
                let claims = args["user"] as? [String: Any] ?? [:]
                client.setCachedUser(User(claims: claims.mapValues { AnyCodable($0) }))
                result(nil)

            case "getUserProfile":
                let profile = try await client.getUserProfile()
                result(encodeUserProfile(profile))

            case "getUserSchema":
                let schema = try await client.getUserSchema()
                result(schema.mapValues { encodeAttributeSchema($0) })

            case "updateUserProfile":
                let payload = args["payload"] as? [String: Any] ?? [:]
                let profile = try await client.updateUserProfile(payload: payload)
                result(encodeUserProfile(profile))

            case "getFlowMeta":
                let appId = args["applicationId"] as? String ?? ""
                let language = args["language"] as? String ?? "en-US"
                let meta = try await client.getFlowMeta(applicationId: appId, language: language)
                result(meta)

            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let error as ThunderIDError {
            result(FlutterError(code: error.code.rawValue, message: error.message, details: nil))
        } catch {
            result(FlutterError(code: "UNKNOWN_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Federated auth (TRIGGER actions)

    /// Resumes a TRIGGER action after the server responded `type: "REDIRECTION"`: opens
    /// `redirectUrl` in an `ASWebAuthenticationSession`, extracts the `code` query parameter
    /// from the provider's callback, and resubmits the flow with `inputs: {"code": code}` —
    /// mirroring `BaseSignIn.handleRedirection` in `ThunderIDSwiftUI` (spec §6.1 federated
    /// sign-in extension). Handles its own errors and always calls `result` itself so a
    /// cancelled browser session can be reported with a dedicated `FEDERATED_AUTH_CANCELLED`
    /// code instead of falling into the generic `UNKNOWN_ERROR` path.
    private func handleContinueFederatedAuth(_ args: [String: Any], result: @escaping FlutterResult) async {
        let redirectUrlStr = args["redirectUrl"] as? String ?? ""
        guard let url = URL(string: redirectUrlStr) else {
            result(FlutterError(code: "INVALID_REDIRECT_URI", message: "Invalid redirect URL", details: nil))
            return
        }
        guard let scheme = callbackURLScheme(from: url) else {
            result(FlutterError(
                code: "INVALID_CONFIGURATION",
                message: "Unable to determine callback URL scheme from the authorization URL's " +
                    "redirect_uri or afterSignInUrl",
                details: nil
            ))
            return
        }
        do {
            let callbackURL = try await federatedAuthSession.authenticate(url: url, callbackURLScheme: scheme)
            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                result(FlutterError(
                    code: "INVALID_GRANT",
                    message: "Authorization code missing from callback URL",
                    details: nil
                ))
                return
            }
            let payload = EmbeddedSignInPayload(
                flowId: args["flowId"] as? String,
                actionId: args["actionId"] as? String ?? "",
                inputs: ["code": code],
                challengeToken: args["challengeToken"] as? String
            )
            let request = buildFlowRequestConfig(from: ["applicationId": args["applicationId"] as? String ?? ""])
            let response = try await client.signIn(payload: payload, request: request)
            result(encodeFlowResponse(response))
        } catch is FederatedAuthSession.CancelledError {
            result(FlutterError(code: "FEDERATED_AUTH_CANCELLED", message: "User cancelled federated sign-in", details: nil))
        } catch let error as ThunderIDError {
            result(FlutterError(code: error.code.rawValue, message: error.message, details: nil))
        } catch {
            result(FlutterError(code: "UNKNOWN_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    /// Resolves the scheme `ASWebAuthenticationSession` should watch for. `afterSignInUrl` is
    /// optional on `ThunderIDConfig` (Android and the Dart API impose no equivalent requirement),
    /// so prefer the `redirect_uri` query parameter already present on every standard OAuth2
    /// authorization URL, falling back to `afterSignInUrl` only if that's absent.
    private func callbackURLScheme(from redirectUrl: URL) -> String? {
        if let redirectUri = URLComponents(url: redirectUrl, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
           let scheme = URLComponents(string: redirectUri)?.scheme {
            return scheme
        }
        guard let afterSignInUrl = try? client.getConfiguration().afterSignInUrl,
              let scheme = URLComponents(string: afterSignInUrl)?.scheme else {
            return nil
        }
        return scheme
    }

    // MARK: - Builders

    private func buildConfig(from args: [String: Any]) throws -> ThunderIDConfig {
        guard let baseUrl = args["baseUrl"] as? String else {
            throw ThunderIDError(code: .invalidConfiguration, message: "baseUrl is required")
        }
        let validation = (args["tokenValidation"] as? [String: Any]).map { v in
            TokenValidationConfig(
                validate: v["validate"] as? Bool ?? true,
                validateIssuer: v["validateIssuer"] as? Bool ?? true,
                clockTolerance: v["clockTolerance"] as? Int ?? 0
            )
        } ?? TokenValidationConfig()
        let attestationEnabled = args["attestationEnabled"] as? Bool ?? false
        return ThunderIDConfig(
            baseUrl: baseUrl,
            clientId: args["clientId"] as? String,
            scopes: (args["scopes"] as? [String]) ?? ["openid"],
            afterSignInUrl: args["afterSignInUrl"] as? String,
            afterSignOutUrl: args["afterSignOutUrl"] as? String,
            applicationId: args["applicationId"] as? String,
            attestationEnabled: attestationEnabled,
            attestationTokenProvider: attestationEnabled
                ? { try await AppAttestTokenProvider().requestToken() } : nil,
            tokenValidation: validation,
            vendor: args["vendor"] as? String ?? VendorConstants.vendorPrefix
        )
    }

    private func buildEmbeddedPayload(from map: [String: Any]) -> EmbeddedSignInPayload {
        EmbeddedSignInPayload(
            flowId: map["flowId"] as? String,
            actionId: map["actionId"] as? String ?? "",
            inputs: (map["inputs"] as? [String: String]) ?? [:],
            challengeToken: map["challengeToken"] as? String
        )
    }

    private func buildFlowRequestConfig(from map: [String: Any]) -> EmbeddedFlowRequestConfig {
        let flowTypeStr = map["flowType"] as? String ?? "AUTHENTICATION"
        let flowType = FlowType(rawValue: flowTypeStr) ?? .authentication
        return EmbeddedFlowRequestConfig(
            applicationId: map["applicationId"] as? String ?? "",
            flowType: flowType
        )
    }

    private func buildTokenExchangeConfig(from map: [String: Any]) -> TokenExchangeRequestConfig {
        TokenExchangeRequestConfig(
            subjectToken: map["subjectToken"] as? String ?? "",
            subjectTokenType: map["subjectTokenType"] as? String ?? "",
            requestedTokenType: map["requestedTokenType"] as? String,
            audience: map["audience"] as? String
        )
    }

    // MARK: - Encoders

    // Claims are dynamic, so the whole set crosses the channel untouched, with decoded
    // values unwrapped into the types the platform channel codec can encode.
    private func encodeUser(_ user: User) -> [String: Any?] {
        user.claims.mapValues { unwrapClaim($0.value) }
    }

    private func encodeUserProfile(_ profile: UserProfile) -> [String: Any?] {
        [
            "id": profile.id,
            "ouId": profile.ouId,
            "type": profile.type,
            "attributes": profile.attributes.mapValues { unwrapClaim($0.value) },
            "display": profile.display,
            "isReadOnly": profile.isReadOnly
        ]
    }

    private func encodeAttributeSchema(_ schema: AttributeSchema) -> [String: Any?] {
        [
            "credential": schema.credential,
            "description": schema.description,
            "displayName": schema.displayName,
            "mutability": schema.mutability,
            "readOnly": schema.readOnly,
            "regex": schema.regex,
            "required": schema.required,
            "subAttributes": schema.subAttributes?.map { encodeAttributeSchema($0) },
            "type": schema.type,
            "unique": schema.unique
        ]
    }

    private func unwrapClaim(_ value: Any) -> Any {
        switch value {
        case let codable as AnyCodable:
            return unwrapClaim(codable.value)
        case let dictionary as [String: AnyCodable]:
            return dictionary.mapValues { unwrapClaim($0.value) }
        case let array as [AnyCodable]:
            return array.map { unwrapClaim($0.value) }
        default:
            return value
        }
    }

    private func encodeFlowResponse(_ r: EmbeddedFlowResponse) -> [String: Any?] {
        ["flowId": r.flowId, "flowStatus": flowStatusString(r.flowStatus),
         "stepId": r.stepId, "type": r.type,
         "data": r.data.map { encodeFlowStepData($0) },
         "assertion": r.assertion, "failureReason": r.failureReason,
         "challengeToken": r.challengeToken]
    }

    private func encodeFlowStepData(_ d: FlowStepData) -> [String: Any] {
        var result: [String: Any] = [:]
        if let inputs = d.inputs {
            result["inputs"] = inputs.map { ["name": $0.name, "type": $0.type as Any] }
        }
        if let actions = d.actions {
            result["actions"] = actions.map {
                [
                    "id": $0.id,
                    "ref": $0.ref as Any,
                    "nextNode": $0.nextNode as Any,
                    "label": $0.label as Any,
                    "eventType": $0.eventType as Any,
                    "type": $0.type as Any,
                    "variant": $0.variant as Any,
                    "icon": $0.icon as Any,
                ]
            }
        }
        if let meta = d.meta {
            result["meta"] = encodeFlowMeta(meta)
        }
        result["redirectURL"] = d.redirectURL as Any
        if let additionalData = d.additionalData {
            result["additionalData"] = additionalData.mapValues { $0.value }
        }
        return result
    }

    private func encodeFlowMeta(_ meta: FlowMeta) -> [String: Any] {
        var result: [String: Any] = [:]
        if let components = meta.components {
            result["components"] = components.map { encodeFlowComponent($0) }
        }
        return result
    }

    private func encodeFlowComponent(_ c: FlowComponent) -> [String: Any] {
        var result: [String: Any] = [
            "id": c.id as Any,
            "ref": c.ref as Any,
            "type": c.type as Any,
            "category": c.category as Any,
            "label": c.label as Any,
            "placeholder": c.placeholder as Any,
            "variant": c.variant as Any,
            "eventType": c.eventType as Any,
            "align": c.align as Any,
            "icon": c.icon as Any,
        ]
        if let components = c.components {
            result["components"] = components.map { encodeFlowComponent($0) }
        }
        return result
    }

    private func flowStatusString(_ status: FlowStatus) -> String {
        switch status {
        case .promptOnly:
            return "PROMPT_ONLY"
        case .complete:
            return "COMPLETE"
        case .error:
            return "ERROR"
        }
    }

    private func encodeTokenResponse(_ r: TokenResponse) -> [String: Any?] {
        ["accessToken": r.accessToken, "tokenType": r.tokenType,
         "expiresIn": r.expiresIn, "refreshToken": r.refreshToken,
         "idToken": r.idToken, "scope": r.scope]
    }
}
