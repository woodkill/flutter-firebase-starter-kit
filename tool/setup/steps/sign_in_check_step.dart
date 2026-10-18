import '../command_runner.dart';
import '../providers/provider_catalog.dart';
import '../providers/sign_in_counts.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'run_step.dart';

/// 소셜 로그인 확인 단계 — 켠 로그인 수단마다 앱으로 로그인한 사용자가 있는지
/// 개수로 확인한다.
///
/// 미룰 수 있는 단계([DeferrableStep])다. 검사는 [countSignIns] 로 켠 수단마다
/// 가입자 수를 세어 모두 1명 이상이면 끝이다 — 응답의 이메일 · uid · 문서 이름은
/// 화면 · 기록에 쓰지 않고 수단 이름과 개수만 보인다.
///
/// 아직 기록이 없는 수단이 있으면 실행 단계와 같은 경로([RunStep.launchAppForSignIn])
/// 로 앱을 다시 띄워 그 수단으로 로그인하게 한 뒤 다시 센다. 그래도 남으면 단계
/// 안에서 같은 세 선택지(다시 실행 · 나중에 · 멈춤)를 다시 묻는다. 나중에는
/// 저장하지 않으므로 다음 실행의 점검표에 다시 보인다.
final class SignInCheckStep implements DeferrableStep {
  /// 켠 로그인 수단 토큰 [enabledProviders] 를 확인하는 단계를 만든다.
  SignInCheckStep({required this.enabledProviders});

  /// 단계 id.
  static const String stepId = 'sign_in_check';

  /// 단계 제목.
  static const String stepTitle = '소셜 로그인 확인';

  /// 기록이 없는 수단 목록 앞에 붙는 사유 머리.
  static const String noRecordPrefix = '아직 로그인 기록이 없습니다: ';

  /// 다시 실행 계획 줄의 안내 — 앱을 띄우기 전에 보일 것.
  static const String relaunchPlanNote =
      '(앱을 띄우기 전에 아직 로그인 기록이 없는 수단을 보여 줍니다 — 그 수단으로 로그인)';

  /// 다시 실행 계획 줄의 안내 — 실행이 끝난 뒤 다시 센다.
  static const String recountPlanNote =
      '(실행이 끝나면 아래 요청으로 켠 수단의 로그인 수를 다시 셉니다 — 개수만 보이고 '
      '아직 없으면 다시 고릅니다)';

  /// 켠 로그인 수단 토큰.
  final Set<String> enabledProviders;

  final RunStep _launcher = RunStep();

  _SignInMode _mode = _SignInMode.unreadable;
  String _reason = '';
  CommandResult? _failedResult;
  String _projectId = '';
  List<String> _missingNames = const <String>[];

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['run'];

  @override
  String get proceedLabel => '앱을 다시 실행';

  @override
  String get deferLabel => '나중에';

