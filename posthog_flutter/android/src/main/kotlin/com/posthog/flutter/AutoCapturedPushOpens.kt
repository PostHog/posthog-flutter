package com.posthog.flutter

import org.json.JSONObject

/**
 * Invocation ids of the notification taps the plugin captured automatically, keyed on the
 * `invocation_id` inside the `posthog` entry that every PostHog-sent push carries.
 *
 * Apps that followed the pre-5.40.0 docs still call `capturePushNotificationOpened` from
 * `FirebaseMessaging.onMessageOpenedApp`, and that call would count the same tap a second time.
 * A push without that entry cannot be matched, so its manual capture goes through unchanged.
 *
 * Main-thread confined: the tap listener and the method channel both run there.
 */
internal class AutoCapturedPushOpens(
    private val capacity: Int = 20,
) {
    private val invocationIds = LinkedHashSet<String>()

    fun remember(posthogEntry: Any?) {
        val id = invocationId(posthogEntry) ?: return
        if (invocationIds.add(id) && invocationIds.size > capacity) {
            invocationIds.remove(invocationIds.first())
        }
    }

    operator fun contains(posthogEntry: Any?): Boolean = invocationId(posthogEntry)?.let { it in invocationIds } == true

    // FCM data values are strings, so the entry is usually JSON; a caller may also pass a map.
    private fun invocationId(posthogEntry: Any?): String? =
        try {
            when (posthogEntry) {
                is Map<*, *> -> posthogEntry["invocation_id"] as? String
                is String -> JSONObject(posthogEntry).opt("invocation_id") as? String
                else -> null
            }?.takeIf { it.isNotEmpty() }
        } catch (e: Throwable) {
            null
        }
}
