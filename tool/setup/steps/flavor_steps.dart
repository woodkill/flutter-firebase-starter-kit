import '../flavor.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import 'apis_step.dart';
import 'app_check_step.dart';
import 'apple_android_step.dart';
import 'apple_step.dart';
import 'billing_step.dart';
import 'configure_step.dart';
import 'facebook_step.dart';
import 'firebase_project_step.dart';
import 'firestore_step.dart';
import 'functions_step.dart';
import 'google_android_step.dart';
import 'google_ios_step.dart';
import 'google_step.dart';
import 'identity_step.dart';
import 'kakao_step.dart';
import 'line_step.dart';
import 'login_step.dart';
import 'naver_step.dart';
import 'provider_android_step.dart';
import 'providers_step.dart';
import 'rules_step.dart';
import 'run_step.dart';
import 'sign_in_check_step.dart';
import 'sign_in_step.dart';
import 'storage_step.dart';
import 'tools_step.dart';
import 'user_files_step.dart';
import 'xcode_step.dart';

/// [flavor] 를 준비하는 단계 목록을 켠 로그인 수단 [enabledProviders] 에 맞춰
/// 순서대로 만든다.
///
/// 위저드는 이 순서대로 검사하고 진행한다. 켠 로그인 수단의 단계는 App Check
/// 뒤 · Functions 앞에 고정 순서로 끼우고, Functions 단계는 그 단계들이 모두
/// 끝난 뒤에 검사한다. 콘솔형 로그인 수단은 그 단계 바로 뒤에 Android 쪽 줄을
/// 끼운다 — 함수 배포는 Android 쪽 줄을 기다리지 않는다. Google 은 설정 파일을
/// 다시 받아야 하므로 로그인 수단 단계 다음 · 앱 등록 앞에 두고, iOS · Android
/// 쪽 줄은 앱 등록 다음에 둔다. Apple 은 iOS · Android 쪽 줄을 App Check 다음 ·
/// 다른 로그인 수단 앞에 두고, 함수 배포는 iOS 쪽 줄만 기다린다. 켠 로그인
/// 수단이 있으면 실행 단계 바로 다음에 소셜 로그인 확인 단계를 둔다. 새 단계는
/// 진행 순서에 맞는 자리에 끼운다.
List<Step> buildSteps({
  required Flavor flavor,
  required Set<String> enabledProviders,
}) {
  final bool isGoogleEnabled = enabledProviders.contains(GoogleStep.token);
  final bool isAppleEnabled = enabledProviders.contains(AppleStep.token);
  final providerSteps = <Step>[
    if (enabledProviders.contains(FacebookStep.token)) FacebookStep(),
    if (enabledProviders.contains(KakaoStep.token)) KakaoStep(),
    if (enabledProviders.contains(NaverStep.token)) NaverStep(),
    if (enabledProviders.contains(LineStep.token)) LineStep(),
  ];
  return <Step>[
    ..._buildCommonSteps(isGoogleEnabled: isGoogleEnabled),
    if (isAppleEnabled) ...<Step>[AppleStep(), AppleAndroidStep()],
    for (final Step step in providerSteps) ...<Step>[
      step,
      ...?_buildAndroidSideSteps(step.id),
    ],
    FunctionsStep(
      enabledProviders: enabledProviders,
      providerStepIds: <String>[
        // Google 은 Android 쪽 줄(SHA-1 등록)을 기다리지 않는다.
        if (isGoogleEnabled) ...<String>[GoogleStep.token, 'google_ios'],
        // Apple 은 Android 쪽 줄(코드 흐름 설정)을 기다리지 않는다.
        if (isAppleEnabled) AppleStep.token,
        for (final Step step in providerSteps) step.id,
      ],
    ),
    RunStep(),
    if (enabledProviders.isNotEmpty)
      SignInCheckStep(enabledProviders: enabledProviders),
  ];
}

/// 로그인 수단 [token] 단계 뒤에 끼울 Android 쪽 단계 — 콘솔형 수단이 아니면 null.
///
/// Android 쪽 단계는 함수 배포가 기다리는 로그인 수단 단계 목록에 넣지 않는다.
List<Step>? _buildAndroidSideSteps(String token) {
  final AndroidFingerprintKind? kind = switch (token) {
    FacebookStep.token ||
    KakaoStep.token ||
    NaverStep.token => AndroidFingerprintKind.keyHash,
    LineStep.token => AndroidFingerprintKind.sha1Colon,
    _ => null,
  };
  final ProviderEntry? entry = findProvider(token);
  if (kind == null || entry == null) return null;
  return <Step>[ProviderAndroidSideStep(entry, kind)];
}

/// 앞 단계 목록(App Check 까지)을 만든다.
///
/// [isGoogleEnabled] 면 Google 단계를 로그인 수단 단계 다음에 두고, 앱 등록이
/// Google 클라이언트가 든 설정 파일을 요구하게 하며, Google 의 iOS · Android 쪽
/// 단계를 앱 등록 다음에 둔다.
List<Step> _buildCommonSteps({required bool isGoogleEnabled}) {
  return <Step>[
    XcodeStep(),
    ToolsStep(),
    UserFilesStep(),
    IdentityStep(),
    LoginStep(),
    FirebaseProjectStep(),
    BillingStep(),
    ApisStep(),
    FirestoreStep(),
    StorageStep(),
    SignInStep(),
    ProvidersStep(),
    if (isGoogleEnabled) GoogleStep(),
    ConfigureStep(requiresGoogleClient: isGoogleEnabled),
    if (isGoogleEnabled) ...<Step>[GoogleIosStep(), GoogleAndroidStep()],
    RulesStep(),
    AppCheckStep(),
  ];
}
