import '../flavor.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import 'apis_step.dart';
import 'app_check_step.dart';
import 'billing_step.dart';
import 'configure_step.dart';
import 'facebook_step.dart';
import 'firebase_project_step.dart';
import 'firestore_step.dart';
import 'functions_step.dart';
import 'identity_step.dart';
import 'kakao_step.dart';
import 'line_step.dart';
import 'login_step.dart';
import 'naver_step.dart';
import 'provider_android_step.dart';
import 'providers_step.dart';
import 'rules_step.dart';
import 'run_step.dart';
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
/// 끼운다 — 함수 배포는 Android 쪽 줄을 기다리지 않는다. 새 단계는 진행 순서에
/// 맞는 자리에 끼운다.
List<Step> buildSteps({
  required Flavor flavor,
  required Set<String> enabledProviders,
}) {
  final providerSteps = <Step>[
    if (enabledProviders.contains(FacebookStep.token)) FacebookStep(),
    if (enabledProviders.contains(KakaoStep.token)) KakaoStep(),
    if (enabledProviders.contains(NaverStep.token)) NaverStep(),
    if (enabledProviders.contains(LineStep.token)) LineStep(),
  ];
  return <Step>[
    ..._buildCommonSteps(),
    for (final Step step in providerSteps) ...<Step>[
      step,
      ...?_buildAndroidSideSteps(step.id),
    ],
    FunctionsStep(
      enabledProviders: enabledProviders,
      providerStepIds: <String>[for (final Step step in providerSteps) step.id],
    ),
    RunStep(),
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

/// 로그인 수단과 무관한 앞 단계 목록(App Check 까지)을 만든다.
List<Step> _buildCommonSteps() {
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
    ConfigureStep(),
    RulesStep(),
    AppCheckStep(),
  ];
}
