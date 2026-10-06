allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// file_picker 11.x skips the Kotlin Gradle plugin on AGP 9+, expecting AGP's built-in Kotlin to
// compile its sources. This project keeps android.builtInKotlin=false (biometric_storage 5.x still
// applies kotlin-android/kotlin-kapt, which is fatal with built-in Kotlin), and Flutter's automatic
// kotlin-android fallback skips file_picker because its build.gradle textually contains
// `apply plugin: 'org.jetbrains.kotlin.android'`. Without this, none of file_picker's Kotlin is
// compiled and GeneratedPluginRegistrant cannot find FilePickerPlugin. Remove once file_picker is
// upgraded to 12+ (its android_file_picker honours android.builtInKotlin itself).
subprojects {
    if (project.name == "file_picker") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                // Match file_picker's Java 17 compileOptions (and its own pre-AGP-9 kotlinOptions);
                // KGP would otherwise default to the Gradle JDK version and fail JVM-target validation on JDK 21.
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}
// Some plugins compile against old SDKs (biometric_storage 5.x uses compileSdk 31) while their
// AndroidX dependencies require 33+, which fails :<plugin>:checkReleaseAarMetadata. Raise every
// Android library module to at least 36. This only changes the SDK the plugin is compiled
// against, not minSdk/targetSdk. Registered before evaluationDependsOn below so it runs before
// AGP finalizes each plugin's DSL in its own afterEvaluate.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { android ->
            val current = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current < 36) android.compileSdkVersion(36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
