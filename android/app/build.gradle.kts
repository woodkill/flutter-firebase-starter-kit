import java.io.ByteArrayOutputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

android {
    namespace = "com.slimpumpkin.flutter_starter_kit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Phase 17 — see ROADMAP.md · flutter_local_notifications 10+ 요구 (README Gradle setup)
        isCoreLibraryDesugaringEnabled = true
    }

    // Phase 17.6 — see ROADMAP.md · 아래 defaultConfig 의 resValue 6곳(Facebook 2 · Naver 3 · 앱 이름 1)이
    // 이 기능을 쓴다. AGP 9 기본값은 꺼짐이라 켜지 않으면 설정 단계에서 빌드가 멈춘다.
    buildFeatures {
        resValues = true
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
        // AndroidManifest.xml의 com.kakao.sdk.AppKey meta-data(kakaoNativeAppKey)와
        // OAuth redirect Activity의 URL scheme intent-filter(kakaoOAuthScheme)가
        // manifestPlaceholders로 주입받는다. 키가 있으면 scheme 은 kakao + 키다.
        //
        // 키가 비면 meta-data 는 빈 값 그대로 두고, scheme 은 일반 scheme(kakao://)
        // 대신 앱이 쓰지 않는 소문자 자리표시 scheme 을 등록한다 — 다른 앱의
        // 링크를 가로채지 않게 (Phase 17.3 — see ROADMAP.md). gradle 은 provider
        // on/off CSV 를 읽지 않고 이미 읽는 키 값의 비어 있음만 본다. 키가 빈 채로
        // Kakao 를 켜면 KakaoSdk 첫 SDK API 호출 시점에 throw로 즉시 발견 가능
        // (silent failure 아님).
        val kakaoNativeAppKey = dartDefines["kakaoNativeAppKey"] ?: ""
        manifestPlaceholders["kakaoNativeAppKey"] = kakaoNativeAppKey
        manifestPlaceholders["kakaoOAuthScheme"] =
            if (kakaoNativeAppKey.isEmpty()) "unset.kakao.oauth" else "kakao$kakaoNativeAppKey"

        // Naver 킷 소유 웹 OAuth 콜백 scheme (Phase 16.5 D-09 · probe ② A).
        //
        // Dart `AppConfig.naverWebCallbackScheme` 과 같은 키 — 둘 다 config json 의
        // 기존 naverUrlScheme 키를 읽는다(새 키 0 · 키가 있으면 같은 값). AndroidManifest.xml 의
        // flutter_web_auth_2 CallbackActivity intent-filter 가 이 값을 scheme 으로 쓴다.
        // Android intent-filter 는 scheme 대소문자를 구분하므로 RFC 3986 소문자
        // 값이어야 한다(Dart 가 같은 규칙으로 검사한다). 이 값은 secret 이 아니다 —
        // client_id · client_secret 은 위 resValue 경로를 유지한다.
        //
        // 키가 비면 일반 scheme(빈 scheme) 대신 앱이 쓰지 않는 소문자 자리표시
        // scheme 을 등록한다 — 다른 앱의 링크를 가로채지 않게 (Phase 17.3 — see
        // ROADMAP.md). gradle 은 provider on/off CSV 를 읽지 않고 이미 읽는 키 값의
        // 비어 있음만 본다. 키가 빈 채로 Naver 를 켜면 첫 Naver 웹 로그인 시도에서
        // Dart 가 ServiceUnavailable 로 즉시 알린다 (silent failure 아님).
        val naverUrlScheme = dartDefines["naverUrlScheme"] ?: ""
        manifestPlaceholders["naverWebCallbackScheme"] =
            if (naverUrlScheme.isEmpty()) "unset.naver.web" else naverUrlScheme

        // 홈 화면 런처 이름 — AndroidManifest.xml 의 application label 이 이
        // placeholder 를 쓰고, placeholder 는 string 리소스 app_name 을 가리킨다.
        // 기본 언어 값은 아래 resValue 로 config json 의 appName 이다(설정 위저드
        // 「앱 정체성」 단계가 iOS xcconfig 의 DISPLAY_NAME 과 같은 값으로 쓴다).
        // 다른 언어 값은 파일 아래 GenerateLauncherNamesTask 가 ARB 의 appTitle 로
        // 만든 values-<qualifier>/strings.xml 이다. dart-define 없이 빌드하면 그
        // 생성 task 가 고칠 방법을 적고 빌드를 멈추므로, 미주입 값은 다른
        // resValue 와 같은 빈 문자열이다.
        resValue("string", "app_name", dartDefines["appName"] ?: "")
        manifestPlaceholders["appName"] = "@string/app_name"
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

    // MainActivity.kt 의 LINE 로그인 콜백 relay(LineAuthCallbackActivity)가 SDK 의 인증
    // Activity 클래스를 참조하려면 컴파일 classpath 에 SDK 가 있어야 한다.
    // flutter_line_sdk 플러그인이 같은 좌표를 implementation 으로 선언해 앱 모듈에는
    // 노출되지 않으므로 compileOnly 로 같은 좌표 · 같은 버전을 선언한다(런타임 AAR 은
    // 플러그인이 공급 — 새 의존성 0). 플러그인을 올려 SDK 버전이 바뀌면
    // test/infrastructure/line_auth_task_return_contract_test.dart 가 이 줄의 갱신을 요구한다.
    compileOnly("com.linecorp.linesdk:linesdk:5.11.1")

    // Phase 17 — see ROADMAP.md · flutter_local_notifications 10+ 요구 (README Gradle setup)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Phase 17.6 — see ROADMAP.md · KGP 2.3 이상은 android 블록 안의 옛 Kotlin 옵션 DSL 을
// 스크립트 컴파일 오류로 만든다 → Flutter 3.47.5 템플릿과 같은 top-level compilerOptions.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// 홈 화면 앱 이름을 언어별로 만드는 생성 task. 규칙은 저장소 루트의
// tool/launcher_names.dart 한 곳에 있고(iOS 빌드 단계와 같은 생성기), 이 task 는
// 입력 · 출력 선언과 실행만 맡는다. 생성기는 dart: 라이브러리만 쓰므로 패키지
// 해석 없이 Flutter SDK 의 dart 로 바로 실행한다. 출력 디렉터리는 AGP 가
// build/ 아래에 정하고 variant 의 생성 리소스로 붙인다 — 저장소에 언어별 파일이
// 생기지 않는다. ARB 위치는 생성기가 l10n.yaml 의 arb-dir 에서 읽으므로 이
// task 는 ARB 파일을 입력으로 세지 않고 빌드마다 다시 돈다(iOS 빌드 단계와 같다).
abstract class GenerateLauncherNamesTask : DefaultTask() {
    @get:javax.inject.Inject
    abstract val execOperations: ExecOperations

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val generator: RegularFileProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val l10nConfig: RegularFileProperty

    @get:Input
    abstract val flavor: Property<String>

    @get:Input
    abstract val appName: Property<String>

    // 기계마다 다른 절대 경로라 입력으로 세지 않는다.
    @get:Internal
    abstract val projectRoot: DirectoryProperty

    @get:Internal
    abstract val dartExecutable: Property<String>

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val out = outputDirectory.get().asFile
        out.deleteRecursively()
        out.mkdirs()
        val errors = ByteArrayOutputStream()
        val result = execOperations.exec {
            commandLine(
                dartExecutable.get(),
                generator.get().asFile.absolutePath,
                "android",
                "--project-root",
                projectRoot.get().asFile.absolutePath,
                "--out",
                out.absolutePath,
                "--flavor",
                flavor.get(),
                "--app-name",
                appName.get(),
            )
            errorOutput = errors
            isIgnoreExitValue = true
        }
        // 생성기의 오류 문장(고칠 파일 · 값 · 방법)이 빌드 출력의 「What went wrong」 에
        // 그대로 보이게 한다.
        if (result.exitValue != 0) {
            throw GradleException(errors.toString(Charsets.UTF_8).trim())
        }
    }
}

