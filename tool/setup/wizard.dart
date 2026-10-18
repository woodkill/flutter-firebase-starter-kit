import 'dart:io';
import 'dart:math';

import 'command_runner.dart';
import 'flavor.dart';
import 'log_sink.dart';
import 'providers/apple_key_input.dart';
import 'providers/fingerprints.dart';
import 'redactor.dart';
import 'rest_client.dart';
import 'step.dart';
import 'terminal.dart';

/// 할 수 있는 단계를 모두 지났을 때의 종료 코드.
///
/// 미룬 · 할 수 없는 · 확인할 수 없는 단계가 남아 있어도 같다 — 그 줄은 끝 목록에
/// 보인다.
const int wizardExitDone = 0;

/// 멈춤 · 거절 · 입력 끝 · 실패로 끝났을 때의 종료 코드.
const int wizardExitStopped = 1;

/// 위저드 밖 작업을 안내하고 끝났을 때의 종료 코드.
const int wizardExitForUser = 3;

/// 점검표 머리 줄.
const String checklistHeading = '점검표';

/// 모든 단계가 끝났을 때의 줄.
const String allDoneLine = '모든 단계가 끝났습니다.';

/// 할 수 있는 단계를 모두 지났지만 남은 일이 있을 때의 줄.
const String remainingDoneLine = '할 수 있는 단계를 모두 지났습니다 — 남은 일은 아래와 같습니다.';

/// 끝 목록(미룬 · 할 수 없는 · 확인할 수 없는 단계)의 머리 줄.
const String remainingHeading = 'release 빌드 전에 끝내야 할 일:';

/// 단계를 시작하기 전에 묻는 질문.
const String stepConfirmQuestion = '이 단계를 진행할까요?';

/// 비용이 들거나 되돌릴 수 없는 선택이 있는 단계의 계획 줄 끝에 붙는 안내 줄.
const String costlyStepNotice =
    '(비용이 들거나 되돌릴 수 없는 선택이 있으면 실행 전에 값 표를 한 번 더 보이고 '
    '확인을 받습니다)';

/// 멈출 때의 마지막 줄.
const String stopLine = '같은 명령을 다시 실행하면 이어집니다.';

/// 위저드 밖 작업 안내 뒤에 붙는 줄.
const String exitForUserTailLine = '끝나면 ./setup.sh 를 다시 실행하세요 — 끝난 단계는 건너뜁니다.';

/// 위저드 밖 짧은 작업을 기다릴 때의 문구.
const String waitForEnterMessage = '끝나면 Enter 를 누르세요';

/// 실패 뒤 고르기 · 미룰 수 있는 단계의 진행 고르기 질문.
const String failureChoiceQuestion = '어떻게 할까요?';

/// 실패 뒤 고르기의 다시 시도 선택지.
const String retryOption = '다시 시도';

/// 실패 뒤 고르기 · 미룰 수 있는 단계의 진행 고르기의 멈춤 선택지.
const String stopOption = '멈춤';

/// 할 수 있는 단계를 모두 지난 뒤 부르는 함수 — 끝 요약 등을 보인다.
typedef WizardCompletion = Future<void> Function(WizardContext context);

/// 끝난 뒤 함수가 실패했을 때의 안내 머리 — 종료 코드는 바꾸지 않는다.
const String completionFailedPrefix = '끝 요약을 보이지 못했습니다 — ';

/// 단계 목록을 다시 만들기 직전에 보이는 줄.
const String replanLine = '로그인 수단이 바뀌었습니다 — 단계 목록을 다시 만듭니다.';

/// 한 실행 안에서 단계 목록을 다시 만드는 최대 횟수 — 넘으면 다시 검사만 한다.
const int maxReplans = 3;

/// 단계 목록을 다시 만드는 함수 — 바뀐 설정 파일을 다시 읽어 새 목록을 돌려준다.
typedef StepListBuilder = List<Step> Function();

/// 한 실행 안에서만 유지하는 메모리 상태 — 파일로 남기지 않는다.
final class WizardSession {
  /// 로그인 수단 체크 목록을 열어 달라는 요청(`--providers`)이 남아 있으면 true.
  ///
  /// 로그인 수단 단계가 체크 목록을 마치면 끈다.
  bool isProviderSelectionRequested = false;

