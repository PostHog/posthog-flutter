package com.posthog.flutter

import android.app.Activity
import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import com.posthog.PersonProfiles
import com.posthog.PostHog
import com.posthog.PostHogBootstrapConfig
import com.posthog.PostHogConfig
import com.posthog.PostHogOnFeatureFlags
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import com.posthog.android.internal.getApplicationInfo
import com.posthog.android.replay.PostHogInternalReplayApi
import com.posthog.android.replay.PostHogReplayIntegration
import com.posthog.logs.PostHogLogSeverity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Date
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.roundToInt

private const val FLUTTER_VIEW_CLASS_PREFIX = "io.flutter"
private const val OCCLUSION_TICK_MS = 1000L

private const val BRIDGE_FAILURE_STRIKE_LIMIT = 3

/** PosthogFlutterPlugin */
class PosthogFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    // / The MethodChannel that will be the communication between Flutter and native Android
    // /
    // / This local reference serves to register the plugin with the Flutter Engine and unregister it
    // / when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel

    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var application: Application? = null

    private var postHogConfig: PostHogAndroidConfig? = null

    // Occluded = host activity STOPPED (not just paused — a translucent/dialog
    // activity pauses the host while Flutter stays visible) AND one of our own
    // activities resumed on top (a stopped host alone is just backgrounding).
    // Out-of-process covers (Custom Tabs, Google Pay) are intentionally missed.
    @Volatile
    private var isHostActivityStopped = false

    // A count, not a boolean: under multi-resume (Android 10+ split-screen)
    // two non-host activities can be resumed at once, and pausing one must
    // not read as "nothing covers the host" while the other still does.
    @Volatile
    private var otherResumedCount = 0

    private val activityLifecycleCallbacks =
        object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(act: Activity) {
                if (act !== activity) {
                    otherResumedCount++
                    nudgeOcclusionDetector()
                }
            }

            override fun onActivityPaused(act: Activity) {
                // Floor at zero: a pause for a resume we never observed (the
                // callbacks registered while it was already resumed) must not
                // underflow the count.
                if (act !== activity && otherResumedCount > 0) {
                    otherResumedCount--
                }
            }

            override fun onActivityCreated(
                act: Activity,
                savedInstanceState: Bundle?,
            ) {}

            override fun onActivityStarted(act: Activity) {
                if (act === activity) {
                    isHostActivityStopped = false
                    nudgeOcclusionDetector()
                }
            }

            override fun onActivityStopped(act: Activity) {
                if (act === activity) {
                    isHostActivityStopped = true
                    nudgeOcclusionDetector()
                }
            }

            override fun onActivitySaveInstanceState(
                act: Activity,
                outState: Bundle,
            ) {}

            override fun onActivityDestroyed(act: Activity) {}
        }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bitmapExportExecutor = Executors.newSingleThreadExecutor()

    // The native SDK stamps its replay events (touches, bridged frames) with
    // config.dateProvider, which prefers the network-time clock on API 33+ and
    // can diverge from System.currentTimeMillis. Replay is ordered by
    // timestamp, so Flutter frames must use the same clock.
    private val snapshotSender =
        SnapshotSender {
            postHogConfig?.dateProvider?.currentTimeMillis() ?: System.currentTimeMillis()
        }

    private var flutterSurveysDelegate: PostHogFlutterSurveysDelegate? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "posthog_flutter")

        this.applicationContext = flutterPluginBinding.applicationContext
        initPlugin()

        channel.setMethodCallHandler(this)
    }

    private fun initPlugin() {
        try {
            val ai = getApplicationInfo(applicationContext)
            val bundle = ai.metaData ?: Bundle()
            val autoInit = bundle.getBoolean("com.posthog.posthog.AUTO_INIT", true)

            if (!autoInit) {
                Log.i("PostHog", "com.posthog.posthog.AUTO_INIT is disabled!")
                return
            }

            val projectToken =
                (
                    bundle.getString("com.posthog.posthog.PROJECT_TOKEN")
                        ?: bundle.getString("com.posthog.posthog.API_KEY")
                )?.trim()

            if (!bundle.containsKey("com.posthog.posthog.PROJECT_TOKEN") && bundle.containsKey("com.posthog.posthog.API_KEY")) {
                Log.w(
                    "PostHog",
                    "com.posthog.posthog.API_KEY is deprecated and will be removed in the next major version. Use com.posthog.posthog.PROJECT_TOKEN instead!",
                )
            }

            if (projectToken.isNullOrEmpty()) {
                Log.e("PostHog", "Either com.posthog.posthog.PROJECT_TOKEN or com.posthog.posthog.API_KEY must be provided!")
                return
            }

            val host =
                bundle
                    .getString("com.posthog.posthog.POSTHOG_HOST", PostHogConfig.DEFAULT_HOST)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: PostHogConfig.DEFAULT_HOST
            // Check new key first, then legacy key, default to true
            val captureApplicationLifecycleEvents =
                if (bundle.containsKey("com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS")) {
                    bundle.getBoolean("com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS", true)
                } else {
                    bundle.getBoolean("com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS", true)
                }
            val debug = bundle.getBoolean("com.posthog.posthog.DEBUG", false)

            val posthogConfig = mutableMapOf<String, Any>()
            posthogConfig["projectToken"] = projectToken
            posthogConfig["apiKey"] = projectToken
            posthogConfig["host"] = host
            posthogConfig["captureApplicationLifecycleEvents"] = captureApplicationLifecycleEvents
            posthogConfig["debug"] = debug

            setupPostHog(posthogConfig)
        } catch (e: Throwable) {
            Log.e("PostHog", "initPlugin error: $e")
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "setup" -> {
                setup(call, result)
            }

            "identify" -> {
                identify(call, result)
            }

            "setPersonProperties" -> {
                setPersonProperties(call, result)
            }

            "capture" -> {
                capture(call, result)
            }

            "screen" -> {
                screen(call, result)
            }

            "captureLog" -> {
                captureLog(call, result)
            }

            "alias" -> {
                alias(call, result)
            }

            "distinctId" -> {
                distinctId(result)
            }

            "reset" -> {
                reset(result)
            }

            "disable" -> {
                disable(result)
            }

            "enable" -> {
                enable(result)
            }

            "isOptOut" -> {
                isOptOut(result)
            }

            "isFeatureEnabled" -> {
                isFeatureEnabled(call, result)
            }

            "reloadFeatureFlags" -> {
                reloadFeatureFlags(result)
            }

            "setPersonPropertiesForFlags" -> {
                setPersonPropertiesForFlags(call, result)
            }

            "resetPersonPropertiesForFlags" -> {
                resetPersonPropertiesForFlags(result)
            }

            "setGroupPropertiesForFlags" -> {
                setGroupPropertiesForFlags(call, result)
            }

            "resetGroupPropertiesForFlags" -> {
                resetGroupPropertiesForFlags(call, result)
            }

            "group" -> {
                group(call, result)
            }

            "getFeatureFlag" -> {
                getFeatureFlag(call, result)
            }

            "getFeatureFlagPayload" -> {
                getFeatureFlagPayload(call, result)
            }

            "getFeatureFlagResult" -> {
                getFeatureFlagResult(call, result)
            }

            "register" -> {
                register(call, result)
            }

            "unregister" -> {
                unregister(call, result)
            }

            "debug" -> {
                debug(call, result)
            }

            "flush" -> {
                flush(result)
            }

            "captureException" -> {
                captureException(call, result)
            }

            "addExceptionStep" -> {
                addExceptionStep(call, result)
            }

            "close" -> {
                close(result)
            }

            "sendMetaEvent" -> {
                handleMetaEvent(call, result)
            }

            "sendFullSnapshot" -> {
                handleSendFullSnapshot(call, result)
            }

            "captureNativeScreenshot" -> {
                handleCaptureNativeScreenshot(call, result)
            }

            "captureNativeScreenshots" -> {
                handleCaptureNativeScreenshots(call, result)
            }

            "enableNativeBridge" -> {
                // Accept only when the bridge can deliver frames, and only for
                // the episode Dart is reacting to: a stale enable that lands
                // after its episode ended must not re-arm the bridge for a
                // later episode Dart never handed off. Declines never disarm,
                // so a stale decline can't stomp a live episode.
                val episode = call.argument<Int>("episode")
                val accepted =
                    isOccluded && episode == occlusionEpisode &&
                        replayIntegration() != null && isSessionReplayActive()
                if (accepted) {
                    bridgeEnabled = true
                    nudgeOcclusionDetector()
                }
                result.success(accepted)
            }

            "isSessionReplayActive" -> {
                result.success(isSessionReplayActive())
            }

            "startSessionRecording" -> {
                startSessionRecording(call, result)
            }

            "stopSessionRecording" -> {
                stopSessionRecording(result)
            }

            "getSessionId" -> {
                getSessionId(result)
            }

            "openUrl" -> {
                openUrl(call, result)
            }

            "surveyAction" -> {
                handleSurveyAction(call, result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun isSessionReplayActive(): Boolean = PostHog.isSessionReplayActive()

    private fun startSessionRecording(
        call: MethodCall,
        result: Result,
    ) {
        val resumeCurrent = call.arguments as? Boolean ?: true
        PostHog.startSessionReplay(resumeCurrent)
        result.success(null)
    }

    private fun stopSessionRecording(result: Result) {
        PostHog.stopSessionReplay()
        result.success(null)
    }

    private fun handleMetaEvent(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            val screen = call.argument<String>("screen") ?: ""

            if (width == 0 || height == 0) {
                result.error("INVALID_ARGUMENT", "Width or height is 0", null)
                return
            }

            snapshotSender.sendMetaEvent(width, height, screen)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun setup(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val args = call.arguments() as Map<String, Any>? ?: mapOf<String, Any>()
            if (args.isEmpty()) {
                result.error("PosthogFlutterException", "Arguments is null or empty", null)
                return
            }

            setupPostHog(args)

            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun setupPostHog(posthogConfig: Map<String, Any>) {
        val projectToken =
            (
                (posthogConfig["projectToken"] as String?)
                    ?: (posthogConfig["apiKey"] as String?)
            )?.trim()
        if (!posthogConfig.containsKey("projectToken") && posthogConfig.containsKey("apiKey")) {
            Log.w(
                "PostHog",
                "apiKey is deprecated and will be removed in the next major version. Use projectToken instead!",
            )
        }
        if (projectToken.isNullOrEmpty()) {
            Log.e("PostHog", "Either projectToken or apiKey must be provided!")
            return
        }

        val host =
            (posthogConfig["host"] as String?)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: PostHogConfig.DEFAULT_HOST

        val config =
            PostHogAndroidConfig(projectToken, host).apply {
                captureScreenViews = false
                captureDeepLinks = false
                posthogConfig.getIfNotNull<Boolean>("captureApplicationLifecycleEvents") {
                    captureApplicationLifecycleEvents = it
                }
                posthogConfig.getIfNotNull<Boolean>("debug") {
                    debug = it
                }
                posthogConfig.getIfNotNull<Int>("flushAt") {
                    flushAt = it
                }
                posthogConfig.getIfNotNull<Int>("maxQueueSize") {
                    maxQueueSize = it
                }
                posthogConfig.getIfNotNull<Int>("maxBatchSize") {
                    maxBatchSize = it
                }
                posthogConfig.getIfNotNull<Int>("flushInterval") {
                    flushIntervalSeconds = it
                }
                posthogConfig.getIfNotNull<Boolean>("sendFeatureFlagEvents") {
                    sendFeatureFlagEvent = it
                }
                posthogConfig.getIfNotNull<Boolean>("preloadFeatureFlags") {
                    preloadFeatureFlags = it
                }
                posthogConfig.getIfNotNull<Boolean>("optOut") {
                    optOut = it
                }
                posthogConfig.getIfNotNull<String>("personProfiles") {
                    when (it) {
                        "never" -> personProfiles = PersonProfiles.NEVER
                        "always" -> personProfiles = PersonProfiles.ALWAYS
                        "identifiedOnly" -> personProfiles = PersonProfiles.IDENTIFIED_ONLY
                    }
                }
                posthogConfig.getIfNotNull<Boolean>("sessionReplay") {
                    sessionReplay = it
                }

                this.sessionReplayConfig.captureLogcat = false

                posthogConfig.getIfNotNull<Map<String, Any>>("sessionReplayConfig") { replayConfig ->
                    replayConfig.getIfNotNull<Double>("sampleRate") {
                        this.sessionReplayConfig.sampleRate = it
                    }
                    if (sessionReplay) {
                        val captureNativeScreens =
                            replayConfig["captureNativeScreens"] as? Boolean ?: false
                        // Unconditional: only bridged captures read these, so a
                        // runtime bridge toggle honors them.
                        (replayConfig["maskAllTexts"] as? Boolean)?.let {
                            this.sessionReplayConfig.maskAllTextInputs = it
                        }
                        (replayConfig["maskAllImages"] as? Boolean)?.let {
                            this.sessionReplayConfig.maskAllImages = it
                        }
                        if (captureNativeScreens) {
                            mainHandler.post { startOcclusionDetector() }
                        } else {
                            mainHandler.post { disableOcclusionDetector() }
                        }
                    } else {
                        mainHandler.post { disableOcclusionDetector() }
                    }
                }

                // Configure surveys
                posthogConfig.getIfNotNull<Boolean>("surveys") {
                    surveys = it
                    if (surveys) {
                        val delegate = PostHogFlutterSurveysDelegate(channel)
                        surveysConfig.surveysDelegate = delegate
                        flutterSurveysDelegate = delegate
                    }
                }

                // Configure error tracking autocapture
                posthogConfig.getIfNotNull<Map<String, Any>>("errorTrackingConfig") { errorConfig ->
                    errorConfig.getIfNotNull<Boolean>("captureNativeExceptions") {
                        errorTrackingConfig.autoCapture = it
                    }
                    errorConfig.getIfNotNull<List<String>>("inAppIncludes") { includes ->
                        errorTrackingConfig.inAppIncludes.addAll(includes)
                    }
                    errorConfig.getIfNotNull<Map<String, Any>>("exceptionSteps") { stepsConfig ->
                        stepsConfig.getIfNotNull<Boolean>("enabled") {
                            errorTrackingConfig.exceptionSteps.enabled = it
                        }
                        stepsConfig.getIfNotNull<Int>("maxBytes") {
                            errorTrackingConfig.exceptionSteps.maxBytes = it
                        }
                    }
                }

                // Configure logs (beforeSend runs Dart-side). Each field is only
                // present when the user set it; unset fields keep native defaults.
                posthogConfig.getIfNotNull<Map<String, Any>>("logs") { logsConfig ->
                    logsConfig.getIfNotNull<String>("serviceName") {
                        logs.serviceName = it
                    }
                    logsConfig.getIfNotNull<String>("serviceVersion") {
                        logs.serviceVersion = it
                    }
                    logsConfig.getIfNotNull<String>("environment") {
                        logs.environment = it
                    }
                    logsConfig.getIfNotNull<Map<String, Any>>("resourceAttributes") {
                        logs.resourceAttributes = it
                    }
                    logsConfig.getIfNotNull<Int>("flushIntervalSeconds") {
                        logs.flushIntervalSeconds = it
                    }
                    logsConfig.getIfNotNull<Int>("flushAt") {
                        logs.flushAt = it
                    }
                    logsConfig.getIfNotNull<Int>("maxBatchSize") {
                        logs.maxBatchSize = it
                    }
                    logsConfig.getIfNotNull<Int>("maxBufferSize") {
                        logs.maxBufferSize = it
                    }
                    logsConfig.getIfNotNull<Int>("rateCapMaxLogs") {
                        logs.rateCapMaxLogs = it
                    }
                    logsConfig.getIfNotNull<Int>("rateCapWindowSeconds") {
                        logs.rateCapWindowSeconds = it
                    }
                }

                // Bootstrap precedence and flag layering live in the native SDK; forward values only.
                posthogConfig.getIfNotNull<Map<String, Any>>("bootstrap") {
                    this.bootstrap = bootstrapConfigFromMap(it)
                }

                sdkName = "posthog-flutter"
                sdkVersion = postHogVersion

                onFeatureFlags =
                    PostHogOnFeatureFlags {
                        Log.i("PostHogFlutter", "Android onFeatureFlags triggered. Notifying Dart.")
                        invokeFlutterMethod("onFeatureFlagsCallback", emptyMap<String, Any?>())
                    }
            }

        PostHogAndroid.setup(applicationContext, config)
        postHogConfig = config
        cachedReplayIntegration = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        application = binding.activity.application
        // Only if the detector is already running; else the setup path registers
        // it. Keeps a default-off feature from installing app-wide callbacks.
        if (occlusionDetectorRunning) {
            registerLifecycleTracking()
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterLifecycleTracking()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        application = binding.activity.application
        if (occlusionDetectorRunning) {
            registerLifecycleTracking()
        }
    }

    override fun onDetachedFromActivity() {
        unregisterLifecycleTracking()
        activity = null
    }

    // Idempotent: registering the same callbacks twice makes them fire twice.
    private fun registerLifecycleTracking() {
        val app = application ?: return
        if (lifecycleCallbacksRegistered) {
            return
        }
        isHostActivityStopped = false
        otherResumedCount = 0
        app.registerActivityLifecycleCallbacks(activityLifecycleCallbacks)
        lifecycleCallbacksRegistered = true
    }

    private fun unregisterLifecycleTracking() {
        if (!lifecycleCallbacksRegistered) {
            return
        }
        application?.unregisterActivityLifecycleCallbacks(activityLifecycleCallbacks)
        lifecycleCallbacksRegistered = false
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopOcclusionDetector()
        channel.setMethodCallHandler(null)
        bitmapExportExecutor.shutdown()
    }

    private var cachedReplayIntegration: PostHogReplayIntegration? = null

    private fun replayIntegration(): PostHogReplayIntegration? {
        cachedReplayIntegration?.let { return it }
        return postHogConfig
            ?.integrations
            ?.filterIsInstance<PostHogReplayIntegration>()
            ?.firstOrNull()
            .also { cachedReplayIntegration = it }
    }

    // Occlusion episode protocol: a main-thread ticker — independent of Flutter's
    // frame lifecycle, which can pause under a native cover — pushes occlusion
    // transitions to Dart and drives bridge captures. State below is @Volatile
    // for the capture executor.
    @Volatile
    internal var isOccluded = false

    @Volatile
    internal var bridgeEnabled = false

    // Whether the episode has delivered its first bridged frame.
    private var bridgeEpisodeStarted = false

    // End-transition debounce: ticks reading not-occluded while an episode is active.
    private var notOccludedTicks = 0

    // Monotonic episode id, stamped into every push so Dart drops stale-episode
    // async work. Volatile: re-read on the capture executor.
    @Volatile
    internal var occlusionEpisode = 0

    // Failed captures before the episode's first delivered frame; at the limit it
    // falls back (bridgeFailed). In-flight captures don't count; after first
    // delivery, failures never demote.
    private var bridgeFailureStrikes = 0

    // Set while a capture is scheduled but its result hasn't posted back — stops
    // stacking captures and mistaking in-flight for a delivery gap.
    private var bridgeCaptureInFlight = false

    private var occlusionDetectorRunning = false

    private var lifecycleCallbacksRegistered = false

    // One guarded tick. The running check no-ops a stale runnable (ticker or nudge)
    // that removeCallbacks missed post-teardown; the catch stops a throw (channel
    // invoke / peekDecorView on a dead window) from crashing the app.
    private fun runTickSafely() {
        if (!occlusionDetectorRunning) {
            return
        }
        try {
            occlusionTick()
        } catch (e: Throwable) {
            Log.w("PostHog", "Occlusion tick failed: $e")
        }
    }

    private val occlusionTicker =
        object : Runnable {
            override fun run() {
                runTickSafely()
                // Reschedule while running, even after a caught throw, so a
                // transient failure never kills the detector.
                if (occlusionDetectorRunning) {
                    mainHandler.postDelayed(this, OCCLUSION_TICK_MS)
                }
            }
        }

    // A named instance (not an anonymous lambda) so stopOcclusionDetector can
    // actually cancel a pending nudge.
    private val nudgeRunnable = Runnable { runTickSafely() }

    private fun startOcclusionDetector() {
        if (occlusionDetectorRunning) {
            return
        }
        occlusionDetectorRunning = true
        // Callbacks feed the detector and only run while it does — registered
        // here, not on attach, so a disabled bridge installs nothing.
        registerLifecycleTracking()
        mainHandler.postDelayed(occlusionTicker, OCCLUSION_TICK_MS)
    }

    // Runs a tick immediately on a lifecycle transition instead of waiting for
    // the next poll, so a native screen appears in replay within a frame or two.
    // Never reschedules the ticker.
    private fun nudgeOcclusionDetector() {
        if (!occlusionDetectorRunning) {
            return
        }
        // Coalesce a burst of lifecycle callbacks into one immediate tick.
        mainHandler.removeCallbacks(nudgeRunnable)
        mainHandler.post(nudgeRunnable)
    }

    private fun stopOcclusionDetector() {
        occlusionDetectorRunning = false
        mainHandler.removeCallbacks(occlusionTicker)
        mainHandler.removeCallbacks(nudgeRunnable)
        unregisterLifecycleTracking()
    }

    // For a setup() re-run that drops the feature: unlike a bare stop, ends any
    // active episode, otherwise Dart never learns and keeps its capture
    // suppressed.
    private fun disableOcclusionDetector() {
        stopOcclusionDetector()
        if (isOccluded || bridgeEnabled) {
            isOccluded = false
            bridgeEnabled = false
            bridgeEpisodeStarted = false
            bridgeFailureStrikes = 0
            bridgeCaptureInFlight = false
            pushOcclusionEvent(occluded = false)
        }
    }

    private fun pushOcclusionEvent(
        occluded: Boolean,
        bridgeFailed: Boolean = false,
    ) {
        channel.invokeMethod(
            "onNativeOcclusionChanged",
            mapOf(
                "occluded" to occluded,
                "episode" to occlusionEpisode,
                "bridgeFailed" to bridgeFailed,
            ),
        )
    }

    @OptIn(PostHogInternalReplayApi::class)
    private fun occlusionTick() {
        if (!isSessionReplayActive()) {
            if (isOccluded || bridgeEnabled) {
                isOccluded = false
                bridgeEnabled = false
                bridgeEpisodeStarted = false
                bridgeFailureStrikes = 0
                bridgeCaptureInFlight = false
                // Dart must learn the episode ended, otherwise the next
                // occluded=true push looks like unchanged state.
                pushOcclusionEvent(occluded = false)
            }
            return
        }
        // Null activity (config-change detach) fails open — the captured Flutter
        // tree has no native pixels. Known limitation: a host recreation
        // mid-episode never re-fires onActivityResumed, ending the episode early.
        val occludedNow =
            activity != null && isHostActivityStopped && otherResumedCount > 0
        // Debounce END only: a native→native handoff (A pauses before B resumes)
        // briefly reads not-occluded; ending the episode there would flash a
        // stale Flutter frame into the native flow.
        if (!occludedNow && isOccluded && notOccludedTicks < 1) {
            notOccludedTicks++
            return
        }
        notOccludedTicks = 0
        if (occludedNow != isOccluded) {
            val previousOccluded = isOccluded
            val previousEpisode = occlusionEpisode
            isOccluded = occludedNow
            if (occludedNow) {
                occlusionEpisode++
            } else {
                bridgeEnabled = false
            }
            bridgeEpisodeStarted = false
            bridgeFailureStrikes = 0
            bridgeCaptureInFlight = false
            try {
                pushOcclusionEvent(occluded = occludedNow)
            } catch (e: Throwable) {
                // The transition never reached Dart. Roll the episode state
                // back so the next tick re-detects and re-pushes it, instead
                // of advancing to an episode Dart never heard begin — whose
                // bridge frames it would then silently drop as stale.
                isOccluded = previousOccluded
                occlusionEpisode = previousEpisode
                throw e
            }
        }
        if (occludedNow && bridgeEnabled && !bridgeCaptureInFlight) {
            // excludeView and validity are resolved at call time (surviving host
            // recreation); the first capture resets the decor view's snapshot
            // state so a reused activity opens with a full snapshot.
            val isFirst = !bridgeEpisodeStarted
            val episode = occlusionEpisode
            bridgeCaptureInFlight = true

            // Applies a capture outcome on the main thread (the capture callback
            // fires off it), ignoring a result that lands after the episode
            // moved on. Posted so it never runs re-entrantly within this tick.
            fun postResult(delivered: Boolean) {
                mainHandler.post {
                    // Engine detach can land between capture and result; the
                    // channel is dead then and a strike-limit push would throw
                    // uncaught on the main looper.
                    if (!occlusionDetectorRunning || occlusionEpisode != episode) {
                        return@post
                    }
                    bridgeCaptureInFlight = false
                    try {
                        onBridgeCaptureResult(delivered)
                    } catch (e: Throwable) {
                        Log.w("PostHog", "Occlusion bridge result failed: $e")
                    }
                }
            }
            val scheduled =
                try {
                    replayIntegration()?.captureSessionReplaySnapshot(
                        activity?.window?.peekDecorView(),
                        isFirst,
                        { isOccluded && bridgeEnabled && occlusionEpisode == episode },
                    ) { delivered -> postResult(delivered) } ?: false
                } catch (e: Throwable) {
                    // peekDecorView / captureSessionReplaySnapshot can throw on
                    // a torn-down window. Treat as not-scheduled so postResult
                    // below clears the in-flight latch; leaving it set would
                    // block every later capture for the rest of the episode.
                    Log.w("PostHog", "Occlusion bridge capture failed to schedule: $e")
                    false
                }
            // Nothing was queued, so the capture callback will never fire —
            // record the delivery gap.
            if (!scheduled) {
                postResult(false)
            }
        }
    }

    // Demotion is gated on the episode never having delivered: captures fail
    // transiently during interaction (the SDK rejects redraw-racing captures to
    // keep masks aligned), so demoting a working episode would swap real frames
    // for the fallback. After the first delivered frame, failures just hold the
    // last good frame.
    private fun onBridgeCaptureResult(delivered: Boolean) {
        if (!isOccluded || !bridgeEnabled) {
            return
        }
        if (delivered) {
            bridgeEpisodeStarted = true
            bridgeFailureStrikes = 0
        } else if (!bridgeEpisodeStarted) {
            bridgeFailureStrikes++
            if (bridgeFailureStrikes >= BRIDGE_FAILURE_STRIKE_LIMIT) {
                bridgeEnabled = false
                pushOcclusionEvent(occluded = true, bridgeFailed = true)
            }
        }
    }

    private fun handleSendFullSnapshot(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val imageBytes = call.argument<ByteArray>("imageBytes")
            val id = call.argument<Int>("id") ?: 1
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 0
            if (imageBytes != null) {
                snapshotSender.sendFullSnapshot(imageBytes, id, x, y)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Image bytes are null", null)
            }
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun handleCaptureNativeScreenshot(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val currentActivity =
                activity ?: run {
                    result.success(null)
                    return
                }
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 0
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            if (width <= 0 || height <= 0) {
                result.error("INVALID_ARGUMENT", "Width or height is 0", null)
                return
            }
            captureOneNative(currentActivity, x, y, width, height) { bytes ->
                result.success(bytes)
            }
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun handleCaptureNativeScreenshots(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val currentActivity =
                activity ?: run {
                    result.success(emptyList<ByteArray?>())
                    return
                }

            @Suppress("UNCHECKED_CAST")
            val views = call.argument<List<Map<String, Int>>>("views") ?: emptyList()
            if (views.isEmpty()) {
                result.success(emptyList<ByteArray?>())
                return
            }
            val results = ArrayList<ByteArray?>(views.size)

            fun captureNext(index: Int) {
                if (index >= views.size) {
                    result.success(results)
                    return
                }
                val v = views[index]
                val x = v["x"] ?: 0
                val y = v["y"] ?: 0
                val w = v["width"] ?: 0
                val h = v["height"] ?: 0
                if (w <= 0 || h <= 0) {
                    results.add(null)
                    captureNext(index + 1)
                    return
                }
                captureOneNative(currentActivity, x, y, w, h) { bytes ->
                    results.add(bytes)
                    captureNext(index + 1)
                }
            }
            captureNext(0)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun captureOneNative(
        activity: Activity,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        onResult: (ByteArray?) -> Unit,
    ) {
        val contentView =
            activity.findViewById<View>(android.R.id.content) ?: run {
                onResult(null)
                return
            }

        val contentWidthPx = contentView.width
        val contentHeightPx = contentView.height
        if (contentWidthPx <= 0 || contentHeightPx <= 0) {
            onResult(null)
            return
        }

        val density = activity.resources.displayMetrics.density
        val cropLeft = (x * density).roundToInt().coerceIn(0, contentWidthPx - 1)
        val cropTop = (y * density).roundToInt().coerceIn(0, contentHeightPx - 1)
        val cropRight = ((x + width) * density).roundToInt().coerceIn(cropLeft + 1, contentWidthPx)
        val cropBottom = ((y + height) * density).roundToInt().coerceIn(cropTop + 1, contentHeightPx)

        val logicalWidth = width.coerceAtLeast(1)
        val logicalHeight = height.coerceAtLeast(1)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val locationInWindow = IntArray(2)
            contentView.getLocationInWindow(locationInWindow)

            val bitmap = Bitmap.createBitmap(logicalWidth, logicalHeight, Bitmap.Config.ARGB_8888)

            // Flutter renders on FlutterSurfaceView — a SurfaceView that lives OUTSIDE the
            // window surface in its own hardware-composited layer. Capturing activity.window
            // gives only the (empty) window background. We must capture FlutterSurfaceView
            // directly, then composite any platform-view SurfaceViews (e.g. google_maps_flutter)
            // on top.
            val allSurfaceViews = collectAllSurfaceViews(contentView)

            val flutterSv = allSurfaceViews.firstOrNull { it.javaClass.name.startsWith(FLUTTER_VIEW_CLASS_PREFIX) }
            val platformViewSvs = allSurfaceViews.filter { !it.javaClass.name.startsWith(FLUTTER_VIEW_CLASS_PREFIX) }

            if (flutterSv == null) {
                val srcRect =
                    Rect(
                        locationInWindow[0] + cropLeft,
                        locationInWindow[1] + cropTop,
                        locationInWindow[0] + cropRight,
                        locationInWindow[1] + cropBottom,
                    )
                PixelCopy.request(
                    activity.window,
                    srcRect,
                    bitmap,
                    { copyResult ->
                        if (copyResult != PixelCopy.SUCCESS) {
                            bitmap.recycle()
                            captureNativeScreenshotFallback(
                                contentView,
                                cropLeft,
                                cropTop,
                                cropRight,
                                cropBottom,
                                logicalWidth,
                                logicalHeight,
                                onResult,
                            )
                            return@request
                        }
                        exportBitmapAsync(bitmap, onResult)
                    },
                    mainHandler,
                )
                return
            }

            if (flutterSv.width <= 0 || flutterSv.height <= 0) {
                bitmap.recycle()
                onResult(null)
                return
            }
            val fsvLocation = IntArray(2)
            flutterSv.getLocationInWindow(fsvLocation)
            val fsvSrcLeft = (locationInWindow[0] + cropLeft - fsvLocation[0]).coerceIn(0, flutterSv.width - 1)
            val fsvSrcTop = (locationInWindow[1] + cropTop - fsvLocation[1]).coerceIn(0, flutterSv.height - 1)
            val fsvSrcRight = (locationInWindow[0] + cropRight - fsvLocation[0]).coerceIn(fsvSrcLeft + 1, flutterSv.width)
            val fsvSrcBottom = (locationInWindow[1] + cropBottom - fsvLocation[1]).coerceIn(fsvSrcTop + 1, flutterSv.height)
            val fsvSrcRect = Rect(fsvSrcLeft, fsvSrcTop, fsvSrcRight, fsvSrcBottom)

            PixelCopy.request(
                flutterSv,
                fsvSrcRect,
                bitmap,
                { copyResult ->
                    if (copyResult != PixelCopy.SUCCESS) {
                        bitmap.recycle()
                        captureNativeScreenshotFallback(
                            contentView,
                            cropLeft,
                            cropTop,
                            cropRight,
                            cropBottom,
                            logicalWidth,
                            logicalHeight,
                            onResult,
                        )
                        return@request
                    }

                    if (platformViewSvs.isEmpty()) {
                        exportBitmapAsync(bitmap, onResult)
                    } else {
                        compositeSurfaceViewsOnto(
                            svList = platformViewSvs,
                            destBitmap = bitmap,
                            contentViewLocation = locationInWindow,
                            cropLeft = cropLeft,
                            cropTop = cropTop,
                            density = density,
                            index = 0,
                        ) {
                            exportBitmapAsync(bitmap, onResult)
                        }
                    }
                },
                mainHandler,
            )
            return
        }

        captureNativeScreenshotFallback(
            contentView = contentView,
            cropLeft = cropLeft,
            cropTop = cropTop,
            cropRight = cropRight,
            cropBottom = cropBottom,
            logicalWidth = logicalWidth,
            logicalHeight = logicalHeight,
            onResult = onResult,
        )
    }

    private fun collectAllSurfaceViews(view: View): List<SurfaceView> {
        val result = mutableListOf<SurfaceView>()
        if (view is SurfaceView) {
            result.add(view)
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                result.addAll(collectAllSurfaceViews(view.getChildAt(i)))
            }
        }
        return result
    }

    @Suppress("SameParameterValue")
    @RequiresApi(Build.VERSION_CODES.O)
    private fun compositeSurfaceViewsOnto(
        svList: List<SurfaceView>,
        destBitmap: Bitmap,
        contentViewLocation: IntArray,
        cropLeft: Int,
        cropTop: Int,
        density: Float,
        index: Int,
        onComplete: () -> Unit,
    ) {
        if (index >= svList.size) {
            onComplete()
            return
        }
        val sv = svList[index]
        val advance = {
            compositeSurfaceViewsOnto(svList, destBitmap, contentViewLocation, cropLeft, cropTop, density, index + 1, onComplete)
        }

        if (!sv.isAttachedToWindow || sv.width <= 0 || sv.height <= 0) {
            advance()
            return
        }

        val svLocation = IntArray(2)
        sv.getLocationInWindow(svLocation)

        val destX = ((svLocation[0] - contentViewLocation[0] - cropLeft) / density).roundToInt()
        val destY = ((svLocation[1] - contentViewLocation[1] - cropTop) / density).roundToInt()
        val svLogW = (sv.width / density).roundToInt().coerceAtLeast(1)
        val svLogH = (sv.height / density).roundToInt().coerceAtLeast(1)

        // Skip a SurfaceView extending well beyond the captured region: it's a
        // different platform view (e.g. a masked map) that merely overlaps, so
        // compositing it would leak masked content. Slack absorbs rounding.
        val tolerance = 8
        if (destX < -tolerance ||
            destY < -tolerance ||
            destX + svLogW > destBitmap.width + tolerance ||
            destY + svLogH > destBitmap.height + tolerance
        ) {
            advance()
            return
        }

        val svBitmap = Bitmap.createBitmap(svLogW, svLogH, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(
                sv,
                null,
                svBitmap,
                { svCopyResult ->
                    if (svCopyResult == PixelCopy.SUCCESS) {
                        val canvas = android.graphics.Canvas(destBitmap)
                        val paint =
                            android.graphics.Paint().apply {
                                // SRC replaces the destination, including any background fill in the
                                // "hole" left by the SurfaceView in the window surface.
                                xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC)
                            }
                        canvas.drawBitmap(svBitmap, destX.toFloat(), destY.toFloat(), paint)
                    }
                    svBitmap.recycle()
                    advance()
                },
                mainHandler,
            )
        } catch (e: Throwable) {
            svBitmap.recycle()
            advance()
        }
    }

    private fun captureNativeScreenshotFallback(
        contentView: View,
        cropLeft: Int,
        cropTop: Int,
        cropRight: Int,
        cropBottom: Int,
        logicalWidth: Int,
        logicalHeight: Int,
        onResult: (ByteArray?) -> Unit,
    ) {
        val contentBitmap =
            Bitmap.createBitmap(contentView.width, contentView.height, Bitmap.Config.ARGB_8888)
        // Software Canvas cannot read GPU-composited surfaces like SurfaceView or TextureView,
        // so those platform views may still appear blank when we hit this fallback path.
        contentView.draw(android.graphics.Canvas(contentBitmap))

        val croppedBitmap =
            Bitmap.createBitmap(
                contentBitmap,
                cropLeft,
                cropTop,
                cropRight - cropLeft,
                cropBottom - cropTop,
            )
        contentBitmap.recycle()

        val outputBitmap =
            if (croppedBitmap.width == logicalWidth && croppedBitmap.height == logicalHeight) {
                croppedBitmap
            } else {
                Bitmap.createScaledBitmap(croppedBitmap, logicalWidth, logicalHeight, true).also {
                    croppedBitmap.recycle()
                }
            }

        exportBitmapAsync(outputBitmap, onResult)
    }

    private fun bitmapToRawRgba(bitmap: Bitmap): ByteArray {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        bitmap.recycle()
        val bytes = ByteArray(pixels.size * 4)
        for (i in pixels.indices) {
            val pixel = pixels[i]
            bytes[i * 4] = ((pixel shr 16) and 0xFF).toByte() // R
            bytes[i * 4 + 1] = ((pixel shr 8) and 0xFF).toByte() // G
            bytes[i * 4 + 2] = (pixel and 0xFF).toByte() // B
            bytes[i * 4 + 3] = ((pixel shr 24) and 0xFF).toByte() // A
        }
        return bytes
    }

    private fun exportBitmapAsync(
        bitmap: Bitmap,
        onResult: (ByteArray?) -> Unit,
    ) {
        // A PixelCopy callback can fire after onDetachedFromEngine shut the
        // executor down. Guard the submission so it neither crashes the main
        // thread (RejectedExecutionException) nor leaks the bitmap.
        try {
            bitmapExportExecutor.execute {
                try {
                    val rgbaBytes = bitmapToRawRgba(bitmap)
                    mainHandler.post { onResult(rgbaBytes) }
                } catch (e: Throwable) {
                    if (!bitmap.isRecycled) bitmap.recycle()
                    mainHandler.post { onResult(null) }
                }
            }
        } catch (e: RejectedExecutionException) {
            if (!bitmap.isRecycled) bitmap.recycle()
            mainHandler.post { onResult(null) }
        }
    }

    private fun getFeatureFlag(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val featureFlagKey: String = call.argument("key")!!
            val flag = PostHog.getFeatureFlag(featureFlagKey)
            result.success(flag)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun getFeatureFlagPayload(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val featureFlagKey: String = call.argument("key")!!
            val flag = PostHog.getFeatureFlagPayload(featureFlagKey)
            result.success(flag)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun getFeatureFlagResult(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val featureFlagKey = call.argument<String>("key")
            if (featureFlagKey.isNullOrEmpty()) {
                result.error("PosthogFlutterException", "Missing argument: key", null)
                return
            }
            val sendEvent: Boolean = call.argument("sendEvent") ?: true
            val flagResult = PostHog.getFeatureFlagResult(featureFlagKey, sendEvent)

            if (flagResult != null) {
                result.success(
                    mapOf(
                        "key" to flagResult.key,
                        "enabled" to flagResult.enabled,
                        "variant" to flagResult.variant,
                        "payload" to flagResult.payload,
                    ),
                )
            } else {
                result.success(null)
            }
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun identify(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val userId: String = call.argument("userId")!!
            val userProperties: Map<String, Any>? = call.argument("userProperties")
            val userPropertiesSetOnce: Map<String, Any>? = call.argument("userPropertiesSetOnce")
            PostHog.identify(userId, userProperties, userPropertiesSetOnce)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun setPersonProperties(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val userPropertiesToSet: Map<String, Any>? = call.argument("userPropertiesToSet")
            val userPropertiesToSetOnce: Map<String, Any>? = call.argument("userPropertiesToSetOnce")
            PostHog.setPersonProperties(userPropertiesToSet, userPropertiesToSetOnce)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun capture(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val eventName: String = call.argument("eventName")!!
            val properties: Map<String, Any>? = call.argument("properties")
            val userProperties: Map<String, Any>? = call.argument("userProperties")
            val userPropertiesSetOnce: Map<String, Any>? = call.argument("userPropertiesSetOnce")
            PostHog.capture(
                eventName,
                properties = properties,
                userProperties = userProperties,
                userPropertiesSetOnce = userPropertiesSetOnce,
            )
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun screen(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val screenName: String = call.argument("screenName")!!
            val properties: Map<String, Any>? = call.argument("properties")
            PostHog.screen(screenName, properties)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun captureLog(
        call: MethodCall,
        result: Result,
    ) {
        val body: String? = call.argument("body")
        if (body == null) {
            result.error("PosthogFlutterException", "Missing argument: body", null)
            return
        }
        try {
            val level: String = call.argument("level") ?: "info"
            val attributes: Map<String, Any>? = call.argument("attributes")
            val traceId: String? = call.argument("traceId")
            val spanId: String? = call.argument("spanId")
            // traceFlags 0 is meaningful (W3C sampled-false); null omits it.
            val traceFlags: Int? = call.argument("traceFlags")
            // Unknown levels fall back to INFO.
            val severity = PostHogLogSeverity.from(level) ?: PostHogLogSeverity.INFO
            PostHog.captureLog(body, severity, attributes, traceId, spanId, traceFlags)
            result.success(null)
        } catch (e: Throwable) {
            // Unlike the other handlers, avoid returning e.localizedMessage: a
            // captureLog failure can carry the log body or attribute values, and
            // the message is forwarded back over the channel.
            result.error("PosthogFlutterException", "Failed to capture log", null)
        }
    }

    private fun alias(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val alias: String = call.argument("alias")!!
            PostHog.alias(alias)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun distinctId(result: Result) {
        try {
            val distinctId: String = PostHog.distinctId()
            result.success(distinctId)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun reset(result: Result) {
        try {
            PostHog.reset()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun enable(result: Result) {
        try {
            PostHog.optIn()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun debug(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val debug: Boolean = call.argument("debug")!!
            PostHog.debug(debug)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun disable(result: Result) {
        try {
            PostHog.optOut()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun isOptOut(result: Result) {
        try {
            val isOptedOut = PostHog.isOptOut()
            result.success(isOptedOut)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun isFeatureEnabled(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val key: String = call.argument("key")!!
            val isEnabled = PostHog.isFeatureEnabled(key)
            result.success(isEnabled)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun reloadFeatureFlags(result: Result) {
        try {
            // Resolve the Dart Future only once flags have actually finished
            // loading. The native callback fires on a background thread, so the
            // result must be posted back to the main thread for Flutter.
            PostHog.reloadFeatureFlags {
                Handler(Looper.getMainLooper()).post {
                    result.success(null)
                }
            }
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    // reloadFeatureFlags is handled on the Dart side (so the Future resolves only
    // after the awaited reload completes), so we always disable the native reload.
    private fun setPersonPropertiesForFlags(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val userProperties: Map<String, Any> = call.argument("userProperties")!!
            PostHog.setPersonPropertiesForFlags(userProperties, reloadFeatureFlags = false)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun resetPersonPropertiesForFlags(result: Result) {
        try {
            PostHog.resetPersonPropertiesForFlags(reloadFeatureFlags = false)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun setGroupPropertiesForFlags(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val groupType: String = call.argument("groupType")!!
            val groupProperties: Map<String, Any> = call.argument("groupProperties")!!
            PostHog.setGroupPropertiesForFlags(groupType, groupProperties, reloadFeatureFlags = false)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun resetGroupPropertiesForFlags(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val groupType: String? = call.argument("groupType")
            PostHog.resetGroupPropertiesForFlags(groupType, reloadFeatureFlags = false)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun group(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val groupType: String = call.argument("groupType")!!
            val groupKey: String = call.argument("groupKey")!!
            val groupProperties: Map<String, Any>? = call.argument("groupProperties")
            PostHog.group(groupType, groupKey, groupProperties)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun register(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val key: String = call.argument("key")!!
            val value: Any = call.argument("value")!!
            PostHog.register(key, value)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun unregister(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val key: String = call.argument("key")!!
            PostHog.unregister(key)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun flush(result: Result) {
        try {
            PostHog.flush()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun captureException(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val arguments =
                call.arguments as? Map<String, Any> ?: run {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments for captureException", null)
                    return
                }

            val properties = arguments["properties"] as? Map<String, Any>
            val timestampMs = arguments["timestamp"] as? Long

            // Extract timestamp from Flutter
            val timestamp: Date? =
                timestampMs?.let {
                    // timestampMs already in UTC milliseconds epoch
                    Date(timestampMs)
                }

            PostHog.capture("\$exception", properties = properties, timestamp = timestamp)
            result.success(null)
        } catch (e: Throwable) {
            result.error("CAPTURE_EXCEPTION_ERROR", "Failed to capture exception: ${e.message}", null)
        }
    }

    private fun addExceptionStep(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val message: String =
                call.argument("message") ?: run {
                    result.error("PosthogFlutterException", "Missing argument: message", null)
                    return
                }
            val properties: Map<String, Any>? = call.argument("properties")
            PostHog.addExceptionStep(message, properties)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun close(result: Result) {
        try {
            PostHog.close()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun getSessionId(result: Result) {
        try {
            val sessionId = PostHog.getSessionId()
            result.success(sessionId?.toString())
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    // Call the `completion` closure if cast to map value with `key` and type `T` is successful.
    @Suppress("UNCHECKED_CAST")
    private fun <T> Map<String, Any>.getIfNotNull(
        key: String,
        callback: (T) -> Unit,
    ) {
        (get(key) as? T)?.let {
            callback(it)
        }
    }

    private fun openUrl(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val raw = (call.arguments as? String)?.trim()
            if (raw.isNullOrEmpty()) {
                result.error("InvalidArguments", "URL is null or empty", null)
                return
            }

            var uri =
                try {
                    Uri.parse(raw)
                } catch (e: Throwable) {
                    result.error("InvalidArguments", "Malformed URL: $raw", null)
                    return
                }

            // If no scheme provided (e.g., "example.com"), default to https://
            if (uri.scheme.isNullOrEmpty()) {
                uri = Uri.parse("https://$raw")
            }

            val intent =
                Intent(Intent.ACTION_VIEW, uri).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

            try {
                applicationContext.startActivity(intent)
                result.success(null)
            } catch (e: ActivityNotFoundException) {
                result.error("ActivityNotFound", "No application can handle ACTION_VIEW for the given URL", null)
            }
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun invokeFlutterMethod(
        method: String,
        arguments: Any? = null,
    ) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            channel.invokeMethod(method, arguments)
        } else {
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod(method, arguments)
            }
        }
    }

    // MARK: - Survey Action Handling

    private fun handleSurveyAction(
        call: MethodCall,
        result: Result,
    ) {
        val args = call.arguments as? Map<String, Any>
        val type = args?.get("type") as? String

        // Check for invalid arguments
        if (args == null || type == null) {
            result.error("InvalidArguments", "Invalid survey action arguments", null)
            return
        }

        if (flutterSurveysDelegate == null) {
            result.error("InvalidArguments", "Survey delegate not available", null)
            return
        }

        flutterSurveysDelegate?.handleSurveyAction(type, args, result)
    }
}

@Suppress("UNCHECKED_CAST")
internal fun bootstrapConfigFromMap(bootstrap: Map<String, Any>): PostHogBootstrapConfig =
    PostHogBootstrapConfig(
        distinctId = bootstrap["distinctId"] as? String,
        isIdentifiedId = bootstrap["isIdentifiedId"] as? Boolean ?: false,
        featureFlags = bootstrap["featureFlags"] as? Map<String, Any>,
        featureFlagPayloads = bootstrap["featureFlagPayloads"] as? Map<String, Any?>,
    )
