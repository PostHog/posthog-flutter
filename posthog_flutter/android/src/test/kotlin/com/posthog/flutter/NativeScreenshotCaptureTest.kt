package com.posthog.flutter

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.fail

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28], shadows = [NativeScreenshotCaptureTest.ShadowPixelCopy::class])
internal class NativeScreenshotCaptureTest {
    // Copies succeed until the window loses its surface, then PixelCopy throws
    // synchronously, as Android does when the app goes to the background.
    @Implements(PixelCopy::class)
    class ShadowPixelCopy {
        companion object {
            var successfulCopiesBeforeSurfaceLoss = Int.MAX_VALUE
            var requests = 0

            @JvmStatic
            @Implementation
            fun request(
                source: Window,
                srcRect: Rect?,
                dest: Bitmap,
                listener: PixelCopy.OnPixelCopyFinishedListener,
                listenerThread: Handler,
            ) {
                if (requests++ >= successfulCopiesBeforeSurfaceLoss) {
                    throw IllegalArgumentException("Window doesn't have a backing surface!")
                }
                listenerThread.post { listener.onPixelCopyFinished(PixelCopy.SUCCESS) }
            }
        }
    }

    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
        var replied = false

        override fun success(result: Any?) {
            successValue = result
            replied = true
        }

        override fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?,
        ) {
            fail("Expected per-view nulls, got error $errorCode: $errorMessage")
        }

        override fun notImplemented() {
            fail("captureNativeScreenshots is implemented")
        }
    }

    @Before
    fun resetShadow() {
        ShadowPixelCopy.successfulCopiesBeforeSurfaceLoss = Int.MAX_VALUE
        ShadowPixelCopy.requests = 0
    }

    private fun captureTwoViews(): List<*> {
        val plugin = PosthogFlutterPlugin()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val binding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(activity)
        plugin.onAttachedToActivity(binding)

        val view = mapOf("x" to 0, "y" to 0, "width" to 10, "height" to 10)
        val result = RecordingResult()
        plugin.onMethodCall(MethodCall("captureNativeScreenshots", mapOf("views" to listOf(view, view))), result)

        // Each capture hands its bitmap to a background executor, then continues on the main looper.
        val deadline = System.currentTimeMillis() + 5_000
        while (!result.replied && System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        assertEquals(true, result.replied, "captureNativeScreenshots never replied")
        return result.successValue as List<*>
    }

    @Test
    fun captureNativeScreenshots_capturesEveryView() {
        val screenshots = captureTwoViews()

        assertEquals(2, screenshots.size)
        assertNotNull(screenshots[0])
        assertNotNull(screenshots[1])
    }

    // The second view is captured from the first one's callback, outside
    // onMethodCall, so a throw there used to reach the main looper and crash the app.
    @Test
    fun captureNativeScreenshots_surfaceLostAfterFirstView_returnsNullForTheRest() {
        ShadowPixelCopy.successfulCopiesBeforeSurfaceLoss = 1

        val screenshots = captureTwoViews()

        assertEquals(2, screenshots.size)
        assertNotNull(screenshots[0])
        assertNull(screenshots[1])
    }

    @Test
    fun captureNativeScreenshots_surfaceLostBeforeFirstView_returnsNullForEveryView() {
        ShadowPixelCopy.successfulCopiesBeforeSurfaceLoss = 0

        assertEquals(listOf(null, null), captureTwoViews())
    }
}
