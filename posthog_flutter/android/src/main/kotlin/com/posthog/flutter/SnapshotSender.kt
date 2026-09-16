package com.posthog.flutter

import android.graphics.BitmapFactory
import com.posthog.android.internal.base64
import com.posthog.internal.replay.RREvent
import com.posthog.internal.replay.RRFullSnapshotEvent
import com.posthog.internal.replay.RRMetaEvent
import com.posthog.internal.replay.RRStyle
import com.posthog.internal.replay.RRWireframe
import com.posthog.internal.replay.capture

internal const val DEFAULT_SCREENSHOT_COMPRESSION_QUALITY = 30

class SnapshotSender(
    private val currentTimeMillis: () -> Long = { System.currentTimeMillis() },
) {
    fun sendFullSnapshot(
        imageBytes: ByteArray,
        id: Int,
        x: Int,
        y: Int,
        timestampMs: Long = currentTimeMillis(),
        width: Int? = null,
        height: Int? = null,
        quality: Int = DEFAULT_SCREENSHOT_COMPRESSION_QUALITY,
    ) {
        listOf(buildFullSnapshot(imageBytes, id, x, y, timestampMs, width, height, quality)).capture()
    }

    internal fun buildFullSnapshot(
        imageBytes: ByteArray,
        id: Int,
        x: Int,
        y: Int,
        timestampMs: Long = currentTimeMillis(),
        width: Int? = null,
        height: Int? = null,
        quality: Int = DEFAULT_SCREENSHOT_COMPRESSION_QUALITY,
    ): RRFullSnapshotEvent {
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size))
        try {
            val wireframe =
                RRWireframe(
                    id = id,
                    x = x,
                    y = y,
                    width = width ?: bitmap.width,
                    height = height ?: bitmap.height,
                    type = "screenshot",
                    base64 = bitmap.base64(quality = quality),
                    style = RRStyle(),
                )
            return RRFullSnapshotEvent(
                listOf(wireframe),
                initialOffsetTop = 0,
                initialOffsetLeft = 0,
                timestamp = timestampMs,
            )
        } finally {
            bitmap.recycle()
        }
    }

    fun sendMetaEvent(
        width: Int,
        height: Int,
        screen: String,
        timestampMs: Long = currentTimeMillis(),
    ) {
        val events = mutableListOf<RREvent>()
        events.add(buildMetaEvent(width, height, screen, timestampMs))

        events.capture()
    }

    internal fun buildMetaEvent(
        width: Int,
        height: Int,
        screen: String,
        timestampMs: Long = currentTimeMillis(),
    ): RRMetaEvent =
        RRMetaEvent(
            href = screen,
            width = width,
            height = height,
            timestamp = timestampMs,
        )
}
