group = "com.posthog.flutter"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.0.0"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
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

val agpVersion = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
val agpMajor = agpVersion.split(".")[0].toInt()
if (agpMajor < 9) {
    apply(plugin = "kotlin-android")
} else {
    // AGP 9 enables built-in Kotlin by default. Flutter templates can explicitly opt out
    // with android.builtInKotlin=false, in which case we still apply kotlin-android.
    val builtInKotlin = providers.gradleProperty("android.builtInKotlin")
        .map { it.toBoolean() }
        .getOrElse(true)
    if (!builtInKotlin) {
        apply(plugin = "kotlin-android")
    }
}

val flutterCompileSdkVersion: Int = try {
    val flutter = project.extensions.findByName("flutter")
    val getCompileSdkVersion = flutter?.javaClass?.getMethod("getCompileSdkVersion")
    (getCompileSdkVersion?.invoke(flutter) as? Number)?.toInt() ?: 35
} catch (e: Exception) {
    35
}

android {
    namespace = "com.posthog.flutter"
    compileSdk = flutterCompileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    sourceSets {
        getByName("main") {
            java.srcDir("src/main/kotlin")
        }
        getByName("test") {
            java.srcDir("src/test/kotlin")
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

tasks.configureEach {
    if (name.contains("Kotlin")) {
        try {
            // Modern Kotlin compiler options (KGP >= 2.0.0)
            val compilerOptions = this.javaClass.getMethod("getCompilerOptions").invoke(this)
            val jvmTarget = compilerOptions.javaClass.getMethod("getJvmTarget")
            val jvmTargetEnum = Class.forName("org.jetbrains.kotlin.gradle.dsl.JvmTarget").getField("JVM_1_8").get(null)
            jvmTarget.javaClass.getMethod("set", jvmTargetEnum.javaClass).invoke(jvmTarget, jvmTargetEnum)
        } catch (e: Exception) {
            try {
                // Legacy kotlinOptions (KGP < 2.0.0)
                val kotlinOptions = this.javaClass.getMethod("getKotlinOptions").invoke(this)
                kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java).invoke(kotlinOptions, "1.8")
            } catch (ex: Exception) {
                // Fail-safe fallback if Kotlin is not applied or has different structure
            }
        }
    }
}
