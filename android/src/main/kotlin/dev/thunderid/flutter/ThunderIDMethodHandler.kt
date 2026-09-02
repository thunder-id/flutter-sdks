package dev.thunderid.flutter

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.MethodChannel.Result
import dev.thunderid.android.*
import dev.thunderid.android.auth.FederatedAuthSession
import dev.thunderid.android.auth.PasskeyClient
import kotlinx.coroutines.CancellationException

/**
 * Routes Flutter method channel calls to the native Android ThunderIDClient (spec §7.1).
 * All OAuth2/OIDC and token management logic lives in the ThunderID Android SDK.
 */
class ThunderIDMethodHandler(private val context: Context) {
    private val client = ThunderIDClient()
    private val passkeyClient = PasskeyClient()

    /**
     * Set by [ThunderIDFlutterPlugin] from its `ActivityAware` callbacks. Required for
     * `continueFederatedAuth` since launching a Custom Tab needs an Activity context; falls back
     * to the application context (set at construction) if no Activity is currently attached.
     */
    var activity: Activity? = null

    suspend fun handle(method: String, args: Map<String, Any?>, result: Result) {
        try {
            when (method) {
                "initialize" -> {
                    val config = buildConfig(args)
                    val storage = EncryptedStorageAdapter(context, prefsName = "dev.${config.vendor}.sdk.prefs")
                    result.success(client.initialize(config, storage))
                }
                "reInitialize" -> {
                    result.success(client.reInitialize(
                        baseUrl = args["baseUrl"] as? String,
                        clientId = args["clientId"] as? String
                    ))
                }
                "signIn" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payloadMap = args["payload"] as? Map<String, Any?> ?: emptyMap()
                    @Suppress("UNCHECKED_CAST")
                    val requestMap = args["request"] as? Map<String, Any?> ?: emptyMap()
                    val response = client.signIn(buildPayload(payloadMap), buildFlowRequest(requestMap))
                    result.success(encodeFlowResponse(response))
                }
                "continueFederatedAuth" -> {
                    val redirectUrl = args["redirectUrl"] as? String ?: ""
                    val actionId = args["actionId"] as? String ?: ""
                    val applicationId = args["applicationId"] as? String ?: ""
                    val flowId = args["flowId"] as? String
                    val challengeToken = args["challengeToken"] as? String
                    val callbackUri = FederatedAuthSession.launch(activity ?: context, redirectUrl)
                    val code = callbackUri.getQueryParameter("code")
                        ?: throw IAMException(
                            ThunderIDErrorCode.INVALID_GRANT,
                            "Federated sign-in did not return an authorization code"
                        )
                    val payload = EmbeddedSignInPayload(
                        flowId = flowId,
                        actionId = actionId,
                        inputs = mapOf("code" to code),
                        challengeToken = challengeToken
                    )
                    val request = EmbeddedFlowRequestConfig(applicationId = applicationId)
                    val response = client.signIn(payload, request)
                    result.success(encodeFlowResponse(response))
                }
                "performPasskeyAuthentication" -> {
                    val requestOptionsJson = args["requestOptionsJson"] as? String ?: ""
                    result.success(passkeyClient.authenticate(activity ?: context, requestOptionsJson))
                }
                "performPasskeyRegistration" -> {
                    val creationOptionsJson = args["creationOptionsJson"] as? String ?: ""
                    result.success(passkeyClient.register(activity ?: context, creationOptionsJson))
                }
                "buildSignInUrl" -> {
                    result.success(client.buildSignInUrl())
                }
                "handleRedirectCallback" -> {
                    val url = args["url"] as? String ?: ""
                    val user = client.handleRedirectCallback(url)
                    result.success(encodeUser(user))
                }
                "signOut" -> {
                    result.success(client.signOut())
                }
                "isSignedIn" -> {
                    result.success(client.isSignedIn())
                }
                "signUp" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payloadMap = args["payload"] as? Map<String, Any?>
                    @Suppress("UNCHECKED_CAST")
                    val requestMap = args["request"] as? Map<String, Any?>
                    val response = client.signUp(
                        payload = payloadMap?.let { buildPayload(it) },
                        request = requestMap?.let { buildFlowRequest(it) }
                    )
                    result.success(encodeFlowResponse(response))
                }
                "getAccessToken" -> {
                    result.success(client.getAccessToken())
                }
                "exchangeToken" -> {
                    @Suppress("UNCHECKED_CAST")
                    val configMap = args["config"] as? Map<String, Any?> ?: emptyMap()
                    result.success(encodeTokenResponse(client.exchangeToken(buildTokenExchangeConfig(configMap))))
                }
                "decodeJwtToken" -> {
                    val token = args["token"] as? String ?: ""
                    result.success(client.decodeJwtToken(token))
                }
                "clearSession" -> {
                    client.clearSession()
                    result.success(null)
                }
                "getUser" -> {
                    result.success(encodeUser(client.getUser()))
                }
                "getUserProfile" -> {
                    val profile = client.getUserProfile()
                    result.success(mapOf("id" to profile.id, "claims" to emptyMap<String, Any>()))
                }
                "updateUserProfile" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = args["payload"] as? Map<String, Any> ?: emptyMap()
                    val user = client.updateUserProfile(payload, args["userId"] as? String)
                    result.success(encodeUser(user))
                }
                "getFlowMeta" -> {
                    val appId = args["applicationId"] as? String ?: ""
                    val language = args["language"] as? String ?: "en-US"
                    result.success(client.getFlowMeta(appId, language))
                }
                else -> result.notImplemented()
            }
        } catch (e: IAMException) {
            result.error(e.code.value, e.message, null)
        } catch (e: CancellationException) {
            // User dismissed the Custom Tab without completing federated sign-in — surfaced as a
            // typed cancellation so the Dart layer can reset state silently instead of erroring.
            result.error("FEDERATED_AUTH_CANCELLED", "User cancelled federated sign-in", null)
        } catch (e: Exception) {
            result.error("UNKNOWN_ERROR", e.message, null)
        }
    }

    private fun buildConfig(args: Map<String, Any?>): ThunderIDConfig {
        val baseUrl = args["baseUrl"] as? String
            ?: throw IAMException(ThunderIDErrorCode.INVALID_CONFIGURATION, "baseUrl is required")
        @Suppress("UNCHECKED_CAST")
        val validationMap = args["tokenValidation"] as? Map<String, Any?>
        val validation = TokenValidationConfig(
            validate = validationMap?.get("validate") as? Boolean ?: true,
            validateIssuer = validationMap?.get("validateIssuer") as? Boolean ?: true,
            clockTolerance = validationMap?.get("clockTolerance") as? Int ?: 0
        )
        val attestationEnabled = args["attestationEnabled"] as? Boolean ?: false
        val cloudProjectNumber = (args["cloudProjectNumber"] as? Number)?.toLong()
        if (attestationEnabled && (cloudProjectNumber == null || cloudProjectNumber <= 0L)) {
            throw IAMException(
                ThunderIDErrorCode.INVALID_CONFIGURATION,
                "cloudProjectNumber must be a positive number when attestationEnabled is true"
            )
        }
        @Suppress("UNCHECKED_CAST")
        return ThunderIDConfig(
            baseUrl = baseUrl,
            clientId = args["clientId"] as? String,
            scopes = (args["scopes"] as? List<String>) ?: listOf("openid"),
            afterSignInUrl = args["afterSignInUrl"] as? String,
            afterSignOutUrl = args["afterSignOutUrl"] as? String,
            applicationId = args["applicationId"] as? String,
            // Lets a development build reach a ThunderID server using the self-signed certificate
            // it generates for localhost. iOS achieves the same at the app level through an
            // NSAppTransportSecurity exemption, so the flag is only meaningful here.
            allowInsecureConnections = args["allowInsecureConnections"] as? Boolean ?: false,
            attestationEnabled = attestationEnabled,
            attestationTokenProvider = if (attestationEnabled) {
                PlayIntegrityTokenProvider(context, cloudProjectNumber!!)::requestToken
            } else {
                null
            },
            tokenValidation = validation,
            vendor = args["vendor"] as? String ?: ThunderIDConfig.DEFAULT_VENDOR
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun buildPayload(map: Map<String, Any?>): EmbeddedSignInPayload = EmbeddedSignInPayload(
        flowId = map["flowId"] as? String,
        actionId = map["actionId"] as? String ?: "",
        inputs = (map["inputs"] as? Map<String, String>) ?: emptyMap(),
        challengeToken = map["challengeToken"] as? String
    )

    private fun buildFlowRequest(map: Map<String, Any?>): EmbeddedFlowRequestConfig {
        val flowTypeStr = map["flowType"] as? String ?: "AUTHENTICATION"
        val flowType = FlowType.values().firstOrNull { it.value == flowTypeStr } ?: FlowType.AUTHENTICATION
        return EmbeddedFlowRequestConfig(
            applicationId = map["applicationId"] as? String ?: "",
            flowType = flowType
        )
    }

    private fun buildTokenExchangeConfig(map: Map<String, Any?>): TokenExchangeRequestConfig = TokenExchangeRequestConfig(
        subjectToken = map["subjectToken"] as? String ?: "",
        subjectTokenType = map["subjectTokenType"] as? String ?: "",
        requestedTokenType = map["requestedTokenType"] as? String,
        audience = map["audience"] as? String
    )

    // Claims are dynamic, so the whole set crosses the channel untouched.
    private fun encodeUser(user: User) = user.claims

    private fun encodeFlowResponse(r: EmbeddedFlowResponse) = mapOf(
        "flowId" to r.flowId, "flowStatus" to r.flowStatus.name,
        "stepId" to r.stepId, "type" to r.type,
        "data" to r.data?.let { encodeFlowStepData(it) },
        "assertion" to r.assertion, "failureReason" to r.failureReason,
        "challengeToken" to r.challengeToken
    )

    private fun encodeFlowStepData(data: FlowStepData) = mapOf(
        "actions" to data.actions?.map { action ->
            mapOf(
                "id" to (action.id?.ifEmpty { null } ?: action.ref ?: action.nextNode ?: "submit"),
                "ref" to action.ref,
                "nextNode" to action.nextNode,
                "type" to action.type,
                "label" to action.label,
                "eventType" to action.eventType,
                "variant" to action.variant,
                "icon" to action.icon
            )
        },
        "inputs" to data.inputs?.map { input ->
            mapOf(
                "name" to input.name,
                "type" to input.type,
                "required" to input.required
            )
        },
        "meta" to data.meta?.let { encodeFlowMeta(it) },
        "additionalData" to data.additionalData
    )

    private fun encodeFlowMeta(meta: FlowMeta) = mapOf(
        "components" to meta.components?.map { encodeFlowComponent(it) }
    )

    private fun encodeFlowComponent(comp: FlowComponent): Map<String, Any?> = mapOf(
        "id" to comp.id,
        "ref" to comp.ref,
        "type" to comp.type,
        "category" to comp.category,
        "label" to comp.label,
        "placeholder" to comp.placeholder,
        "variant" to comp.variant,
        "eventType" to comp.eventType,
        "align" to comp.align,
        "icon" to comp.icon,
        "components" to comp.components?.map { encodeFlowComponent(it) }
    )

    private fun encodeTokenResponse(r: TokenResponse) = mapOf(
        "accessToken" to r.accessToken, "tokenType" to r.tokenType,
        "expiresIn" to r.expiresIn, "refreshToken" to r.refreshToken,
        "idToken" to r.idToken, "scope" to r.scope
    )
}
