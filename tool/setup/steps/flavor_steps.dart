import '../flavor.dart';
import '../step.dart';
import 'apis_step.dart';
import 'app_check_step.dart';
import 'billing_step.dart';
import 'configure_step.dart';
import 'firebase_project_step.dart';
import 'firestore_step.dart';
import 'functions_step.dart';
import 'identity_step.dart';
import 'kakao_step.dart';
import 'login_step.dart';
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
/// 끝난 뒤에 검사한다. 새 단계는 진행 순서에 맞는 자리에 끼운다.
List<Step> buildSteps({
  required Flavor flavor,
  required Set<String> enabledProviders,
}) {
  final List<Step> providerSteps = <Step>[
    if (enabledProviders.contains(KakaoStep.token)) KakaoStep(),
  ];
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
    ...providerSteps,
    FunctionsStep(
      enabledProviders: enabledProviders,
      providerStepIds: <String>[for (final Step step in providerSteps) step.id],
    ),
    RunStep(),
  ];
}
