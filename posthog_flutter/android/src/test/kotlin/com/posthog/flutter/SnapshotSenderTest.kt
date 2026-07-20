package com.posthog.flutter

import kotlin.test.Test
import kotlin.test.assertEquals

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
}
