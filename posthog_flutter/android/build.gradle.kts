group = "com.posthog.flutter"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        // KGP not needed: AGP 9 provides Built-in Kotlin support by default.
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.posthog.flutter"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.setSrcDirs(listOf("src/main/kotlin"))
        }
        getByName("test") {
            java.setSrcDirs(listOf("src/test/kotlin"))
        }
    }

    defaultConfig {
        minSdk = 21
    }

    dependencies {
        testImplementation("org.jetbrains.kotlin:kotlin-test")
        testImplementation("org.mockito:mockito-core:5.0.0")
        // Version 3.51.0 up to (but not including) 4.0.0
        implementation("com.posthog:posthog-android:[3.51.0,4.0.0]")
    }

    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
            it.outputs.upToDateWhen { false }

            it.testLogging {
                events("passed", "skipped", "failed", "standardOut", "standardError")
                showStandardStreams = true
            }
        }
    }
}
