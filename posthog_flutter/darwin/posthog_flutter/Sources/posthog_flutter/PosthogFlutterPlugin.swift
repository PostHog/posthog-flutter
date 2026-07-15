@_spi(PostHogInternal) import PostHog
#if os(iOS)
    import Flutter
    import UIKit
    import WebKit
#elseif os(macOS)
    import AppKit
    import FlutterMacOS
#endif

public class PosthogFlutterPlugin: NSObject, FlutterPlugin {
    #if os(iOS)
        // Occlusion episode protocol: a main-thread timer — independent of
        // Flutter's frame lifecycle, which can pause under a native cover —
        // pushes occlusion transitions to Dart and drives bridge captures.
        private var occlusionTimer: Timer?
        private var isOccluded = false
        var bridgeEnabled = false
        // Whether the episode has delivered its first bridged frame.
        private var bridgeEpisodeStarted = false
        // End-transition debounce: ticks reading not-occluded while an episode is active.
        private var notOccludedTicks = 0
        // Monotonic episode id, stamped into every push so Dart drops stale-episode work.
        private var occlusionEpisode = 0
        // Failed captures before the episode's first delivered frame; at the limit it
        // falls back (bridgeFailed). After first delivery, failures never demote.
        private var bridgeFailureStrikes = 0
        private static let bridgeFailureStrikeLimit = 3
    #endif

    private static var instance: PosthogFlutterPlugin?
    private var channel: FlutterMethodChannel?

    public static func getInstance() -> PosthogFlutterPlugin? {
        instance
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(featureFlagsDidUpdate),
            name: PostHogSDK.didReceiveFeatureFlags,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel: FlutterMethodChannel
        #if os(iOS)
            methodChannel = FlutterMethodChannel(name: "posthog_flutter", binaryMessenger: registrar.messenger())
        #elseif os(macOS)
            methodChannel = FlutterMethodChannel(name: "posthog_flutter", binaryMessenger: registrar.messenger)
        #endif
        let instance = PosthogFlutterPlugin()
        instance.channel = methodChannel
        PosthogFlutterPlugin.instance = instance
        initPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }

    @objc func featureFlagsDidUpdate() {
        invokeFlutterMethod("onFeatureFlagsCallback", arguments: [String: Any]())
    }

    private let dispatchQueue = DispatchQueue(label: "com.posthog.PosthogFlutterPlugin",
                                              target: .global(qos: .utility))