  /// 이번 실행에서 계산한 Android 디버그 서명 키 지문 — 아직 계산 전이면 null.
  ///
  /// 「계산할 수 없음」 도 담는다 — keytool 을 한 실행 안에서 다시 부르지 않는다.
  DebugFingerprints? debugFingerprints;

  /// 이번 실행에서 받은 Apple 키 — 자리(용도)마다 따로 두고, 같은 키면 두
  /// 자리가 같은 값을 가리킨다.
  ///
  /// `.p8` 내용만 담고 파일 경로는 담지 않는다.
  final Map<AppleKeyUse, AppleKey> appleKeys = <AppleKeyUse, AppleKey>{};

  /// 이번 실행에서 정한 Apple Team ID — 아직 정하지 않았으면 null.
  String? appleTeamId;

  /// 이번 실행에서 DeviceCheck 키를 Firebase 에 넣었으면 true.
  ///
  /// DeviceCheck 단계가 실행 끝에 켜고, APNs 안내가 읽는다.
  bool hasEnteredDeviceCheckKey = false;

  /// 이번 실행에서 APNs 키 업로드 안내를 보였으면 true.
  ///
  /// APNs 단계가 안내 확인 뒤 켠다 — 같은 실행에서 안내를 다시 띄우지 않는다.
  /// 업로드했다는 뜻이 아니다(확인할 방법이 없다).
  bool isApnsGuideShown = false;
}

/// 단계 실행에 필요한 공용 문맥.
final class WizardContext {
  /// 저장소 루트 · 실행기 · 터미널 · 가림 함수 · 실행 기록 · REST 실행기로
  /// 문맥을 만든다.
  ///
  /// [random] 을 주지 않으면 암호학적으로 안전한 난수를, [now] 를 주지 않으면
  /// 시스템 시각을 쓴다(테스트는 고정값을 넣는다). [flavor] 의 기본값은 dev 이고
  /// [session] 을 주지 않으면 빈 세션을 만든다. [homeDirectory] 를 주지 않으면
  /// 환경 변수 `HOME` 을 쓴다(테스트는 임시 디렉터리를 넣는다).
  WizardContext({
    required this.projectRoot,
    required this.runner,
    required this.terminal,
    required this.redactor,
    required this.log,
    required this.rest,
    this.flavor = Flavor.dev,
    WizardSession? session,
    String? homeDirectory,
    Random? random,
    DateTime Function()? now,
  }) : session = session ?? WizardSession(),
       homeDirectory = homeDirectory ?? Platform.environment['HOME'] ?? '',
       random = random ?? Random.secure(),
       now = now ?? DateTime.now;

  /// 저장소 루트의 절대 경로.
  final String projectRoot;

  /// 외부 명령 실행기.
  final CommandRunner runner;

  /// 화면 입출력 — 위저드는 가림 터미널을 넘긴다.
  final Terminal terminal;

  /// 화면 · 기록 직전에 비밀 값을 가리는 함수 — 단계가 아는 비밀 값을 등록한다.
  final Redactor redactor;

  /// 실행 기록.
  final LogSink log;

  /// REST 실행기 — 토큰은 프로세스 안에만 두고 화면에는 curl 표시형을 보인다.
  final RestClient rest;

  /// 이번 실행이 준비하는 flavor.
  final Flavor flavor;

  /// 한 실행 안의 메모리 상태.
  final WizardSession session;

  /// 사용자 홈 디렉터리의 절대 경로 — 모르면 빈 문자열.
  final String homeDirectory;

  /// [flavor] 의 사용자 파일 · 설정 파일 경로.
  FlavorPaths get paths => FlavorPaths(flavor);

  /// 비밀 값 · 식별자를 만들 때 쓰는 난수.
  final Random random;

  /// 지금 시각을 돌려주는 함수.
  final DateTime Function() now;

  /// [relativePath] 를 저장소 루트 기준 절대 경로로 바꾼다.
  String resolve(String relativePath) {
    if (relativePath.startsWith('/')) return relativePath;
    return '$projectRoot/$relativePath';
  }
}

