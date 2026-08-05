package com.google.firebase

/**
 * Test stub for PosthogFlutterPlugin's reflective Firebase lookup. Mirrors real
 * Firebase: getInstance() throws until [projectId] is set.
 */
class FirebaseApp private constructor() {
    fun getOptions(): FirebaseOptions = FirebaseOptions(checkNotNull(projectId))

    companion object {
        @JvmStatic
        var projectId: String? = null

        @JvmStatic
        fun getInstance(): FirebaseApp {
            check(projectId != null) { "Default FirebaseApp is not initialized" }
            return FirebaseApp()
        }
    }
}

class FirebaseOptions(
    private val id: String,
) {
    fun getProjectId(): String = id
}
