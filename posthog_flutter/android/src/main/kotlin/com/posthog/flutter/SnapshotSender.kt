package com.posthog.flutter

import android.graphics.BitmapFactory
import com.posthog.PostHog
import com.posthog.android.internal.base64
import com.posthog.internal.replay.RREvent
import com.posthog.internal.replay.RRFullSnapshotEvent
import com.posthog.internal.replay.RRMetaEvent
import com.posthog.internal.replay.RRStyle
import com.posthog.internal.replay.RRWireframe

class SnapshotSender(
    private val currentTimeMillis: () -> Long = { System.currentTimeMillis() },
) {
    fun sendFullSnapshot(
        imageBytes: ByteArray,
        id: Int,
        x: Int,
        y: Int,
        timestampMs: Long = currentTimeMillis(),
        sessionId: String? = null,
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

        capture(listOf(snapshotEvent), sessionId)
    }

    fun sendMetaEvent(
        width: Int,
        height: Int,
        screen: String,
        timestampMs: Long = currentTimeMillis(),
        sessionId: String? = null,
    ) {
        val events = mutableListOf<RREvent>()
        events.add(buildMetaEvent(width, height, screen, timestampMs))

        capture(events, sessionId)
    }

    // Not RRUtils' List<RREvent>.capture(): that helper cannot carry extra
    // properties, and pre-attaching the session id is what keeps a frame in the
    // session it was captured under — PostHog.capture prefers a supplied
    // $session_id over resolving one itself. See NATIVE_BEHAVIOR.md.
    private fun capture(
        events: List<RREvent>,
        sessionId: String?,
    ) {
        val properties =
            mutableMapOf<String, Any>(
                "\$snapshot_data" to events,
                "\$snapshot_source" to "mobile",
            )
        sessionId?.takeIf { it.isNotBlank() }?.let { properties["\$session_id"] = it }
        PostHog.capture("\$snapshot", properties = properties)
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