/// 실패 고르기 뒤 위저드가 갈 길.
enum _RetryDecision {
  /// 멈춘다.
  stop,

  /// 다시 검사해 끝난 것을 확인했다 — 다음 단계로 간다.
  finished,

  /// 다시 실행한다.
  rerun,
}

/// 단계 진행 질문의 답.
enum _ProceedDecision {
  /// 실행한다.
  proceed,

  /// 이번 실행에서는 하지 않고 다음 단계로 간다.
  defer,

  /// 멈춘다.
  stop,
}

/// 점검표를 보이고 첫 할 일 단계부터 차례로 진행하는 위저드.
final class Wizard {
  /// [context] 로 [steps] 를 순서대로 진행하는 위저드를 만든다.
  ///
  /// [onCompleted] 는 할 수 있는 단계를 모두 지났을 때(종료 코드 0 직전)에만
  /// 부른다 — 끝 목록에 남은 일이 있어도 부른다.
  /// [rebuildSteps] 는 단계가 [Replan] 을 돌려줬을 때 새 목록을 만든다 — null 이면
  /// [Replan] 은 [Applied] 와 같다.
  Wizard(this.context, this.steps, {this.onCompleted, this.rebuildSteps})
    : _steps = steps;

  /// 공용 문맥.
  final WizardContext context;

  /// 처음 받은 단계 목록.
  final List<Step> steps;

  /// 할 수 있는 단계를 모두 지났을 때 부를 함수. null 이면 부르지 않는다.
  final WizardCompletion? onCompleted;

  /// 단계 목록을 다시 만드는 함수. null 이면 다시 만들지 않는다.
  final StepListBuilder? rebuildSteps;

  // 지금 진행 중인 단계 목록 — 다시 짜기마다 바뀐다.
  List<Step> _steps;

  // 이번 실행에서 다시 짠 횟수.
  int _replanCount = 0;

  // 방금 진행한 단계가 목록 다시 짜기를 요청했으면 true.
  bool _isReplanPending = false;

  // 이번 바퀴 점검표의 판정 — 진행 중 다시 판정한 줄을 다시 쓸지 정할 때 비교한다.
  Map<String, CheckResult> _checklist = <String, CheckResult>{};

  // 이번 바퀴의 최신 판정 — 점검표에서 시작해 단계를 마무리할 때마다 갱신한다.
  Map<String, CheckResult> _results = <String, CheckResult>{};

  // 이번 바퀴의 끝 목록 줄(진행 순서) — 바퀴마다 새로 모은다.
  final List<String> _remainingLines = <String>[];

  // 이번 실행에서 사용자가 미룬 단계 id → 미룬 사유. 다시 짠 바퀴에서도 다시
  // 묻지 않는다 — 파일로 남기지 않으므로 다음 실행은 다시 묻는다.
  final Map<String, String> _userDeferrals = <String, String>{};

  Terminal get _terminal => context.terminal;

  /// 위저드를 실행하고 종료 코드를 돌려준다.
  ///
  /// 단계가 목록 다시 짜기를 요청하면 새 목록으로 점검표부터 다시 돈다 — 끝 목록도
  /// 새 바퀴의 판정으로 다시 모은다.
  Future<int> run() async {
    while (true) {
      _checklist = await _checkAll();
      _results = Map<String, CheckResult>.of(_checklist);
      _remainingLines.clear();
      _printChecklist();
      if (_checklist.values.every((CheckResult result) => result is Done)) {
        _terminal.writeLine(allDoneLine);
        return await _complete();
      }
      var isReplanned = false;
      for (final Step step in _steps) {
        if (_checklist[step.id] is Done) continue;
        final int? code = await _runStep(step);
        if (code != null) return code;
        if (_isReplanPending) {
          _isReplanPending = false;
          isReplanned = true;
          break;
        }
      }
      if (isReplanned) continue;
      _printEnding();
      return await _complete();
    }
  }

