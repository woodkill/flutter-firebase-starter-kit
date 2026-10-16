import 'command_runner.dart';
import 'wizard.dart';

/// 단계 검사 결과 — 끝남 · 할 일 · 앞 단계 대기 세 가지.
sealed class CheckResult {
  /// 하위 클래스만 만든다.
  const CheckResult();
}

/// 이미 끝난 단계.
final class Done extends CheckResult {
  /// 끝난 상태를 [summary] 로 요약한다.
  const Done(this.summary);

  /// 점검표에 보일 요약.
  final String summary;
}

/// 해야 할 일이 남은 단계.
final class Todo extends CheckResult {
  /// 남은 일을 [reason] 으로 적는다.
  const Todo(this.reason);

  /// 점검표 · 단계 머리에 보일 사유.
  final String reason;
}

/// 앞 단계가 끝나야 검사할 수 있는 단계.
///
/// 점검표가 끝나지 않은 앞 단계를 가진 단계에만 붙이는 판정이다 —
/// [Step.check] 는 이 값을 돌려주지 않는다.
final class Blocked extends CheckResult {
  /// [waitingFor] 단계가 끝나기를 기다린다.
  const Blocked(this.waitingFor);

  /// 기다리는 단계의 제목.
  final String waitingFor;
}

/// 단계 실행 결과.
sealed class StepOutcome {
  /// 하위 클래스만 만든다.
  const StepOutcome();
}

/// 실행을 마쳤다 — 위저드가 다시 검사해 끝났는지 판정한다.
final class Applied extends StepOutcome {
  /// 실행을 마친 결과를 만든다.
  const Applied();
}

/// 위저드 밖에서 오래 걸리는 작업이 필요하다 — 안내 후 위저드를 끝낸다.
final class ExitForUser extends StepOutcome {
  /// 사용자에게 보일 [guide] 로 만든다.
  const ExitForUser(this.guide);

  /// 사용자가 할 일 안내.
  final String guide;
}

/// 위저드 밖에서 짧은 작업이 필요하다 — 안내 후 Enter 를 기다려 다시 검사한다.
final class WaitForUser extends StepOutcome {
  /// 사용자에게 보일 [guide] 로 만든다.
  const WaitForUser(this.guide);

  /// 사용자가 할 일 안내.
  final String guide;
}

/// 실행이 실패했다 — 위저드가 원문을 보이고 다시 시도 · 멈춤을 고르게 한다.
final class Failed extends StepOutcome {
  /// 실패를 [summary] 로 요약하고, 명령 결과가 있으면 [result] 로 넘긴다.
  const Failed(this.summary, {this.result});

  /// 실패 요약.
  final String summary;

  /// 실패한 명령의 결과(출력 원문). 없으면 null.
  final CommandResult? result;
}

/// 단계 안의 추가 확인에서 사용자가 아니요를 골랐다 — 위저드를 멈춘다.
final class Declined extends StepOutcome {
  /// 거절 결과를 만든다.
  const Declined();
}

/// 실행이 단계 목록을 바꿨다 — 위저드가 목록을 다시 만들고 점검표부터 다시 돈다.
///
/// 목록을 다시 만들 수 없는 위저드(다시 만드는 함수가 없음 · 횟수 상한)는
/// [Applied] 와 같이 다시 검사만 한다.
final class Replan extends StepOutcome {
  /// 다시 짜기 결과를 만든다.
  const Replan();
}

/// 위저드 단계 하나 — 검사 · 실행할 명령 · 실행을 같은 모양으로 갖는다.
abstract interface class Step {
  /// 다른 단계가 [dependsOn] 으로 가리키는 고유 이름.
  String get id;

  /// 점검표 · 단계 머리에 보일 제목.
  String get title;

  /// 이 단계보다 먼저 끝나야 하는 단계의 [id] 목록.
  List<String> get dependsOn;

  /// 직전 [check] 판정(현재 모드)으로 실행하면 비용이 들거나 되돌릴 수 없는
  /// 선택의 값 표(확인 표)를 보일 수 있으면 true.
  ///
  /// 위저드는 이 값이 true 일 때 계획 줄 끝에 값 표 재확인 안내를 붙인다. 같은
  /// 단계라도 값 표 없이 끝나는 모드(실패 전용 · 표시 이름만 쓰기 등)에서는
  /// false 를 돌려준다 — 보인 안내와 실제 실행이 어긋나지 않게 한다.
  bool get isCostlyOrIrreversible;

  /// 읽기 전용으로 상태를 검사한다 — [Done] · [Todo] 만 돌려준다.
  ///
  /// [Blocked] 는 위저드의 점검표가 만드는 판정이라 여기서 돌려주면 위저드가
  /// [StateError] 로 멈춘다.
  Future<CheckResult> check(WizardContext context);

  /// 실행 전에 보일 명령 줄 목록을 만든다.
  ///
  /// 직전 [check] 결과에 따라 필요한 명령만 돌려줘도 된다. `(` 로 시작하는 줄은
  /// 명령이 아닌 안내 줄로 `$` 머리 없이 보인다.
  List<String> plannedCommandLines(WizardContext context);

  /// 단계를 실행한다.
  Future<StepOutcome> apply(WizardContext context);
}
