package com.posthog.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class PosthogFlutterPluginTest {
    @Test
    fun onMethodCall_identify_returnsExpectedValue() {
        val plugin = PosthogFlutterPlugin()

        var arguments = mapOf("userId" to "abc")

        val call = MethodCall("identify", arguments)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_alias_returnsExpectedValue() {
        val plugin = PosthogFlutterPlugin()

        var arguments = mapOf("alias" to "abc")

        val call = MethodCall("alias", arguments)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(true)
    }
}
