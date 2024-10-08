package com.posthog.posthog_flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.posthog.internal.replay.*
import java.io.ByteArrayOutputStream

/*
* TEMPORARY CLASS FOR TESTING PURPOSES
* This function sends a screenshot to PostHog.
* It should be removed or refactored in the other version.
*/
class SnapshotSender {

    fun sendFullSnapshot(imageBytes: ByteArray, id: Int = 1) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val base64String = bitmapToBase64(bitmap)

        val wireframe = RRWireframe(
            id = id,
            x = 0,
            y = 0,
            width = bitmap.width,
            height = bitmap.height,
            type = "screenshot",
            base64 = base64String,
            style = RRStyle()
        )

        val snapshotEvent = RRFullSnapshotEvent(
            listOf(wireframe),
            initialOffsetTop = 0,
            initialOffsetLeft = 0,
            timestamp = System.currentTimeMillis()
        )

        Log.d("Snapshot", "Sending Full Snapshot")
        listOf(snapshotEvent).capture()
    }

    fun sendIncrementalSnapshot(imageBytes: ByteArray, id: Int = 1) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val base64String = bitmapToBase64(bitmap)

        val wireframe = RRWireframe(
            id = id,
            x = 0,
            y = 0,
            width = bitmap.width,
            height = bitmap.height,
            type = "screenshot",
            base64 = base64String,
            style = RRStyle()
        )

        val mutatedNode = RRMutatedNode(wireframe, parentId = null)
        val updatedNodes = listOf(mutatedNode)

        val incrementalMutationData = RRIncrementalMutationData(
            adds = null,
            removes = null,
            updates = updatedNodes
        )

        val incrementalSnapshotEvent = RRIncrementalSnapshotEvent(
            mutationData = incrementalMutationData,
            timestamp = System.currentTimeMillis()
        )

        Log.d("Snapshot", "Sending Incremental Snapshot")
        listOf(incrementalSnapshotEvent).capture()
    }

    private fun bitmapToBase64(bitmap: Bitmap): String? {
        ByteArrayOutputStream().use { byteArrayOutputStream ->
            bitmap.compress(
                Bitmap.CompressFormat.JPEG,
                30,
                byteArrayOutputStream
            )
            val byteArray = byteArrayOutputStream.toByteArray()
            return android.util.Base64.encodeToString(byteArray, android.util.Base64.NO_WRAP)
        }
    }
}
