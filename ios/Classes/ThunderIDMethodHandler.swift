import Flutter
import ThunderID

/// Routes Flutter method channel calls to the native ThunderIDClient (spec §7.1).
/// All OAuth2/OIDC and token management logic lives in the ThunderID iOS SDK, not here.
@MainActor
final class ThunderIDMethodHandler {
    private let client = ThunderIDClient()

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

            case "getUserProfile":
                let profile = try await client.getUserProfile()
                result(["id": profile.id, "claims": [:]])

            case "updateUserProfile":
                let payload = args["payload"] as? [String: Any] ?? [:]
                let userId = args["userId"] as? String
                let user = try await client.updateUserProfile(payload: payload, userId: userId)
                result(encodeUser(user))

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
        return ThunderIDConfig(
            baseUrl: baseUrl,
            clientId: args["clientId"] as? String,
            scopes: (args["scopes"] as? [String]) ?? ["openid"],
            afterSignInUrl: args["afterSignInUrl"] as? String,
            afterSignOutUrl: args["afterSignOutUrl"] as? String,
            applicationId: args["applicationId"] as? String,
            tokenValidation: validation
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

    private func encodeUser(_ user: User) -> [String: Any?] {
        ["sub": user.sub, "email": user.email, "displayName": user.displayName,
         "username": user.username, "profilePicture": user.profilePicture,
         "isNewUser": user.isNewUser]
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
                ]
            }
        }
        if let meta = d.meta,
           let encoded = try? JSONEncoder().encode(meta),
           let obj = try? JSONSerialization.jsonObject(with: encoded) {
            result["meta"] = obj
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
