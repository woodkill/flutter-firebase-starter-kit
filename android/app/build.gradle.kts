import java.util.Base64

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
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

        // Naver Login SDK 네이티브 설정 (Phase 16.2 D-01).
        //
        // 교체된 플러그인은 runtime initialize()가 없고, AndroidManifest.xml의
        // meta-data를 plugin registration 시점에 읽어 SDK를 초기화한다.
        //
        // meta-data가 @string 참조인 이유: android:value는 typed value라
        // 숫자로만 이뤄진 리터럴이 정수로 컴파일되어 네이티브의 getString이
        // null을 돌려줄 수 있고, 그러면 플러그인이 조용히 초기화를 건너뛴다.
        // @string 참조는 이 위험을 구조적으로 제거한다 (Facebook 선례 동일).
        //
        // dart-define 미주입 시 빈 문자열 → 앱 기동은 성공하고 Naver 버튼 탭
        // 시에만 실패한다 (D-05, silent failure 아님).
        resValue("string", "naver_client_id", dartDefines["naverClientId"] ?: "")
        resValue("string", "naver_client_secret", dartDefines["naverClientSecret"] ?: "")
        // 동의 화면 앱 이름 = config json의 기존 appName(flavor 표시명) 재사용,
        // 전용 키 신설 없음 (D-06).
        resValue("string", "naver_client_name", dartDefines["appName"] ?: "")

        // Kakao SDK 네이티브 앱 키 (Phase 12 D-20, D-21).
        //
        // AndroidManifest.xml의 com.kakao.sdk.AppKey meta-data와
        // OAuth redirect Activity의 URL scheme intent-filter (kakao${kakaoNativeAppKey}://oauth)
        // 가 manifestPlaceholders로 주입받는다. dart-define 미주입 시 빈 문자열 →
        // KakaoSdk 첫 SDK API 호출 시점에 throw로 즉시 발견 가능 (silent failure 아님).
        manifestPlaceholders["kakaoNativeAppKey"] = dartDefines["kakaoNativeAppKey"] ?: ""

        // Yahoo!JP OAuth redirect scheme (Phase 15 D-YJP-03 — see ROADMAP.md).
        //
        // flutter_appauth README verbatim: defaultConfig 에 `appAuthRedirectScheme`
        // manifestPlaceholder 등록 시 RedirectActivity 가 manifest merging 으로
        // 자동 inject (AndroidManifest.xml 본문 명시적 Activity 등록 불필요).
        // Yahoo Developers Console "クライアントサイド・アプリケーション" 등록
        // 시 Redirect URI 의 custom scheme 부분과 1:1 일치 의무 — 충돌 시
        // intent hijack 위험 (T-15-02). dart-define 미주입 시 빈 문자열 →
        // 첫 signInWithYahoojp 호출 시점에 즉시 발견 가능.
        manifestPlaceholders["appAuthRedirectScheme"] = dartDefines["yahoojpRedirectScheme"] ?: ""

        // Naver 킷 소유 웹 OAuth 콜백 scheme (Phase 16.5 D-09 · probe ② A).
        //
        // Dart `AppConfig.naverWebCallbackScheme` 과 같은 식 — 둘 다 config json 의
        // 기존 naverUrlScheme 키를 읽는다(새 키 0). AndroidManifest.xml 의
        // flutter_web_auth_2 CallbackActivity intent-filter 가 이 값을 scheme 으로 쓴다.
        // Android intent-filter 는 scheme 대소문자를 구분하므로 RFC 3986 소문자
        // 값이어야 한다(Dart 가 같은 규칙으로 검사한다). 이 값은 secret 이 아니다 —
        // client_id · client_secret 은 위 resValue 경로를 유지한다.
        // dart-define 미주입 시 빈 문자열 → 첫 Naver 웹 로그인 시도에서 Dart 가
        // ServiceUnavailable 로 즉시 알린다 (silent failure 아님).
        manifestPlaceholders["naverWebCallbackScheme"] = dartDefines["naverUrlScheme"] ?: ""
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

    // Phase 16.5 D-03 · D-23 — NaverHostChannel.kt 가 SDK 의 설치 판정
    // (NidApplicationUtil.isExistNaverApp) 을 호출하려면 컴파일 classpath 에
    // SDK 가 있어야 한다. naver_login_flutter 플러그인이 같은 좌표를
    // implementation 으로 선언해 앱 모듈에는 노출되지 않으므로 compileOnly 로
    // 같은 좌표 · 같은 버전을 선언한다(런타임 AAR 은 플러그인이 공급 — 새 의존성 0).
    // 플러그인을 올려 SDK 버전이 바뀌면 T-16.5-NATIVE-07 이 이 줄의 갱신을 요구한다.
    compileOnly("com.navercorp.nid:oauth:5.11.2")
}

flutter {
    source = "../.."
}
