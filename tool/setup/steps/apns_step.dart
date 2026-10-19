import '../confirm.dart';
import '../firebase_app_files.dart';
import '../providers/apple_key_input.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../wizard.dart';
import 'apple_android_step.dart';

/// APNs 키 단계 — Firebase 콘솔에 올릴 APNs 인증 키의 값을 안내한다.
///
/// 업로드 여부를 읽는 API 가 없어 이 단계는 끝났다고 판정하지 않는다 — 점검표 ·
/// 끝 목록에 늘 확인할 수 없는 줄로 남고, 실제 확인은 실기기 알림이다. 같은
/// 실행에서 DeviceCheck 에 키를 넣었을 때만(그 `.p8` 을 손에 든 때) 할 일이 되어
/// 값 표 · 할 일 · 매뉴얼 절을 보이고 Enter 를 안내 확인으로 받는다. 답 · Key ID
/// 를 저장하지 않고 config 를 쓰지 않는다. 콘솔 화면 단계는 매뉴얼 절이 맡는다.
final class ApnsStep implements DeferrableStep {
  /// APNs 키 단계를 만든다.
  ApnsStep();

  /// 단계 id.
  static const String stepId = 'apns';

  /// 단계 제목.
  static const String stepTitle = 'APNs 키';

  /// 확인할 수 없는 줄의 문장.
  static const String unverifiableNote = '콘솔 업로드(확인은 실기기 알림)';

  /// 값 표 뒤의 할 일 줄 — 기능 이름만 쓴다.
  static const String uploadTodoLine =
      'Firebase 콘솔에 APNs 인증 키 올리기 — iOS 앱마다 · 개발 · 운영 같은 키';

  /// 값 표 첫 행의 라벨 — 키를 올릴 iOS 앱을 번들 ID 로 가리킨다.
  static const String targetAppRowLabel = 'iOS 앱 (번들 ID)';

  /// 할 일 줄 다음의 안내 — 프로젝트에 iOS 앱이 여럿일 때 올릴 앱.
  static const String multipleAppsNote =
      'Firebase 프로젝트에 iOS 앱이 여럿이면 위 번들 ID 의 앱에 올리기';

  /// 화면 단계를 맡는 매뉴얼 절.
  static const String manualHeading = '### FCM 알림';

  /// 할 일 사유.
  static const String guideReason = 'DeviceCheck 에 넣은 키를 Firebase 콘솔에 올려야 합니다';

  /// 실행 전 계획 줄의 안내.
  static const String plannedNote =
      '(값 표 · 할 일을 보인 뒤 Enter 를 기다립니다 — 업로드 여부는 읽을 수 없어 '
      '? 줄로 남습니다)';

  /// 안내 확인 문구.
  static const String guideConfirmMessage = '안내를 확인했으면 Enter 를 누르세요';

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>[];

  @override
  String get proceedLabel => '업로드 안내 보기';

  @override
  String get deferLabel => '지금 안 함';

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final WizardSession session = context.session;
    if (session.hasEnteredDeviceCheckKey && !session.isApnsGuideShown) {
      return const Todo(guideReason);
    }
    return const Unverifiable(unverifiableNote);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[
    plannedNote,
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    final WizardSession session = context.session;
    final String? keyId = session.appleKeys[AppleKeyUse.deviceCheck]?.keyId;
    writeSummary(
      context.terminal,
      title: 'Firebase 콘솔에 올릴 APNs 인증 키',
      rows: <SummaryRow>[
        SummaryRow(
          targetAppRowLabel,
          readBundleId(context.projectRoot, context.flavor) ??
              AppleAndroidStep.unreadValue,
        ),
        SummaryRow(
          '.p8',
          keyId == null ? AppleAndroidStep.unreadValue : 'Key ID $keyId 의 .p8',
        ),
        SummaryRow('Key ID', keyId ?? AppleAndroidStep.unreadValue),
        SummaryRow(
          'Team ID',
          session.appleTeamId ?? AppleAndroidStep.unreadValue,
        ),
      ],
      notes: <String>[
        uploadTodoLine,
        multipleAppsNote,
        '자세한 절차: ${formatManualReference(manualHeading)}',
      ],
    );
    if (!context.terminal.waitForEnter(guideConfirmMessage)) {
      return const Declined();
    }
    session.isApnsGuideShown = true;
    return const Applied();
  }
}