    public static func initPlugin() {
        let autoInit = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.AUTO_INIT") as? Bool ?? true
        if !autoInit {
            print("[PostHog] com.posthog.posthog.AUTO_INIT is disabled!")
            return
        }

        let projectToken = ((Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.PROJECT_TOKEN") as? String) ?? (Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.API_KEY") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.PROJECT_TOKEN") == nil,
           Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.API_KEY") != nil
        {
            print("[PostHog] com.posthog.posthog.API_KEY is deprecated and will be removed in the next major version. Use com.posthog.posthog.PROJECT_TOKEN instead!")
        }

        if projectToken.isEmpty {
            print("[PostHog] Either com.posthog.posthog.PROJECT_TOKEN or com.posthog.posthog.API_KEY must be provided!")
            return
        }

        let host = (Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.POSTHOG_HOST") as? String ?? PostHogConfig.defaultHost)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let captureApplicationLifecycleEvents = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS") as? Bool ?? true
        let debug = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.DEBUG") as? Bool ?? false

        setupPostHog([
            "projectToken": projectToken,
            "apiKey": projectToken,
            "host": host,
            "captureApplicationLifecycleEvents": captureApplicationLifecycleEvents,
            "debug": debug,
        ])
    }

    private static func setupPostHog(_ posthogConfig: [String: Any]) {
        guard let instance = PosthogFlutterPlugin.instance else {
            print("[PostHog] Plugin instance not found!")
            return
        }
        let projectToken = ((posthogConfig["projectToken"] as? String) ?? (posthogConfig["apiKey"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if posthogConfig["projectToken"] == nil, posthogConfig["apiKey"] != nil {
            print("[PostHog] apiKey is deprecated and will be removed in the next major version. Use projectToken instead!")
        }
        if projectToken.isEmpty {
            print("[PostHog] Either projectToken or apiKey must be provided!")
            return
        }

        let normalizedHost = (posthogConfig["host"] as? String ?? PostHogConfig.defaultHost)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = normalizedHost.isEmpty ? PostHogConfig.defaultHost : normalizedHost

        let config = PostHogConfig(
            projectToken: projectToken,
            host: host
        )
        config.captureScreenViews = false

        if let captureApplicationLifecycleEvents = posthogConfig["captureApplicationLifecycleEvents"] as? Bool {
            config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        }
        if let debug = posthogConfig["debug"] as? Bool {
            config.debug = debug
        }
        if let flushAt = posthogConfig["flushAt"] as? Int {
            config.flushAt = flushAt
        }
        if let maxQueueSize = posthogConfig["maxQueueSize"] as? Int {
            config.maxQueueSize = maxQueueSize
        }
        if let maxBatchSize = posthogConfig["maxBatchSize"] as? Int {
            config.maxBatchSize = maxBatchSize
        }
        if let flushInterval = posthogConfig["flushInterval"] as? Int {
            config.flushIntervalSeconds = Double(flushInterval)
        }
        if let sendFeatureFlagEvents = posthogConfig["sendFeatureFlagEvents"] as? Bool {
            config.sendFeatureFlagEvent = sendFeatureFlagEvents
        }
        if let preloadFeatureFlags = posthogConfig["preloadFeatureFlags"] as? Bool {
            config.preloadFeatureFlags = preloadFeatureFlags
        }
        if let optOut = posthogConfig["optOut"] as? Bool {
            config.optOut = optOut
        }

        if let personProfiles = posthogConfig["personProfiles"] as? String {
            switch personProfiles {
            case "never":
                config.personProfiles = .never
            case "always":
                config.personProfiles = .always
            case "identifiedOnly":
                config.personProfiles = .identifiedOnly
            default:
                break
            }
        }
        if let dataMode = posthogConfig["dataMode"] as? String {
            switch dataMode {
            case "wifi":
                config.dataMode = .wifi
            case "cellular":
                config.dataMode = .cellular
            case "any":
                config.dataMode = .any
            default:
                break
            }
        }
        #if os(iOS)
            // configure session replay
            if let sessionReplay = posthogConfig["sessionReplay"] as? Bool {
                config.sessionReplay = sessionReplay
            }
            // disabled since Dart has native libs such as http/dio and dont use the ios URLSession
            config.sessionReplayConfig.captureNetworkTelemetry = false

            if let sessionReplayConfigMap = posthogConfig["sessionReplayConfig"] as? [String: Any] {
                if let sampleRate = sessionReplayConfigMap["sampleRate"] as? NSNumber {
                    config.sessionReplayConfig.sampleRate = sampleRate
                }
                let captureNativeScreens =
                    sessionReplayConfigMap["captureNativeScreens"] as? Bool ?? false
                // Unconditional: only bridged captures read these, so a runtime
                // bridge toggle honors them.
                if let maskAllTexts = sessionReplayConfigMap["maskAllTexts"] as? Bool {
                    config.sessionReplayConfig.maskAllTextInputs = maskAllTexts
                }
                if let maskAllImages = sessionReplayConfigMap["maskAllImages"] as? Bool {
                    config.sessionReplayConfig.maskAllImages = maskAllImages
                }
                if config.sessionReplay, captureNativeScreens {
                    PosthogFlutterPlugin.instance?.startOcclusionDetector()
                } else {
                    PosthogFlutterPlugin.instance?.disableOcclusionDetector()
                }
            }

            // configure surveys
            if #available(iOS 15.0, *) {
                let surveys: Bool = posthogConfig["surveys"] as? Bool ?? false
                config.surveys = surveys
                if surveys {
                    // if surveys are enabled, assign this instance as the survey delegate (we'll take over rendering)
                    config.surveysConfig.surveysDelegate = instance
                }
            }
        #endif

        // Configure error tracking
        if let errorConfig = posthogConfig["errorTrackingConfig"] as? [String: Any] {
            // autoCapture is only available on iOS, macOS, and tvOS
            #if os(iOS) || os(macOS) || os(tvOS)
                if let captureNativeExceptions = errorConfig["captureNativeExceptions"] as? Bool {
                    config.errorTrackingConfig.autoCapture = captureNativeExceptions
                }
            #endif

            // inApp configuration works across all platforms (including manual capture)
            if let inAppIncludes = errorConfig["inAppIncludes"] as? [String] {
                config.errorTrackingConfig.inAppIncludes.append(contentsOf: inAppIncludes)
            }
            if let inAppExcludes = errorConfig["inAppExcludes"] as? [String] {
                config.errorTrackingConfig.inAppExcludes.append(contentsOf: inAppExcludes)
            }
            if let inAppByDefault = errorConfig["inAppByDefault"] as? Bool {
                config.errorTrackingConfig.inAppByDefault = inAppByDefault
            }

            if let exceptionSteps = errorConfig["exceptionSteps"] as? [String: Any] {
                if let enabled = exceptionSteps["enabled"] as? Bool {
                    config.errorTrackingConfig.exceptionSteps.enabled = enabled
                }
                if let maxBytes = exceptionSteps["maxBytes"] as? Int {
                    config.errorTrackingConfig.exceptionSteps.maxBytes = maxBytes
                }
            }
        }

        // Configure logs (beforeSend runs Dart-side). Each field is only present
        // when the user set it; unset fields keep native defaults.
        if let logsConfig = posthogConfig["logs"] as? [String: Any] {
            if let serviceName = logsConfig["serviceName"] as? String {
                config.logs.serviceName = serviceName
            }
            if let serviceVersion = logsConfig["serviceVersion"] as? String {
                config.logs.serviceVersion = serviceVersion
            }
            if let environment = logsConfig["environment"] as? String {
                config.logs.environment = environment
            }
            if let resourceAttributes = logsConfig["resourceAttributes"] as? [String: Any] {
                config.logs.resourceAttributes = resourceAttributes
            }
            if let flushIntervalSeconds = logsConfig["flushIntervalSeconds"] as? Int {
                config.logs.flushIntervalSeconds = TimeInterval(flushIntervalSeconds)
            }
            if let flushAt = logsConfig["flushAt"] as? Int {
                config.logs.flushAt = flushAt
            }
            if let maxBatchSize = logsConfig["maxBatchSize"] as? Int {
                config.logs.maxBatchSize = maxBatchSize
            }
            if let maxBufferSize = logsConfig["maxBufferSize"] as? Int {
                config.logs.maxBufferSize = maxBufferSize
            }
            if let rateCapMaxLogs = logsConfig["rateCapMaxLogs"] as? Int {
                config.logs.rateCapMaxLogs = rateCapMaxLogs
            }
            if let rateCapWindowSeconds = logsConfig["rateCapWindowSeconds"] as? Int {
                config.logs.rateCapWindowSeconds = TimeInterval(rateCapWindowSeconds)
            }
        }

        // Update SDK name and version
        postHogSdkName = "posthog-flutter"
        postHogVersion = postHogFlutterVersion

        PostHogSDK.shared.setup(config)
    }

    private var currentSurvey: PostHogDisplaySurvey?
    private var onSurveyShownCallback: OnPostHogSurveyShown?
    private var onSurveyResponseCallback: OnPostHogSurveyResponse?
    private var onSurveyClosedCallback: OnPostHogSurveyClosed?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            setup(call, result: result)
        case "getFeatureFlag":
            getFeatureFlag(call, result: result)
        case "isFeatureEnabled":
            isFeatureEnabled(call, result: result)
        case "getFeatureFlagPayload":
            getFeatureFlagPayload(call, result: result)
        case "getFeatureFlagResult":
            getFeatureFlagResult(call, result: result)
        case "identify":
            identify(call, result: result)
        case "setPersonProperties":
            setPersonProperties(call, result: result)
        case "capture":
            capture(call, result: result)
        case "screen":
            screen(call, result: result)
        case "captureLog":
            captureLog(call, result: result)
        case "alias":
            alias(call, result: result)
        case "distinctId":
            distinctId(result)
        case "reset":
            reset(result)
        case "enable":
            enable(result)
        case "disable":
            disable(result)
        case "isOptOut":
            isOptOut(result)
        case "debug":
            debug(call, result: result)
        case "reloadFeatureFlags":
            reloadFeatureFlags(result)
        case "setPersonPropertiesForFlags":
            setPersonPropertiesForFlags(call, result: result)
        case "resetPersonPropertiesForFlags":
            resetPersonPropertiesForFlags(result)
        case "setGroupPropertiesForFlags":
            setGroupPropertiesForFlags(call, result: result)
        case "resetGroupPropertiesForFlags":
            resetGroupPropertiesForFlags(call, result: result)
        case "group":
            group(call, result: result)
        case "register":
            register(call, result: result)
        case "unregister":
            unregister(call, result: result)
        case "flush":
            flush(result)
        case "captureException":
            captureException(call, result: result)
        case "addExceptionStep":
            addExceptionStep(call, result: result)
        case "close":
            close(result)
        case "sendMetaEvent":
            sendMetaEvent(call, result: result)
        case "sendFullSnapshot":
            sendFullSnapshot(call, result: result)
        case "captureNativeScreenshot":
            captureNativeScreenshot(call, result: result)
        case "captureNativeScreenshots":
            captureNativeScreenshots(call, result: result)
        case "enableNativeBridge":
            #if os(iOS)
                let episode = (call.arguments as? [String: Any])?["episode"] as? Int
                DispatchQueue.main.async {
                    // Accept only when the bridge can deliver frames, and only
                    // for the episode Dart is reacting to: a stale enable that
                    // lands after its episode ended must not re-arm the bridge
                    // for a later episode Dart never handed off. Declines never
                    // disarm, so a stale decline can't stomp a live episode.
                    let accepted = self.isOccluded
                        && episode == self.occlusionEpisode
                        && PostHogSDK.shared.isSessionReplayActive()
                    if accepted {
                        self.bridgeEnabled = true
                    }
                    result(accepted)
                }
            #else
                result(false)
            #endif
        case "isSessionReplayActive":
            isSessionReplayActive(result: result)
        case "startSessionRecording":
            startSessionRecording(call, result: result)
        case "stopSessionRecording":
            stopSessionRecording(result: result)
        case "getSessionId":
            getSessionId(result: result)
        case "openUrl":
            openUrl(call, result: result)
        case "surveyAction":
            #if os(iOS)
                handleSurveyAction(call, result: result)
            #else
                // surveys only supported on iOS
                result(nil)
            #endif
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

#if os(iOS)

    // MARK: - PostHogSurveysDelegate

    extension PosthogFlutterPlugin: PostHogSurveysDelegate {
        public func renderSurvey(
            _ survey: PostHogDisplaySurvey,
            onSurveyShown: @escaping OnPostHogSurveyShown,
            onSurveyResponse: @escaping OnPostHogSurveyResponse,
            onSurveyClosed: @escaping OnPostHogSurveyClosed
        ) {
            // Store the callbacks and survey for later use
            currentSurvey = survey
            onSurveyShownCallback = onSurveyShown
            onSurveyResponseCallback = onSurveyResponse
            onSurveyClosedCallback = onSurveyClosed

            // We don't need to handle the result here
            // All responses will come through the surveyResponse method
            invokeFlutterMethod("showSurvey", arguments: survey.toDict())
        }

        public func cleanupSurveys() {
            // Reset all survey-related state when the survey feature is stopped
            currentSurvey = nil
            onSurveyShownCallback = nil
            onSurveyResponseCallback = nil
            onSurveyClosedCallback = nil

            // Notify Flutter side that surveys have been cleaned up
            invokeFlutterMethod("hideSurveys", arguments: nil)
        }

        private func handleSurveyAction(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
            guard let survey = currentSurvey,
                  let args = call.arguments as? [String: Any],
                  let type = args["type"] as? String
            else {
                result(FlutterError(code: "InvalidArguments", message: "Invalid survey action arguments", details: nil))
                return
            }

            switch type {
            case "shown":
                onSurveyShownCallback?(survey)
            case "response":
                if let index = args["index"] as? Int,
                   index < survey.questions.count
                {
                    let question = survey.questions[index]
                    let responsePayload = args["response"]

                    // Create PostHogSurveyResponse based on question type
                    var surveyResponse: PostHogSurveyResponse

                    switch question {
                    case is PostHogDisplayLinkQuestion:
                        // For link questions
                        let boolValue = responsePayload as? Bool ?? false
                        surveyResponse = .link(boolValue)

                    case is PostHogDisplayRatingQuestion:
                        // For rating questions
                        let ratingValue = responsePayload as? Int
                        surveyResponse = .rating(ratingValue)

                    case let choiceQuestion as PostHogDisplayChoiceQuestion:
                        // For single/multiple choice questions
                        var selectedOptions: [String]? = nil

                        if choiceQuestion.isMultipleChoice {
                            // Multiple choice: accept array directly from Flutter
                            selectedOptions = responsePayload as? [String]
                            surveyResponse = .multipleChoice(selectedOptions)
                        } else {
                            // Single choice: Flutter sends as a list with one element
                            selectedOptions = responsePayload as? [String]
                            surveyResponse = .singleChoice(selectedOptions?.first)
                        }

                    default:
                        // Default to open text question
                        let textValue = responsePayload as? String
                        surveyResponse = .openEnded(textValue)
                    }

                    // Call the callback with the constructed response
                    if let nextQuestion = onSurveyResponseCallback?(survey, index, surveyResponse) {
                        result(["nextIndex": nextQuestion.questionIndex,
                                "isSurveyCompleted": nextQuestion.isSurveyCompleted])
                        return
                    }
                }
            case "closed":
                onSurveyClosedCallback?(survey)
                // Clear the callbacks after survey is closed
                currentSurvey = nil
                onSurveyShownCallback = nil
                onSurveyResponseCallback = nil
                onSurveyClosedCallback = nil
            default:
                break
            }

            result(nil)
        }
    }

#endif

extension PosthogFlutterPlugin {
    private func captureNativeScreenshot(_ call: FlutterMethodCall,
                                         result: @escaping FlutterResult)
    {
        #if os(iOS)
            guard let args = call.arguments as? [String: Any] else {
                _badArgumentError(result)
                return
            }
            let x = args["x"] as? Int ?? 0
            let y = args["y"] as? Int ?? 0
            let width = args["width"] as? Int ?? 0
            let height = args["height"] as? Int ?? 0
            guard width > 0, height > 0 else {
                _badArgumentError(result)
                return
            }
            captureOneNative(x: x, y: y, width: width, height: height) { bytes in
                result(bytes)
            }
        #else
            result(nil)
        #endif
    }

    private func captureNativeScreenshots(_ call: FlutterMethodCall,
                                          result: @escaping FlutterResult)
    {
        #if os(iOS)
            guard let args = call.arguments as? [String: Any],
                  let views = args["views"] as? [[String: Int]]
            else {
                result([])
                return
            }
            captureNextNative(views: views, index: 0, acc: []) { results in
                result(results)
            }
        #else
            result([])
        #endif
    }

    #if os(iOS)
        private func captureOneNative(x: Int, y: Int, width: Int, height: Int,
                                      onResult: @escaping (FlutterStandardTypedData?) -> Void)
        {
            DispatchQueue.main.async {
                guard let window = self.captureWindow() else {
                    onResult(nil)
                    return
                }

                // If a native VC is presented over Flutter (paywall, system sheet,
                // etc.) Flutter has no widget rects for it, so capturing would
                // include unmasked native content. Fall back to Flutter-only.
                if window.rootViewController?.presentedViewController != nil {
                    onResult(nil)
                    return
                }

                let cropRect = CGRect(x: x, y: y, width: width, height: height)
                    .intersection(window.bounds)
                guard !cropRect.isNull, !cropRect.isEmpty else {
                    onResult(nil)
                    return
                }

                // Only reveal a web view that the capture rect fully covers, and
                // snapshot only the crop region. Requiring containment (not mere
                // intersection) stops a neighboring MASKED web view that overlaps
                // this captured view's rect from being snapshotted and leaked.
                if let webView = self.findWKWebView(in: window, containedBy: cropRect) {
                    let config = WKSnapshotConfiguration()
                    config.rect = webView.convert(cropRect, from: nil).intersection(webView.bounds)
                    guard !config.rect.isNull, !config.rect.isEmpty else {
                        onResult(nil)
                        return
                    }
                    webView.takeSnapshot(with: config) { snapshotImage, error in
                        guard error == nil, let snapshotImage = snapshotImage else {
                            onResult(nil)
                            return
                        }
                        onResult(self.imageToRawRgba(snapshotImage).map(FlutterStandardTypedData.init(bytes:)))
                    }
                    return
                }

                // No WKWebView found for the captured rect. Returning nil here
                // keeps this safe: drawHierarchy over the full window would
                // include any masked CALayer-backed platform view overlapping
                // the crop region and leak it into replay.
                onResult(nil)
            }
        }

        private func captureNextNative(views: [[String: Int]], index: Int,
                                       acc: [FlutterStandardTypedData?],
                                       completion: @escaping ([FlutterStandardTypedData?]) -> Void)
        {
            guard index < views.count else {
                completion(acc)
                return
            }
            let v = views[index]
            let x = v["x"] ?? 0
            let y = v["y"] ?? 0
            let width = v["width"] ?? 0
            let height = v["height"] ?? 0
            captureOneNative(x: x, y: y, width: width, height: height) { bytes in
                self.captureNextNative(views: views, index: index + 1, acc: acc + [bytes], completion: completion)
            }
        }

        private func imageToRawRgba(_ image: UIImage) -> Data? {
            guard let cgImage = image.cgImage else { return nil }
            // image.size is in points; cgImage.width/height are physical pixels (2×/3× on Retina).
            // Dart decodes at logical-pixel dimensions, so the buffer must be point-sized.
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            let bytesPerRow = width * 4
            var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
            guard let context = CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return Data(buffer)
        }

        private func captureWindow() -> UIWindow? {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            // Prefer the window hosting Flutter: the key window can be a
            // foreign overlay (or the occluding screen itself), and searching
            // it would miss the platform views embedded in the Flutter tree.
            return windows.first(where: {
                Self.containsFlutterViewController($0.rootViewController)
            })
                ?? windows.first(where: \.isKeyWindow)
                ?? UIApplication.shared.windows.first
        }

        private func findWKWebView(in view: UIView, containedBy rect: CGRect) -> WKWebView? {
            if let webView = view as? WKWebView {
                let frameInWindow = webView.convert(webView.bounds, to: nil)
                // 1pt slack absorbs rounding between Flutter's rect and the native frame.
                if rect.insetBy(dx: -1, dy: -1).contains(frameInWindow) { return webView }
            }
            for sub in view.subviews {
                if let found = findWKWebView(in: sub, containedBy: rect) { return found }
            }
            return nil
        }
    #endif

    // The occlusion timer retains its closure until invalidated; without this
    // it would survive engine detach and push zombie occlusion events.
    public func detachFromEngine(for _: FlutterPluginRegistrar) {
        #if os(iOS)
            DispatchQueue.main.async { [weak self] in
                self?.stopOcclusionDetector()
            }
        #endif
    }

    #if os(iOS)
        func startOcclusionDetector() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.occlusionTimer == nil else { return }
                let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.occlusionTick()
                }
                RunLoop.main.add(timer, forMode: .common)
                self.occlusionTimer = timer
                // Event-driven nudge: an own-window paywall (Superwall-style) is
                // caught within a frame, not on the next poll, so covered frames
                // don't leak at episode start. Same-window modal has no global
                // hook, so it still relies on the ~1 s poll.
                for name in [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeKeyNotification] {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(self.nudgeOcclusionDetector),
                        name: name,
                        object: nil
                    )
                }
            }
        }

