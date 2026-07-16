pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// Local development against an unreleased posthog-android. Inert unless a
// gitignored local.settings.gradle.kts exists; see CONTRIBUTING.md. The name must
// end in .settings.gradle.kts so Kotlin DSL compiles it against Settings.
val localSettings = file("local.settings.gradle.kts")
if (localSettings.exists()) apply(from = localSettings)
