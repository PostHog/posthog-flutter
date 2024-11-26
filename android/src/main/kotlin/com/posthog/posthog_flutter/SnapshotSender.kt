package com.posthog.posthog_flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import com.posthog.internal.replay.RREvent
import com.posthog.internal.replay.RRFullSnapshotEvent
import com.posthog.internal.replay.RRMetaEvent
import com.posthog.internal.replay.RRStyle
import com.posthog.internal.replay.RRWireframe
import com.posthog.internal.replay.capture
import java.io.ByteArrayOutputStream

class SnapshotSender {
    fun sendFullSnapshot(
        imageBytes: ByteArray,
        id: Int,
        x: Int,
        y: Int,
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
                timestamp = System.currentTimeMillis(),
            )

        listOf(snapshotEvent).capture()
    }

    fun sendMetaEvent(
        width: Int,
        height: Int,
    ) {
        val metaEvent =
            RRMetaEvent(
                href = "", // TODO: get href from flutter
                width = width,
                height = height,
                timestamp = System.currentTimeMillis(),
            )

        val events = mutableListOf<RREvent>()
        events.add(metaEvent)

        events.capture()
    }

    // TODO: reuse from Android
    private fun Bitmap.isValid(): Boolean =
        !isRecycled &&
            width > 0 &&
            height > 0

    // TODO: reuse from Android
    private fun Bitmap.base64(): String? {
        if (!isValid()) {
            return null
        }

        ByteArrayOutputStream(allocationByteCount).use {
            // we can make format and type configurable
            compress(Bitmap.CompressFormat.JPEG, 30, it)
            val byteArray = it.toByteArray()
            val encoded = Base64.encodeToString(byteArray, Base64.DEFAULT) ?: return null
            return "data:image/jpeg;base64,$encoded"
        }
    }
}