  // 다시 띄우고 세기만 한다 — 비용 · 되돌릴 수 없는 선택이 없다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      _mode = _SignInMode.unreadable;
      _reason = '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다';
      return Todo(_reason);
    }
    _projectId = projectId;
    final SignInCount count = await countSignIns(
      context,
      projectId,
      enabledProviders,
    );
    switch (count) {
      case SignInCountFailed(
        :final String reason,
        :final CommandResult? result,
      ):
        _mode = _SignInMode.requestFailed;
        _reason = reason;
        _failedResult = result;
        return Todo(reason);
      case SignInCountOk(:final Map<String, int> countsByToken):
        final List<String> missing = _findMissingNames(countsByToken);
        if (missing.isEmpty) {
          _mode = _SignInMode.done;
          return Done(_formatCounts(countsByToken));
        }
        _mode = _SignInMode.relaunch;
        _missingNames = missing;
        return Todo(_buildNoRecordReason(missing));
    }
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _SignInMode.relaunch => <String>[
      ...RunStep.buildLaunchPlanLines(context, guideNote: relaunchPlanNote),
      recountPlanNote,
      if (_enabledEntries.any(
        (ProviderEntry entry) => authProviderIds.containsKey(entry.token),
      ))
        RunStep.buildBatchGetRequest(_projectId).displayCurl(),
      if (_enabledEntries.any(
        (ProviderEntry entry) => identityIndexProviders.contains(entry.token),
      ))
        buildIdentityIndexRequest(_projectId).displayCurl(),
    ],
    _SignInMode.requestFailed => <String>['(응답 원문을 보입니다)'],
    _SignInMode.unreadable || _SignInMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _SignInMode.relaunch => await _relaunchUntilSignedIn(context),
      _SignInMode.requestFailed => Failed(_reason, result: _failedResult),
      _SignInMode.unreadable => Failed(_reason),
      _SignInMode.done => const Applied(),
    };
  }

  /// 앱을 다시 띄우고 다시 센다 — 아직 없는 수단이 남으면 다시 묻는다.
  ///
  /// 모두 1명 이상이면 [Applied](위저드가 다시 검사해 ✓ 줄을 낸다), 세지 못하면
  /// 실패, 나중에면 [DeferredByUser], 멈춤 · 입력 끝이면 [Declined] 다. 앱 실행이
  /// 끝나지 않은 결과(실패 · 대상 고르기 입력 끝)는 그대로 돌려준다.
  Future<StepOutcome> _relaunchUntilSignedIn(WizardContext context) async {
    var missing = _missingNames;
    while (true) {
      final StepOutcome launched = await _launcher.launchAppForSignIn(
        context,
        guideLines: <String>['  ${missing.join(' · ')} 로 로그인한 뒤 q 로 끝내세요'],
      );
      if (launched is! Applied) return launched;
      final SignInCount count = await countSignIns(
        context,
        _projectId,
        enabledProviders,
      );
      switch (count) {
        case SignInCountFailed(
          :final String reason,
          :final CommandResult? result,
        ):
          return Failed(reason, result: result);
        case SignInCountOk(:final Map<String, int> countsByToken):
          missing = _findMissingNames(countsByToken);
      }
      if (missing.isEmpty) return const Applied();
      context.terminal.writeLine('  ${_buildNoRecordReason(missing)}');
      final int? choice = context.terminal.choose(
        failureChoiceQuestion,
        <String>[proceedLabel, deferLabel, stopOption],
        defaultIndex: null,
      );
      switch (choice) {
        case 0:
          continue;
        case 1:
          return DeferredByUser(deferLabel);
        default:
          return const Declined();
      }
    }
  }

  /// 켠 수단의 표 행(표 순서) — 표에 없는 토큰은 뺀다.
  List<ProviderEntry> get _enabledEntries => <ProviderEntry>[
    for (final ProviderEntry entry in providerCatalog)
      if (enabledProviders.contains(entry.token)) entry,
  ];

  /// 개수가 0 인(또는 세지 않은) 켠 수단의 표시 이름을 표 순서로 모은다.
  List<String> _findMissingNames(Map<String, int> countsByToken) => <String>[
    for (final ProviderEntry entry in _enabledEntries)
      if ((countsByToken[entry.token] ?? 0) < 1) entry.displayName,
  ];

  /// 켠 수단마다 `<표시 이름> <n>명` 을 표 순서로 잇는다.
  String _formatCounts(Map<String, int> countsByToken) => <String>[
    for (final ProviderEntry entry in _enabledEntries)
      '${entry.displayName} ${countsByToken[entry.token] ?? 0}명',
  ].join(' · ');

  /// 기록이 없는 수단 [names] 의 사유를 만든다.
  String _buildNoRecordReason(List<String> names) =>
      '$noRecordPrefix${names.join(' · ')}';
}

/// 직전 검사 판정 — 실행이 무엇을 할지 정한다.
enum _SignInMode {
  /// config 에서 프로젝트 ID 를 읽지 못함.
  unreadable,

  /// 기록이 없는 수단이 있어 앱을 다시 띄운다.
  relaunch,

  /// 집계 요청이 실패함.
  requestFailed,

  /// 켠 수단 모두 1명 이상.
  done,
}