// local.properties 의 flutter.sdk(Flutter Gradle plugin 과 같은 출처) 아래 dart 경로.
fun resolveLauncherNamesDart(): String {
    val properties = Properties()
    val localProperties = rootProject.file("local.properties")
    if (localProperties.isFile) {
        localProperties.inputStream().use { properties.load(it) }
    }
    val flutterSdk = properties.getProperty("flutter.sdk")
        ?: error("android/local.properties 에 flutter.sdk 가 없다 — fvm flutter pub get 을 한 번 실행한다")
    return "$flutterSdk/bin/dart"
}

androidComponents {
    onVariants { variant ->
        val task = tasks.register<GenerateLauncherNamesTask>(
            "generate${variant.name.replaceFirstChar { it.uppercase() }}LauncherNames",
        ) {
            // ARB 디렉터리를 여기서 고정하면 l10n.yaml 의 arb-dir 를 옮긴 프로젝트에서
            // ARB 를 고쳐도 UP-TO-DATE 로 건너뛴다 — 생성기는 짧게 끝나므로 매번 돌린다.
            outputs.upToDateWhen { false }
            generator.set(rootProject.file("../tool/launcher_names.dart"))
            l10nConfig.set(rootProject.file("../l10n.yaml"))
            projectRoot.set(rootProject.file(".."))
            flavor.set(variant.flavorName ?: "")
            appName.set(dartDefines["appName"] ?: "")
            dartExecutable.set(resolveLauncherNamesDart())
        }
        variant.sources.res?.addGeneratedSourceDirectory(task, GenerateLauncherNamesTask::outputDirectory)
    }
}
