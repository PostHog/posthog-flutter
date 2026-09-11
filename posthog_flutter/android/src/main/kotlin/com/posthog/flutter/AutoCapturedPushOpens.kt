package com.posthog.flutter

import org.json.JSONObject

/**
 * The notification taps the plugin captured automatically, keyed on the `posthog` entry that
 * every PostHog-sent push carries: `invocation_id` names the workflow run and `action_id` the step
 * in it, so two pushes from one run differ only by step.
 *
 * Apps that followed the pre-5.40.0 docs still call `capturePushNotificationOpened` from
 * `FirebaseMessaging.onMessageOpenedApp`, and that call would count the same tap a second time.
 * A push without an `invocation_id` cannot be matched, so its manual capture goes through unchanged.
 *
 * A match does not consume the entry: `firebase_messaging` reports a cold-start tap to both
 * `onMessageOpenedApp` and `getInitialMessage()`, so one tap can face two manual calls.
 *
 * Main-thread confined: the tap listener and the method channel both run there.
 */
internal class AutoCapturedPushOpens(
    private val capacity: Int = 20,
) {
    private val keys = LinkedHashSet<String>()

    fun remember(posthogEntry: Any?) {
        val key = key(posthogEntry) ?: return
        if (keys.add(key) && keys.size > capacity) {
            keys.remove(keys.first())
        }
    }

    operator fun contains(posthogEntry: Any?): Boolean = key(posthogEntry)?.let { it in keys } == true

    // FCM data values are strings, so the entry is usually JSON; a caller may also pass a map.
    private fun key(posthogEntry: Any?): String? =
        try {
            val (invocationId, actionId) =
                when (posthogEntry) {
                    is Map<*, *> -> posthogEntry["invocation_id"] to posthogEntry["action_id"]
                    is String -> JSONObject(posthogEntry).let { it.opt("invocation_id") to it.opt("action_id") }
                    else -> return null
                }
            (invocationId as? String)?.takeIf { it.isNotEmpty() }?.let { "$it/${actionId as? String ?: ""}" }
        } catch (e: Throwable) {
            null
        }
}
