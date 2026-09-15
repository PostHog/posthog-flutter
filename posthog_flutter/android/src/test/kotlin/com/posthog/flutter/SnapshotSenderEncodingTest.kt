package com.posthog.flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.util.Base64
import com.posthog.android.internal.base64
import com.posthog.internal.replay.RRFullSnapshotEvent
import com.posthog.internal.replay.RRWireframe
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayOutputStream
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SnapshotSenderEncodingTest {
    private fun png(withAlpha: Boolean = false): ByteArray {
        val bitmap = Bitmap.createBitmap(51, 50, Bitmap.Config.ARGB_8888)
        try {
            for (y in 0 until bitmap.height) {
                for (x in 0 until bitmap.width) {
                    bitmap.setPixel(x, y, Color.rgb((x * 17 + y * 11) % 256, (x * 3 + y * 19) % 256, (x * 23 + y * 5) % 256))
                }
            }
            if (withAlpha) {
                bitmap.setPixel(0, 0, Color.argb(80, 255, 100, 50))
            } else {
                bitmap.setHasAlpha(false)
            }
            return ByteArrayOutputStream().use {
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                it.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun wireframe(event: RRFullSnapshotEvent): RRWireframe {
        val data = event.data as Map<*, *>
        return (data["wireframes"] as List<*>).single() as RRWireframe
    }

    @Test
    fun defaultsPreserveLegacyJpegBytesDimensionsAndClock() {
        val bytes = png()
        val decoded = assertNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        try {
            val event = SnapshotSender { 1234L }.buildFullSnapshot(bytes, id = 7, x = 11, y = 13)
            val frame = wireframe(event)
            assertEquals(1234L, event.timestamp)
            assertEquals(7, frame.id)
            assertEquals(11, frame.x)
            assertEquals(13, frame.y)
            assertEquals(51, frame.width)
            assertEquals(50, frame.height)
            assertEquals(decoded.base64(), frame.base64)
            assertTrue(assertNotNull(frame.base64).startsWith("data:image/jpeg;base64,"))
        } finally {
            decoded.recycle()
        }
    }

    @Test
    fun jpegQualityChangesEncodingWithoutChangingLogicalOrRasterDimensions() {
        val bytes = png()
        val decoded = assertNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        val encodedSizes = mutableMapOf<Int, Int>()
        try {
            for (quality in listOf(0, 30, 100)) {
                val event =
                    SnapshotSender { 1234L }.buildFullSnapshot(
                        bytes,
                        id = 7,
                        x = 11,
                        y = 13,
                        timestampMs = 99L,
                        width = 101,
                        height = 99,
                        quality = quality,
                    )
                val frame = wireframe(event)
                assertEquals(99L, event.timestamp)
                assertEquals(101, frame.width)
                assertEquals(99, frame.height)
                val dataUri = assertNotNull(frame.base64)
                assertEquals(decoded.base64(quality = quality), dataUri)
                val jpeg = Base64.decode(dataUri.substringAfter(','), Base64.DEFAULT)
                encodedSizes[quality] = jpeg.size
                val image = assertNotNull(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
                try {
                    assertEquals(51, image.width)
                    assertEquals(50, image.height)
                } finally {
                    image.recycle()
                }
            }
            assertTrue(encodedSizes.getValue(100) > encodedSizes.getValue(0))
        } finally {
            decoded.recycle()
        }
    }

    @Test
    fun alphaPngPreservesLegacyJpegEncoding() {
        val bytes = png(withAlpha = true)
        val decoded = assertNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        try {
            assertTrue(decoded.hasAlpha())
            val frame =
                wireframe(
                    SnapshotSender().buildFullSnapshot(
                        bytes,
                        id = 1,
                        x = 0,
                        y = 0,
                        quality = 100,
                    ),
                )
            assertEquals(decoded.base64(quality = 100), frame.base64)
        } finally {
            decoded.recycle()
        }
    }
}
