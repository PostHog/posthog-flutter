package com.example.flutter

/**
 * Custom exception type for testing error tracking symbolication.
 * This class will be minified by R8/ProGuard in release builds,
 * allowing us to verify that symbolication (ProGuard mapping upload) works correctly.
 */
class PostHogExampleException(message: String) : Exception(message)

/**
 * Helper class to trigger a native crash for testing error tracking.
 * This class and its methods will be minified by R8/ProGuard in release builds,
 * allowing us to verify that symbolication (ProGuard mapping upload) works correctly.
 */
class NativeCrashHelper {
    fun triggerCrash() {
        // Crash on a background thread because Flutter wraps and
        // swallows exceptions from the method channel handler as
        // a PlatformException, preventing the app from actually crashing.
        Thread {
            throw PostHogExampleException("Test native crash from PostHog Flutter example")
        }.start()
    }
}
