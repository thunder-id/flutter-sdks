package dev.thunderid.flutter

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import dev.thunderid.android.api.auth.FederatedAuthSession
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class ThunderIDFlutterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var handler: ThunderIDMethodHandler
    private val scope = CoroutineScope(Dispatchers.Main)
    private var activity: Activity? = null

    // Cancels any in-flight federated-auth Custom Tab session when the host Activity resumes
    // without having received the provider's redirect (e.g. the user pressed back in the tab).
    // Safe to call unconditionally: FederatedAuthSession.cancelIfPending() is a no-op once the
    // session already completed via onNewIntent.
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(resumedActivity: Activity) {
            if (resumedActivity === activity) FederatedAuthSession.cancelIfPending()
        }
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityPaused(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handler = ThunderIDMethodHandler(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "dev.thunderid/sdk")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val args = call.arguments<Map<String, Any?>>() ?: emptyMap()
        scope.launch {
            handler.handle(call.method, args, result)
        }
    }

    // ── ActivityAware — required so `continueFederatedAuth` can launch a Custom Tab from an
    // Activity context, and so the provider's redirect (delivered via onNewIntent to the host
    // app's registered callback scheme) reaches FederatedAuthSession.onRedirect ──

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        // Unlike onDetachedFromActivityForConfigChanges, this is a permanent detach (e.g. the
        // host Activity finished while the Custom Tab was open) — nothing will resume to call
        // cancelIfPending() via onActivityResumed, so the suspended method-channel request would
        // otherwise hang indefinitely.
        FederatedAuthSession.cancelIfPending()
        detachActivity()
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        handler.activity = binding.activity
        binding.activity.application.registerActivityLifecycleCallbacks(lifecycleCallbacks)
        binding.addOnNewIntentListener { intent -> handleNewIntent(intent) }
    }

    private fun detachActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        activity = null
        handler.activity = null
    }

    private fun handleNewIntent(intent: Intent): Boolean {
        val data = intent.data
        if (data != null) FederatedAuthSession.onRedirect(data)
        return false
    }
}
