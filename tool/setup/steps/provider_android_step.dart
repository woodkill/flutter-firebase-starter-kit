import '../firebase_app_files.dart';
import '../providers/fingerprints.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../wizard.dart';

/// 로그인 수단 콘솔이 받는 Android 서명 지문 형식.
enum AndroidFingerprintKind {
  /// 키 해시 — SHA-1 바이트의 base64 28자(Kakao · Facebook · Naver).
  keyHash,

  /// SHA-1 — 대문자 · 콜론 59자(LINE).
  sha1Colon,
}

/// Android 쪽 ✓ 줄 끝에 붙는 안내.
///
/// ✓ 는 지문을 계산해 값을 보였다는 뜻이다 — 콘솔에 실제로 등록했는지는 읽는
/// API 가 없어 앱 로그인 검사가 확인한다.
const String consoleRegistrationNote = '(콘솔 등록은 로그인 검사로 확인)';

/// 콘솔형 로그인 수단의 「Android 쪽」 줄 — 콘솔에 넣을 서명 지문을 보인다.
///
/// 지문을 계산할 수 있으면 콘솔이 받는 형식의 값 · 패키지명을 ✓ 로 보이고,
/// 없으면 이 줄만 할 수 없음(✗)으로 남긴다 — 함수 배포 · 앱 실행은 이 단계를
/// 기다리지 않는다. 실행할 것은 없다.
final class ProviderAndroidSideStep implements Step {
  /// [entry] 로그인 수단의 Android 쪽 줄을 [kind] 형식으로 만든다.
  const ProviderAndroidSideStep(this.entry, this.kind);

  /// Android 쪽 단계 id 의 꼬리 — `<토큰>_android`.
  static const String idSuffix = '_android';

  /// 이 줄이 가리키는 로그인 수단.
  final ProviderEntry entry;

  /// 콘솔이 받는 지문 형식.
  final AndroidFingerprintKind kind;

  @override
  String get id => '${entry.token}$idSuffix';

  @override
  String get title => '${entry.displayName} — Android 쪽';

  @override
  List<String> get dependsOn => const <String>['providers', 'identity'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final DebugFingerprints fingerprints = await readDebugFingerprints(context);
    return switch (fingerprints) {
      FingerprintsAvailable() => Done(buildDoneSummary(context, fingerprints)),
      FingerprintsUnavailable() => const Deferred(unavailableFingerprintGuide),
    };
  }

  /// 지문을 계산했을 때의 ✓ 줄 요약을 만든다.
  ///
  /// `<키 해시|SHA-1> <값> · 패키지명 <패키지명> (콘솔 등록은 로그인 검사로 확인)`.
  String buildDoneSummary(
    WizardContext context,
    FingerprintsAvailable fingerprints,
  ) {
    final String packageName =
        readAndroidPackage(context.projectRoot, context.flavor) ?? '(읽지 못했습니다)';
    final String value = switch (kind) {
      AndroidFingerprintKind.keyHash => '키 해시 ${fingerprints.keyHash}',
      AndroidFingerprintKind.sha1Colon =>
        'SHA-1 ${formatSha1Colon(fingerprints.sha1Hex)}',
    };
    return '$value · 패키지명 $packageName $consoleRegistrationNote';
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async => const Applied();
}