  /// 진행을 마친 뒤의 끝 줄을 보인다.
  ///
  /// 끝 목록이 비었으면 모든 단계가 끝났다는 줄을, 아니면 남은 일 안내 · 머리 ·
  /// 점검표 줄 모양 그대로의 끝 목록을 보인다.
  void _printEnding() {
    _terminal.writeLine('');
    if (_remainingLines.isEmpty) {
      _terminal.writeLine(allDoneLine);
      return;
    }
    _terminal
      ..writeLine(remainingDoneLine)
      ..writeLine(remainingHeading);
    for (final String line in _remainingLines) {
      _terminal.writeLine(line);
    }
  }

  /// [Replan] 을 받았을 때 목록을 다시 만들 수 있으면 다시 만들고 true 를 돌려준다.
  ///
  /// 다시 만드는 함수가 없거나 [maxReplans] 를 넘었으면 false — 호출한 쪽이
  /// [Applied] 처럼 다시 검사만 한다.
  bool _replan() {
    final StepListBuilder? builder = rebuildSteps;
    if (builder == null || _replanCount >= maxReplans) return false;
    _replanCount++;
    _terminal
      ..writeLine('')
      ..writeLine(replanLine);
    _steps = builder();
    _isReplanPending = true;
    return true;
  }

  /// 끝난 뒤 함수를 부르고 끝남 종료 코드를 돌려준다.
  ///
  /// 함수가 예외를 던져도 단계는 모두 끝났으므로 한 줄로 알리고 끝남으로 둔다.
  Future<int> _complete() async {
    final WizardCompletion? completion = onCompleted;
    if (completion == null) return wizardExitDone;
    try {
      await completion(context);
    } on Exception catch (e) {
      _terminal.writeLine('$completionFailedPrefix$e');
    }
    return wizardExitDone;
  }

  /// 모든 단계를 순서대로 검사한다.
  ///
  /// 의존 단계 가운데 이번 점검에서 끝나지 않은 것이 있으면 그 단계는 검사하지
  /// 않고 [Blocked] 로 적는다 — 앞 단계 없이 실패하는 검사 명령을 부르지 않는다.
  Future<Map<String, CheckResult>> _checkAll() async {
    final results = <String, CheckResult>{};
    for (final Step step in _steps) {
      final String? waitingFor = _findUnfinishedDependency(step, results);
      if (waitingFor == null) {
        results[step.id] = await _check(step);
      } else {
        final blocked = Blocked(waitingFor);
        _logCheck(step, blocked);
        results[step.id] = blocked;
      }
    }
    return results;
  }

  /// [step] 의 의존 단계 가운데 [results] 에서 끝나지 않은 첫 단계의 제목을 찾는다.
  String? _findUnfinishedDependency(
    Step step,
    Map<String, CheckResult> results,
  ) {
    for (final String dependency in step.dependsOn) {
      if (results[dependency] is Done) continue;
      return _findTitle(dependency);
    }
    return null;
  }

  /// [id] 단계의 제목을 찾는다 — 목록에 없으면 [id] 그대로.
  String _findTitle(String id) {
    for (final Step step in _steps) {
      if (step.id == id) return step.title;
    }
    return id;
  }

  /// 단계 하나를 검사하고 판정을 기록에 남긴다 — 검사 중 예외는 할 일로 본다.
  ///
  /// [Step.check] 가 [Blocked] 를 돌려주면 계약 위반이라 [StateError] 를
  /// 던진다 — 단계 검사는 모두 여기를 거치므로 돌려준 값은 [Done] · [Todo] ·
  /// [Deferred] · [Unverifiable] 뿐이다. [Blocked] 는 위저드가 이 함수를 거치지
  /// 않고 만든다.
  Future<CheckResult> _check(Step step) async {
    CheckResult result;
    try {
      result = await step.check(context);
    } on Exception catch (e) {
      result = Todo('검사하지 못했습니다 — $e');
    }
    if (result is Blocked) throw _buildBlockedCheckError(step);
    _logCheck(step, result);
    return result;
  }

  /// 검사 판정을 `<id> <✓|✗|?> <문장>` 꼴로 기록에 남긴다.
  void _logCheck(Step step, CheckResult result) {
    final String line = switch (result) {
      Done(:final String summary) => '✓ $summary',
      Todo(:final String reason) => '✗ $reason',
      Deferred(:final String reason) => '✗ $reason',
      Unverifiable(:final String note) => '? $note',
      Blocked(:final String waitingFor) => '? $waitingFor 뒤에 검사합니다',
    };
    context.log.write('check', '${step.id} $line');
  }