        func stopOcclusionDetector() {
            occlusionTimer?.invalidate()
            occlusionTimer = nil
            NotificationCenter.default.removeObserver(self, name: UIWindow.didBecomeVisibleNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIWindow.didBecomeKeyNotification, object: nil)
        }

        /// For a setup() re-run that drops the feature: unlike a bare stop,
        /// ends any active episode, otherwise Dart never learns and keeps its
        /// capture suppressed.
        func disableOcclusionDetector() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stopOcclusionDetector()
                if self.isOccluded || self.bridgeEnabled {
                    self.isOccluded = false
                    self.bridgeEnabled = false
                    self.bridgeEpisodeStarted = false
                    self.bridgeFailureStrikes = 0
                    self.pushOcclusionEvent(occluded: false)
                }
            }
        }

        // Notifications fire on main; the guard drops a stray one after stop.
        @objc private func nudgeOcclusionDetector() {
            guard occlusionTimer != nil else { return }
            occlusionTick()
        }

        private func pushOcclusionEvent(occluded: Bool, bridgeFailed: Bool = false) {
            channel?.invokeMethod(
                "onNativeOcclusionChanged",
                arguments: [
                    "occluded": occluded,
                    "episode": occlusionEpisode,
                    "bridgeFailed": bridgeFailed,
                ]
            )
        }

        private func occlusionTick() {
            // Freeze while not active: the SDK only snapshots foreground-active
            // windows, so every capture would fail and burn the episode's
            // pre-first-frame strikes during app switches or backgrounding.
            guard UIApplication.shared.applicationState == .active else {
                return
            }
            guard PostHogSDK.shared.isSessionReplayActive() else {
                if isOccluded || bridgeEnabled {
                    isOccluded = false
                    bridgeEnabled = false
                    bridgeEpisodeStarted = false
                    bridgeFailureStrikes = 0
                    // Dart must learn the episode ended, otherwise the next
                    // occluded=true push looks like unchanged state.
                    pushOcclusionEvent(occluded: false)
                }
                return
            }
            let occluded = Self.isFlutterOccluded()
            // Debounce END only: a native→native handoff briefly reads
            // not-occluded; ending the episode there would flash a stale frame.
            if !occluded, isOccluded, notOccludedTicks < 1 {
                notOccludedTicks += 1
                return
            }
            notOccludedTicks = 0
            if occluded != isOccluded {
                isOccluded = occluded
                if occluded {
                    occlusionEpisode += 1
                } else {
                    bridgeEnabled = false
                    bridgeEpisodeStarted = false
                }
                bridgeFailureStrikes = 0
                pushOcclusionEvent(occluded: occluded)
            }
            if occluded, bridgeEnabled {
                // First capture of an episode settles the presentation with
                // afterScreenUpdates; steady-state ticks avoid it because it
                // visibly flickers secure text fields.
                let isFirst = !bridgeEpisodeStarted
                if PostHogSDK.shared.captureSessionReplaySnapshot(episodeFirstFrame: isFirst) {
                    bridgeEpisodeStarted = true
                    bridgeFailureStrikes = 0
                } else if !bridgeEpisodeStarted {
                    // Demotion is gated on the episode never having delivered:
                    // captures fail transiently during interaction (mid-transition
                    // skips), so demoting a working episode would swap real frames
                    // for the fallback. After first delivery, failures just hold
                    // the last good frame.
                    bridgeFailureStrikes += 1
                    if bridgeFailureStrikes >= Self.bridgeFailureStrikeLimit {
                        bridgeEnabled = false
                        pushOcclusionEvent(occluded: true, bridgeFailed: true)
                    }
                }
            }
        }

        /// Whether the Flutter surface is NOT what the user currently sees,
        /// evaluated live — no cached identities. Single windows pass per tick.
        private static func isFlutterOccluded() -> Bool {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            guard let flutterWindow = windows.first(where: {
                containsFlutterViewController($0.rootViewController)
            }) else {
                // Fail open: without a Flutter window there is nothing to blank.
                return false
            }
            // Walk the whole presentation chain: native SDKs routinely present
            // full-screen from the top of an existing chain. A single geometric
            // + opacity test covers every presentation style: popovers, alerts,
            // and portrait sheets fail the coverage check; full-screen covers
            // (including compact-height sheets) pass it.
            var top = flutterWindow.rootViewController
            while let presented = top?.presentedViewController {
                if let view = presented.view,
                   Self.containsOpaqueCoveringView(view, window: flutterWindow)
                {
                    return true
                }
                top = presented
            }
            // An SDK-owned window made key above Flutter (e.g. Superwall
            // presents its paywall in its own UIWindow + makeKeyAndVisible).
            // It must actually cover the screen with opaque content —
            // floating-button, banner, or transparent passthrough windows that
            // hold key status do not count. Scoped to the Flutter window's
            // scene: on multi-scene (iPad) apps another scene's key window
            // does not cover this one.
            let sceneWindows = flutterWindow.windowScene?.windows ?? windows
            if let keyWindow = sceneWindows.first(where: \.isKeyWindow),
               keyWindow !== flutterWindow,
               !isSystemWindow(keyWindow),
               coversScreen(keyWindow),
               containsOpaqueCoveringView(keyWindow, window: keyWindow)
            {
                return true
            }
            return false
        }

        /// Whether [view]'s tree contains an opaque view that covers the
        /// window — a hierarchy test, because a single-view background check
        /// misses the common clear-container-with-opaque-child pattern of
        /// payment/auth SDKs. isOpaque is a rendering hint (defaults true), so
        /// only background-color alpha counts. Known bias: covers drawn purely
        /// by layers (camera previews) without an opaque background are missed
        /// and fall back to pre-feature stale-frame behavior.
        private static func containsOpaqueCoveringView(
            _ view: UIView,
            window: UIWindow,
            depth: Int = 0
        ) -> Bool {
            // Depth bound is a runaway guard, not a search budget — complex
            // SDK view trees nest far deeper than a handful of levels, and a
            // missed opaque cover silently disables the feature for that
            // screen. The walk early-exits on the first hit.
            guard depth <= 16, !view.isHidden, view.alpha >= 0.99 else {
                return false
            }
            let frameInWindow = view.convert(view.bounds, to: window)
            let windowArea = window.bounds.width * window.bounds.height
            guard windowArea > 0 else { return false }
            let covered = frameInWindow.intersection(window.bounds)
            let coversBounds = (covered.width * covered.height) >= windowArea * 0.95
            if coversBounds,
               let background = view.backgroundColor,
               background.cgColor.alpha >= 0.99
            {
                return true
            }
            // A child can cover even when its container is clear.
            return view.subviews.contains {
                containsOpaqueCoveringView($0, window: window, depth: depth + 1)
            }
        }
    #endif

    #if os(iOS)
        private static func containsFlutterViewController(_ viewController: UIViewController?) -> Bool {
            guard let viewController else { return false }
            if viewController is FlutterViewController { return true }
            return viewController.children.contains { $0 is FlutterViewController }
        }

        private static func isSystemWindow(_ window: UIWindow) -> Bool {
            let className = String(describing: type(of: window))
            return className.contains("Keyboard") || className.contains("TextEffects")
        }

        private static func coversScreen(_ window: UIWindow) -> Bool {
            guard !window.isHidden, window.alpha > 0.01 else { return false }
            let screen = window.screen.bounds.size
            guard screen.width > 0, screen.height > 0 else { return false }
            let size = window.frame.size
            return size.width >= screen.width * 0.95 && size.height >= screen.height * 0.95
        }
    #endif

    private func sendMetaEvent(_ call: FlutterMethodCall,
                               result: @escaping FlutterResult)
    {
        #if os(iOS)
            let date = Date()
            let timestamp = dateToMillis(date)
            if let args = call.arguments as? [String: Any] {
                let width = args["width"] as? Int ?? 0
                let height = args["height"] as? Int ?? 0
                let screen = args["screen"] as? String ?? ""

                if width == 0 || height == 0 {
                    _badArgumentError(result)
                    return
                }

                dispatchQueue.async {
                    var snapshotsData: [Any] = []
                    let data: [String: Any] = ["width": width, "height": height, "href": screen]

                    let snapshotData: [String: Any] = ["type": 4, "data": data, "timestamp": timestamp]
                    snapshotsData.append(snapshotData)

                    PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData], timestamp: date)
                }

                result(nil)
            } else {
                _badArgumentError(result)
            }
        #else
            result(nil)
        #endif
    }

    private func sendFullSnapshot(_ call: FlutterMethodCall,
                                  result: @escaping FlutterResult)
    {
        #if os(iOS)
            let date = Date()
            let timestamp = dateToMillis(date)
            if let args = call.arguments as? [String: Any] {
                let id = args["id"] as? Int ?? 1
                let x = args["x"] as? Int ?? 0
                let y = args["y"] as? Int ?? 0

                guard let imageBytes = args["imageBytes"] as? FlutterStandardTypedData else {
                    _badArgumentError(result)
                    return
                }

                dispatchQueue.async {
                    guard let image = UIImage(data: imageBytes.data) else {
                        // bad data but we cannot do this in the calling thread
                        // otherwise we are doing slow operatios in the main thread
                        return
                    }

                    guard let base64 = imageToBase64(image) else {
                        // bad data but we cannot do this in the calling thread
                        // otherwise we are doing slow operatios in the main thread
                        return
                    }

                    var snapshotsData: [Any] = []
                    var wireframes: [Any] = []

                    let wireframe: [String: Any] = [
                        "id": id,
                        "x": x,
                        "y": y,
                        "width": Int(image.size.width),
                        "height": Int(image.size.height),
                        "type": "screenshot",
                        "base64": base64,
                        "style": [:],
                    ]

                    wireframes.append(wireframe)
                    let initialOffset = ["top": 0, "left": 0]
                    let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
                    let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
                    snapshotsData.append(snapshotData)

                    PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData], timestamp: date)
                }

                result(nil)
            } else {
                _badArgumentError(result)
            }
        #else
            result(nil)
        #endif
    }

    private func isSessionReplayActive(result: @escaping FlutterResult) {
        #if os(iOS)
            result(PostHogSDK.shared.isSessionReplayActive())
        #else
            result(false)
        #endif
    }

    private func startSessionRecording(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        #if os(iOS)
            let resumeCurrent = call.arguments as? Bool ?? true
            PostHogSDK.shared.startSessionRecording(resumeCurrent: resumeCurrent)
            result(nil)
        #else
            result(nil)
        #endif
    }

    private func stopSessionRecording(result: @escaping FlutterResult) {
        #if os(iOS)
            PostHogSDK.shared.stopSessionRecording()
            result(nil)
        #else
            result(nil)
        #endif
    }

    private func openUrl(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let url = call.arguments as? String,
           let urlObject = URL(string: url)
        {
            #if os(iOS)
                if UIApplication.shared.canOpenURL(urlObject) {
                    UIApplication.shared.open(urlObject)
                }
            #else
                NSWorkspace.shared.open(urlObject)
            #endif
            result(nil)
        } else {
            result(FlutterError(code: "InvalidArguments",
                                message: "Invalid URL",
                                details: "The URL provided is invalid"))
        }
    }

    private func setup(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any] {
            PosthogFlutterPlugin.setupPostHog(args)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func getFeatureFlag(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let value = PostHogSDK.shared.getFeatureFlag(featureFlagKey)
            result(value)
        } else {
            _badArgumentError(result)
        }
    }

    private func isFeatureEnabled(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let value = PostHogSDK.shared.isFeatureEnabled(featureFlagKey)
            result(value)
        } else {
            _badArgumentError(result)
        }
    }

    private func getFeatureFlagPayload(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let value = PostHogSDK.shared.getFeatureFlagPayload(featureFlagKey)
            result(value)
        } else {
            _badArgumentError(result)
        }
    }

    private func getFeatureFlagResult(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let sendEvent = args["sendEvent"] as? Bool ?? true
            let flagResult = PostHogSDK.shared.getFeatureFlagResult(featureFlagKey, sendFeatureFlagEvent: sendEvent)

            if let flagResult {
                result([
                    "key": flagResult.key,
                    "enabled": flagResult.enabled,
                    "variant": flagResult.variant as Any,
                    "payload": flagResult.payload as Any,
                ])
            } else {
                result(nil)
            }
        } else {
            _badArgumentError(result)
        }
    }

    private func identify(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let userId = args["userId"] as? String
        {
            let userProperties = args["userProperties"] as? [String: Any]
            let userPropertiesSetOnce = args["userPropertiesSetOnce"] as? [String: Any]

            PostHogSDK.shared.identify(
                userId,
                userProperties: userProperties,
                userPropertiesSetOnce: userPropertiesSetOnce
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func setPersonProperties(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any] {
            let userPropertiesToSet = args["userPropertiesToSet"] as? [String: Any]
            let userPropertiesToSetOnce = args["userPropertiesToSetOnce"] as? [String: Any]

            PostHogSDK.shared.setPersonProperties(
                userPropertiesToSet: userPropertiesToSet,
                userPropertiesToSetOnce: userPropertiesToSetOnce
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func capture(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let eventName = args["eventName"] as? String
        {
            let properties = args["properties"] as? [String: Any]
            let userProperties = args["userProperties"] as? [String: Any]
            let userPropertiesSetOnce = args["userPropertiesSetOnce"] as? [String: Any]
            PostHogSDK.shared.capture(
                eventName,
                properties: properties,
                userProperties: userProperties,
                userPropertiesSetOnce: userPropertiesSetOnce
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func screen(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let screenName = args["screenName"] as? String
        {
            let properties = args["properties"] as? [String: Any]
            PostHogSDK.shared.screen(
                screenName,
                properties: properties
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func captureLog(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let body = args["body"] as? String
        {
            let level = args["level"] as? String ?? "info"
            let attributes = args["attributes"] as? [String: Any]
            let traceId = args["traceId"] as? String
            let spanId = args["spanId"] as? String
            // traceFlags 0 is meaningful (W3C sampled-false); nil omits it.
            let traceFlags = args["traceFlags"] as? Int
            // PostHogLogSeverity.from(name:) is internal in the SDK, so map the
            // wire string here. Unknown levels fall back to .info.
            let severity = severityFromString(level)
            PostHogSDK.shared.captureLog(
                body,
                level: severity,
                attributes: attributes,
                traceId: traceId,
                spanId: spanId,
                traceFlags: traceFlags
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    // Maps the wire level to PostHogLogSeverity using only public enum cases
    // (the SDK's `from(name:)` is internal). Unknown levels fall back to .info.
    private func severityFromString(_ level: String) -> PostHogLogSeverity {
        switch level.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "warn": return .warn
        case "error": return .error
        case "fatal": return .fatal
        default: return .info
        }
    }

    private func alias(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let alias = args["alias"] as? String
        {
            PostHogSDK.shared.alias(alias)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func distinctId(_ result: @escaping FlutterResult) {
        let val = PostHogSDK.shared.getDistinctId()
        result(val)
    }

    private func reset(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.reset()
        result(nil)
    }

    private func enable(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.optIn()
        result(nil)
    }

    private func disable(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.optOut()
        result(nil)
    }

    private func isOptOut(_ result: @escaping FlutterResult) {
        let isOptedOut = PostHogSDK.shared.isOptOut()
        result(isOptedOut)
    }

    private func debug(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let debug = args["debug"] as? Bool
        {
            PostHogSDK.shared.debug(debug)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func reloadFeatureFlags(_ result: @escaping FlutterResult) {
        // Resolve the Dart Future only once flags have actually finished loading.
        // The native callback fires on a background thread, so hop to main for Flutter.
        PostHogSDK.shared.reloadFeatureFlags {
            DispatchQueue.main.async {
                result(nil)
            }
        }
    }

    // reloadFeatureFlags is handled on the Dart side (so the Future resolves only
    // after the awaited reload completes), so we always disable the native reload.
    private func setPersonPropertiesForFlags(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let userProperties = args["userProperties"] as? [String: Any]
        {
            PostHogSDK.shared.setPersonPropertiesForFlags(userProperties, reloadFeatureFlags: false)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func resetPersonPropertiesForFlags(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.resetPersonPropertiesForFlags(reloadFeatureFlags: false)
        result(nil)
    }

    private func setGroupPropertiesForFlags(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let groupType = args["groupType"] as? String,
           let groupProperties = args["groupProperties"] as? [String: Any]
        {
            PostHogSDK.shared.setGroupPropertiesForFlags(groupType, properties: groupProperties, reloadFeatureFlags: false)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func resetGroupPropertiesForFlags(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let groupType = (call.arguments as? [String: Any])?["groupType"] as? String
        if let groupType = groupType {
            PostHogSDK.shared.resetGroupPropertiesForFlags(groupType, reloadFeatureFlags: false)
        } else {
            PostHogSDK.shared.resetGroupPropertiesForFlags(reloadFeatureFlags: false)
        }
        result(nil)
    }

    private func group(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let groupType = args["groupType"] as? String,
           let groupKey = args["groupKey"] as? String
        {
            let groupProperties = args["groupProperties"] as? [String: Any]
            PostHogSDK.shared.group(type: groupType, key: groupKey, groupProperties: groupProperties)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func register(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String,
           let value = args["value"]
        {
            PostHogSDK.shared.register([key: value])
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func unregister(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String
        {
            PostHogSDK.shared.unregister(key)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func flush(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.flush()
        result(nil)
    }

    private func captureException(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for captureException", details: nil))
            return
        }

        let properties = arguments["properties"] as? [String: Any]

        // Extract timestamp from Flutter and convert to Date
        var timestamp: Date? = nil
        if let timestampMs = arguments["timestamp"] as? Int64 {
            timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
        }

        // Use capture method with timestamp to ensure Flutter timestamp is used
        PostHogSDK.shared.capture("$exception", properties: properties, timestamp: timestamp)
        result(nil)
    }

    private func addExceptionStep(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let message = arguments["message"] as? String
        else {
            _badArgumentError(result)
            return
        }

        let properties = arguments["properties"] as? [String: Any]
        PostHogSDK.shared.addExceptionStep(message, properties: properties)
        result(nil)
    }

    private func close(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.close()
        result(nil)
    }

    private func getSessionId(result: @escaping FlutterResult) {
        result(PostHogSDK.shared.getSessionId())
    }

    // Return bad Arguments error
    private func _badArgumentError(_ result: @escaping FlutterResult) {
        result(FlutterError(
            code: "PosthogFlutterException", message: "Missing arguments!", details: nil
        ))
    }

    private func invokeFlutterMethod(_ method: String, arguments: Any? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(method, arguments: arguments)
        }
    }
}
