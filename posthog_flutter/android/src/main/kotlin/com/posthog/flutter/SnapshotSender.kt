package com.posthog.flutter

import android.graphics.BitmapFactory
import com.posthog.android.internal.base64
import com.posthog.internal.replay.RREvent
import com.posthog.internal.replay.RRFullSnapshotEvent
import com.posthog.internal.replay.RRMetaEvent
import com.posthog.internal.replay.RRStyle
import com.posthog.internal.replay.RRWireframe
import com.posthog.internal.replay.capture

class SnapshotSender(
    private val currentTimeMillis: () -> Long = { System.currentTimeMillis() },
) {
    fun sendFullSnapshot(
        imageBytes: ByteArray,
        id: Int,
        x: Int,
        y: Int,
        timestampMs: Long = currentTimeMillis(),
    ) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val base64String = bitmap.base64()

        val wireframe =
            RRWireframe(
                id = id,
                x = x,
                y = y,
                width = bitmap.width,
                height = bitmap.height,
                type = "screenshot",
                base64 = base64String,
                style = RRStyle(),
            )

        val snapshotEvent =
            RRFullSnapshotEvent(
                listOf(wireframe),
                initialOffsetTop = 0,
                initialOffsetLeft = 0,
                timestamp = timestampMs,
            )

        listOf(snapshotEvent).capture()
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