  /// 이번 바퀴의 점검표를 한 번 출력한다.
  void _printChecklist() {
    _terminal.writeLine(checklistHeading);
    for (final Step step in _steps) {
      _terminal.writeLine(_formatCheckLine(step, _checklist[step.id]!));
    }
  }

  /// 점검표 한 줄을 만든다.
  String _formatCheckLine(Step step, CheckResult result) => switch (result) {
    Done(:final String summary) => '  ✓ ${step.title} — $summary',
    Todo(:final String reason) => '  ✗ ${step.title} — $reason',
    Deferred(:final String reason) => '  ✗ ${step.title} — $reason',
    Unverifiable(:final String note) => '  ? ${step.title} — $note',
    Blocked(:final String waitingFor) =>
      '  ? ${step.title} — $waitingFor 뒤에 검사합니다',
  };

  /// 단계 하나를 진행한다 — 계속하면 null, 끝내야 하면 종료 코드를 돌려준다.
  ///
  /// 실패하거나 실행 뒤에도 끝나지 않으면 다시 시도 · 멈춤을 고르게 한다. 다시
  /// 시도는 먼저 다시 검사한다 — 위저드 밖에서 이미 끝냈으면 실행하지 않고 ✓ 로
  /// 넘어간다. 검사 · 재검사가 할 수 없음 · 확인할 수 없음이거나 사용자가 미루면
  /// 그 줄을 끝 목록에 모으고 다음 단계로 간다(멈춤이 아니다).
  ///
  /// 의존 단계 가운데 이번 실행에서 ✓ 로 끝나지 않은 것이 있으면 검사 · 실행하지
  /// 않고 앞 단계 대기로 끝 목록에 넣는다. 단계 머리에서 점검표와 같은 종류로 다시
  /// 판정된 줄은 다시 쓰지 않는다 — 끝 목록에만 한 번 더 보인다.
  Future<int?> _runStep(Step step) async {
    final String? waitingFor = _findUnfinishedDependency(step, _results);
    if (waitingFor != null) {
      final blocked = Blocked(waitingFor);
      _logCheck(step, blocked);
      _settle(step, blocked, shouldSkipSameKind: true);
      return null;
    }
    final CheckResult current = await _check(step);
    if (current is! Todo) {
      _settle(step, current, shouldSkipSameKind: true);
      return null;
    }
    final String? userDeferral = _userDeferrals[step.id];
    if (userDeferral != null) {
      _deferByUser(step, userDeferral);
      return null;
    }
    _terminal.writeLine('');
    _terminal.writeLine('▶ ${step.title}');
    _terminal.writeLine('  ${current.reason}');
    _printPlannedLines(step);
    switch (_askToProceed(step)) {
      case _ProceedDecision.proceed:
        break;
      case _ProceedDecision.defer when step is DeferrableStep:
        _deferByUser(step, step.deferLabel);
        return null;
      case _ProceedDecision.defer || _ProceedDecision.stop:
        return _stop();
    }

    while (true) {
      final StepOutcome outcome = await _apply(step);
      switch (outcome) {
        // 목록을 다시 만들 수 있으면 다음 바퀴의 점검표로 간다. 다시 만들 수
        // 없으면 아래 갈래에서 실행을 마친 것처럼 다시 검사한다.
        case Replan() when _replan():
          return null;
        case Applied() || Replan():
          final CheckResult after = await _check(step);
          if (after is! Todo) {
            _settle(step, after);
            return null;
          }
          _printFailure(after.reason, null);
        case DeferredByUser(:final String note):
          _deferByUser(step, note);
          return null;
        case ExitForUser(:final String guide):
          _terminal.writeLine(guide);
          _terminal.writeLine(exitForUserTailLine);
          return wizardExitForUser;
        case WaitForUser(:final String guide):
          return await _waitForUser(step, guide);
        case Failed(:final String summary, :final CommandResult? result):
          _printFailure(summary, result);
        case Declined():
          return _stop();
      }
      // 여기에 오는 것은 실행 뒤 미완료 · 실패 두 갈래뿐이다.
      switch (await _decideRetry(step)) {
        case _RetryDecision.stop:
          return _stop();
        case _RetryDecision.finished:
          return null;
        case _RetryDecision.rerun:
          continue;
      }
    }
  }

