import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.z4yed.typed"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.z4yed.typed"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // On-device voice-memo shaper (llama.cpp). Only 64-bit ABIs: phones
        // and the x86_64 emulator. 32-bit installs simply don't offer it.
        externalNativeBuild {
            cmake {
                // Build only for what `flutter build --target-platform`
                // asked for, so a phone APK doesn't carry the emulator's lib.
                val requested = (project.findProperty("target-platform") as String?)
                    ?.split(",")
                    ?.mapNotNull {
                        when (it.trim()) {
                            "android-arm64" -> "arm64-v8a"
                            "android-x64" -> "x86_64"
                            else -> null
                        }
                    }
                    ?.takeIf { it.isNotEmpty() }
                    ?: listOf("arm64-v8a", "x86_64")
                abiFilters(*requested.toTypedArray())
                // Always optimised: profile/debug variants otherwise compile
                // ggml at -O0, which is tens of times slower.
                arguments("-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=Release")
                cFlags("-O3")
                cppFlags("-O3")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Production builds must provide key.properties. Without it the
            // artifact remains unsigned instead of silently using debug keys.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
