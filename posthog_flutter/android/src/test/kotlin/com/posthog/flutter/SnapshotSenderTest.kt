package com.posthog.flutter

import com.posthog.PostHogEventName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class SnapshotSenderTest {
    @Test
    fun buildMetaEvent_stampsWithTheInjectedClock() {
        val sender = SnapshotSender(currentTimeMillis = { 1234L })

        val metaEvent = sender.buildMetaEvent(width = 10, height = 20, screen = "Home")

        assertEquals(1234L, metaEvent.timestamp)
        val data = metaEvent.data as Map<*, *>
        assertEquals(10, data["width"])
        assertEquals(20, data["height"])
        assertEquals("Home", data["href"])
    }

    @Test
    fun buildMetaEvent_prefersAnExplicitTimestamp() {
        val sender = SnapshotSender(currentTimeMillis = { 1234L })

        val metaEvent = sender.buildMetaEvent(width = 1, height = 2, screen = "s", timestampMs = 99L)

        assertEquals(99L, metaEvent.timestamp)
    }

    @Test
    fun buildSnapshotProperties_attachesTheSessionId() {
        // PostHog.capture prefers a supplied id over resolving one itself, which is
        // what keeps the frame in the session it was captured under.
        val sender = SnapshotSender()
        val events = listOf(sender.buildMetaEvent(width = 1, height = 2, screen = "Home"))

        val properties = sender.buildSnapshotProperties(events, "session-a")

        assertEquals("session-a", properties["\$session_id"])
        assertEquals("mobile", properties["\$snapshot_source"])
        assertEquals(events, properties["\$snapshot_data"])
    }

    @Test
    fun buildSnapshotProperties_omitsABlankSessionId() {
        // Omitted rather than sent blank, so this does not lean on native's own
        // isNotBlank fallback (PostHog.kt:680 at android-v3.58.0).
        val sender = SnapshotSender()
        val events = listOf(sender.buildMetaEvent(width = 1, height = 2, screen = "Home"))

        assertNull(sender.buildSnapshotProperties(events, null)["\$session_id"])
        assertNull(sender.buildSnapshotProperties(events, "   ")["\$session_id"])
    }

    @Test
    fun sendMetaEvent_capturesWithThePreAttachedSessionId() {
        val captured = mutableListOf<Pair<String, Map<String, Any>>>()
        val sender =
            SnapshotSender(
                currentTimeMillis = { 1L },
                capture = { event, properties -> captured += event to properties },
            )

        sender.sendMetaEvent(width = 1, height = 2, screen = "Home", sessionId = "session-a")

        assertEquals(1, captured.size)
        assertEquals(PostHogEventName.SNAPSHOT.event, captured[0].first)
        assertEquals("session-a", captured[0].second["\$session_id"])
    }
}