  /// 실패 뒤 다시 시도 · 멈춤을 고르게 하고, 다시 시도면 먼저 다시 검사한다.
  ///
  /// 이미 끝났으면 ✓ 줄을 보이고 실행하지 않는다. 아직 할 일이면 다시 실행한다.
  Future<_RetryDecision> _decideRetry(Step step) async {
    if (!_chooseRetry()) return _RetryDecision.stop;
    final CheckResult recheck = await _check(step);
    if (recheck is Todo) return _RetryDecision.rerun;
    _settle(step, recheck);
    return _RetryDecision.finished;
  }

  /// 할 일이 아닌 판정 [result] 로 [step] 을 마무리하고 진행 줄을 보인다.
  ///
  /// 이번 바퀴의 최신 판정에 적어 뒤 단계의 의존 판정이 쓰게 한다. 끝나지 않은
  /// 판정([Deferred] · [Unverifiable] · [Blocked])은 끝 목록에도 모은다 —
  /// [shouldSkipSameKind] 가 true 이고 점검표 판정과 같은 종류면 진행 줄은 쓰지
  /// 않는다. [Todo] 는 호출한 쪽이 먼저 갈라 실행으로 가므로 여기 오면
  /// 프로그래밍 오류다.
  void _settle(
    Step step,
    CheckResult result, {
    bool shouldSkipSameKind = false,
  }) {
    final String line = _formatCheckLine(step, result);
    switch (result) {
      case Todo():
        throw StateError('${step.id} 단계는 아직 할 일이라 마무리할 수 없습니다');
      case Done():
        _terminal.writeLine(line);
      case Deferred() || Unverifiable() || Blocked():
        if (!shouldSkipSameKind || !_isSameKind(_checklist[step.id], result)) {
          _terminal.writeLine(line);
        }
        _remainingLines.add(line);
    }
    _results[step.id] = result;
  }

  /// [before] 와 [after] 가 같은 종류의 끝나지 않은 판정이면 true.
  bool _isSameKind(CheckResult? before, CheckResult after) =>
      switch ((before, after)) {
        (Deferred(), Deferred()) ||
        (Unverifiable(), Unverifiable()) ||
        (Blocked(), Blocked()) => true,
        _ => false,
      };

  /// [step] 을 사용자가 [note] 사유로 미룬 것으로 마무리한다.
  ///
  /// 이번 실행 동안만 기억한다 — 파일로 남기지 않는다.
  void _deferByUser(Step step, String note) {
    _userDeferrals[step.id] = note;
    _settle(step, Deferred(note));
  }

  /// 단계 진행 여부를 묻는다.
  ///
  /// [DeferrableStep] 은 진행 · 미루기 · 멈춤 셋 가운데 고르게 한다 — 기본값이
  /// 없어 Enter 만 치면 다시 묻는다. 그 밖의 단계는 y/N 으로 묻는다. 입력 끝은
  /// 멈춤이다.
  _ProceedDecision _askToProceed(Step step) {
    if (step is! DeferrableStep) {
      return _terminal.confirm(stepConfirmQuestion)
          ? _ProceedDecision.proceed
          : _ProceedDecision.stop;
    }
    final int? choice = _terminal.choose(failureChoiceQuestion, <String>[
      step.proceedLabel,
      step.deferLabel,
      stopOption,
    ], defaultIndex: null);
    return switch (choice) {
      0 => _ProceedDecision.proceed,
      1 => _ProceedDecision.defer,
      _ => _ProceedDecision.stop,
    };
  }

