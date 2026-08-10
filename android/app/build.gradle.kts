import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterLocalProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    require(localPropertiesFile.isFile) {
        "android/local.properties is missing; run flutter build apk --config-only --no-pub."
    }
    localPropertiesFile.inputStream().use { load(it) }
}

fun requiredIntProperty(name: String): Int =
    providers.gradleProperty(name).get().toInt()

fun requiredStringProperty(name: String): String =
    providers.gradleProperty(name).get()

fun requiredFlutterProperty(name: String): String {
    val value = flutterLocalProperties.getProperty(name)?.trim()
    require(!value.isNullOrEmpty()) {
        "$name is missing from android/local.properties; run flutter build apk --config-only --no-pub."
    }
    return value
}

val projectJavaVersion = JavaVersion.toVersion(
    requiredStringProperty("noteSecretSearch.javaVersion"),
)
val flutterVersionCode = requiredFlutterProperty("flutter.versionCode").toIntOrNull()
    ?: error("flutter.versionCode must be an integer in android/local.properties.")
val flutterVersionName = requiredFlutterProperty("flutter.versionName")
require(flutterVersionCode != 1) {
    "flutter.versionCode is still the Gradle default 1; run flutter build apk --config-only --no-pub."
}
require(flutterVersionName != "1.0") {
    "flutter.versionName is still the Gradle default 1.0; run flutter build apk --config-only --no-pub."
}

android {
    namespace = "com.example.note_secret_search"
    compileSdk = requiredIntProperty("noteSecretSearch.android.compileSdk")
    ndkVersion = requiredStringProperty("noteSecretSearch.android.ndkVersion")

    defaultConfig {
        applicationId = "com.example.note_secret_search"
        minSdk = requiredIntProperty("noteSecretSearch.android.minSdk")
        targetSdk = requiredIntProperty("noteSecretSearch.android.targetSdk")
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = projectJavaVersion
        targetCompatibility = projectJavaVersion
    }

    kotlinOptions {
        jvmTarget = requiredStringProperty("noteSecretSearch.javaVersion")
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/arm64-v8a/librnllama_v8_2_fp16.so",
                "lib/arm64-v8a/librnllama_v8_2_fp16_dotprod.so",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.lambdapioneer.argon2kt:argon2kt:1.6.0")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")
    implementation(files("../third_party/llamacpp-kotlin-0.2.0-nss-arm64-baseline.aar"))

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}
