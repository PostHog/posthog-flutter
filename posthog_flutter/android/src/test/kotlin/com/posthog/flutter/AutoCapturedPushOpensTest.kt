package com.posthog.flutter

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class AutoCapturedPushOpensTest {
    private val fcmEntry = """{"workflow_id":"wf","invocation_id":"inv-1","action_id":"a"}"""

    @Test
    fun matchesAJsonEntryRememberedFromTheIntent() {
        val opens = AutoCapturedPushOpens()

        opens.remember(fcmEntry)

        assertTrue(fcmEntry in opens)
    }

    @Test
    fun matchesAMapEntryByInvocationId() {
        val opens = AutoCapturedPushOpens()

        opens.remember(fcmEntry)

        assertTrue(mapOf("workflow_id" to "other", "invocation_id" to "inv-1") in opens)
    }

    @Test
    fun doesNotMatchADifferentInvocationId() {
        val opens = AutoCapturedPushOpens()

        opens.remember(fcmEntry)

        assertFalse("""{"invocation_id":"inv-2"}""" in opens)
    }

    @Test
    fun ignoresEntriesWithoutAnInvocationId() {
        val opens = AutoCapturedPushOpens()

        listOf(null, "", "not json", "[]", """{"invocation_id":null}""", """{"invocation_id":""}""", 42)
            .forEach { opens.remember(it) }

        listOf(null, "", "not json", "[]", """{"invocation_id":null}""", """{"invocation_id":""}""", 42, emptyMap<String, Any>())
            .forEach { assertFalse(it in opens) }
    }

    @Test
    fun forgetsTheOldestIdPastCapacity() {
        val opens = AutoCapturedPushOpens(capacity = 2)

        listOf("a", "b", "c").forEach { opens.remember(mapOf("invocation_id" to it)) }

        assertFalse(mapOf("invocation_id" to "a") in opens)
        assertTrue(mapOf("invocation_id" to "b") in opens)
        assertTrue(mapOf("invocation_id" to "c") in opens)
    }
}
