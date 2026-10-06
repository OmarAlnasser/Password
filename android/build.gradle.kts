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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