  /// [step] 의 검사가 [Blocked] 를 돌려줬을 때의 프로그래밍 오류를 만든다.
  ///
  /// [Blocked] 는 위저드가 앞 단계를 기다리는 단계에만 붙이는 판정이다 —
  /// [Step.check] 는 [Done] · [Todo] · [Deferred] · [Unverifiable] 만 돌려준다.
  StateError _buildBlockedCheckError(Step step) => StateError(
    '${step.id} 단계의 check 가 Blocked 를 돌려줬습니다 — '
    'check 는 Done · Todo · Deferred · Unverifiable 만 돌려줍니다',
  );

  /// 안내를 보이고 Enter 를 기다려 그 자리에서 다시 검사한다.
  ///
  /// 끝났으면 null, 입력 끝이면 멈춤 종료 코드를 돌려준다. 아직이면 사유를 보이고
  /// 다시 기다린다.
  Future<int?> _waitForUser(Step step, String guide) async {
    while (true) {
      _terminal.writeLine(guide);
      if (!_terminal.waitForEnter(waitForEnterMessage)) return _stop();
      final CheckResult after = await _check(step);
      if (after is! Todo) {
        _settle(step, after);
        return null;
      }
      _terminal.writeLine('  아직 끝나지 않았습니다 — ${after.reason}');
    }
  }

  /// 실패 뒤 다시 시도 · 멈춤을 고르게 한다 — 다시 시도면 true.
  bool _chooseRetry() {
    final int? choice = _terminal.choose(failureChoiceQuestion, const <String>[
      retryOption,
      stopOption,
    ], defaultIndex: 1);
    return choice == 0;
  }

  /// 단계를 실행한다 — 실행 중 예외는 실패로 본다.
  Future<StepOutcome> _apply(Step step) async {
    try {
      return await step.apply(context);
    } on Exception catch (e) {
      return Failed('실행하지 못했습니다 — $e');
    }
  }

  /// 단계가 실행할 명령 줄을 출력한다 — `(` 로 시작하는 줄은 안내 줄이다.
  ///
  /// [Step.isCostlyOrIrreversible] 단계는 끝에 값 표를 한 번 더 확인한다는 안내
  /// 줄을 붙인다 — 단계 y 하나로 끝나지 않는다는 것을 미리 알린다.
  void _printPlannedLines(Step step) {
    for (final String line in step.plannedCommandLines(context)) {
      if (line.startsWith('(')) {
        _terminal.writeLine('    $line');
      } else {
        _terminal.writeCommand(line);
      }
    }
    if (step.isCostlyOrIrreversible) {
      _terminal.writeLine('    $costlyStepNotice');
    }
  }

  /// 실패 요약과 명령 출력 원문을 그대로 보인다.
  ///
  /// 실행 중에 이미 화면에 흘린 출력([CommandResult.isOutputShown])은 다시 쓰지
  /// 않고 요약 줄만 보인다 — 흘린 출력은 그때 실행 기록에도 남았다.
  void _printFailure(String summary, CommandResult? result) {
    _terminal.writeLine('  실패 — $summary');
    if (result == null || result.isOutputShown) return;
    for (final text in <String>[result.stdout, result.stderr]) {
      if (text.isEmpty) continue;
      _terminal.writeRaw(text.endsWith('\n') ? text : '$text\n');
    }
  }

  /// 멈춤 줄을 출력하고 멈춤 종료 코드를 돌려준다.
  int _stop() {
    _terminal.writeLine(stopLine);
    return wizardExitStopped;
  }
}

/// [steps] 를 [context] 로 진행하고 종료 코드(0 · 1 · 3)를 돌려준다.
///
/// [onCompleted] 는 할 수 있는 단계를 모두 지났을 때(종료 코드 0 직전)에만
/// 부른다 — 이미 모든 단계가 끝난 저장소의 재실행 · 끝 목록에 남은 일이 있는
/// 실행도 포함한다. 단계가 [Replan] 을 돌려주면
/// [rebuildSteps] 로 새 목록을 받아 점검표부터 다시 돈다([maxReplans] 회까지).
Future<int> runWizard(
  WizardContext context,
  List<Step> steps, {
  WizardCompletion? onCompleted,
  StepListBuilder? rebuildSteps,
}) => Wizard(
  context,
  steps,
  onCompleted: onCompleted,
  rebuildSteps: rebuildSteps,
).run();
