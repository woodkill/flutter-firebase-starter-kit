import java.util.Base64

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.slimpumpkin.flutter_starter_kit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Facebook SDK 네이티브 설정을 위해 dart-defines에서 값을 추출한다 (D-06).
    // --dart-define-from-file로 전달된 값은 Base64로 인코딩되어 gradle property로 전달된다.
    val dartDefines = mutableMapOf<String, String>()
    if (project.hasProperty("dart-defines")) {
        val encoded = project.property("dart-defines") as String
        encoded.split(",").forEach { entry ->
            val decoded = String(
                Base64.getDecoder().decode(entry),
                Charsets.UTF_8,
            )
            val parts = decoded.split("=", limit = 2)
            if (parts.size == 2) {
                dartDefines[parts[0]] = parts[1]
            }
        }
    }

    defaultConfig {
        applicationId = "com.slimpumpkin.flutter_starter_kit"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Facebook SDK가 AndroidManifest.xml에서 참조하는 string 리소스 (D-06).
        resValue("string", "facebook_app_id", dartDefines["facebookAppId"] ?: "")
        resValue("string", "facebook_client_token", dartDefines["facebookClientToken"] ?: "")
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") { applicationIdSuffix = ".dev" }
        create("stg") { applicationIdSuffix = ".stg" }
        create("prod") { /* prod는 suffix 없음 */ }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Firebase Auth signInWithProvider가 Chrome Custom Tab을 사용하도록
    // 명시적으로 추가한다. 이 의존성이 없으면 GenericIdpActivity가
    // 전체 Chrome 브라우저로 fallback하여 인증 후 자동 닫힘이 안 된다.
    implementation("androidx.browser:browser:1.8.0")
}

flutter {
    source = "../.."
}
