package com.example.flutter

/**
 * Helper class to trigger a native crash for testing error tracking.
 * This class and its methods will be minified by R8/ProGuard in release builds,
 * allowing us to verify that symbolication (ProGuard mapping upload) works correctly.
 */
class NativeCrashHelper {
    fun triggerCrash() {
        throw RuntimeException("Test native crash from PostHog Flutter example")
    }
}
