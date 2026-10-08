plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from the environment, never from a file in the repo:
// the release workflow decodes the keystore secret to a temporary file and
// sets ANDROID_KEYSTORE_PATH (an absolute path; a relative one starts in
// android/app) with ANDROID_KEYSTORE_PASSWORD, and optionally
// ANDROID_KEY_ALIAS (default "release"). The keystore is PKCS12, so the key
// password equals the store password. Without ANDROID_KEYSTORE_PATH (normal
// dev and CI builds) the release type is signed with the debug key as before.
// Android only installs an update that is signed with the same key as the
// installed app, so this key must stay the same for the life of the app.
// Error messages below name variables only; secret values are never printed.
val releaseKeystorePath: String? =
    System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val releaseKeystorePassword: String? =
    System.getenv("ANDROID_KEYSTORE_PASSWORD")?.takeIf { it.isNotEmpty() }
val releaseKeyAlias: String =
    System.getenv("ANDROID_KEY_ALIAS")?.takeIf { it.isNotBlank() } ?: "release"

android {
    namespace = "app.hisn.hisn"
    // receive_sharing_intent requires compiling against API 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.hisn.hisn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // AutofillService and its Dataset APIs require Android 8.0 (API 26).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // A keystore was asked for: a missing file or password must fail the
        // build. Silently falling back to the debug key would produce an APK
        // that installed copies of the app refuse as an update.
        releaseKeystorePath?.let { keystorePath ->
            val keystorePassword = releaseKeystorePassword
                ?: throw GradleException(
                    "ANDROID_KEYSTORE_PATH is set but ANDROID_KEYSTORE_PASSWORD is empty"
                )
            val keystoreFile = file(keystorePath)
            if (!keystoreFile.isFile) {
                throw GradleException("ANDROID_KEYSTORE_PATH does not point to a file")
            }
            create("release") {
                storeFile = keystoreFile
                storePassword = keystorePassword
                keyAlias = releaseKeyAlias
                // PKCS12 keystores use one password for the store and the key.
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            // Stable release key when the environment provides one; otherwise the
            // debug key, so `flutter run --release` and the dev CI build keep working.
            signingConfig =
                if (releaseKeystorePath != null) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
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
