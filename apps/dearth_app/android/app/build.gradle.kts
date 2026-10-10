import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (SPEC §15.1): android/key.properties (never committed) or the
// DEARTH_KEYSTORE* environment variables in CI. Without either, release builds
// fall back to the debug key so they still install for testing.
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? = keystoreProps.getProperty(prop) ?: System.getenv(env)

android {
    namespace = "app.dearth"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Fixed before the first install on a frame: FreeKiosk targets it (PROGRESS 2026-10-02).
        applicationId = "app.dearth"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        val storeFile = signingValue("storeFile", "DEARTH_KEYSTORE_PATH")
        if (storeFile != null) {
            create("release") {
                this.storeFile = file(storeFile)
                storePassword = signingValue("storePassword", "DEARTH_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "DEARTH_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "DEARTH_KEY_PASSWORD")
            }
        }
    }

    // Profile builds too: tool/perf_gate.sh installs its scenarios over the
    // display's Dearth, which takes the same key. Releases update themselves
    // in place (SPEC §15.3), so every build a display runs shares one key.
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
        findByName("profile")?.signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
