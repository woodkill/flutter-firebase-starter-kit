/// 위저드 진입 실행 — 시작 빌드 입력 지문을 남긴 뒤 위저드를 실행한다.
///
/// 위저드 진입점(`bin/setup.dart`)이 이 파일의 [runSetupWizard] 만 부른다.
/// `build_inputs.dart` 는 `wizard.dart` 를 가져오므로 순환을 피해 진입 함수를
/// 따로 둔다.
library;

import 'build_inputs.dart';
import 'step.dart';
import 'wizard.dart';

/// 위저드 진입점이 부르는 실행 — 시작 빌드 입력 지문을 남긴 뒤 같은 인자로
/// [runWizard] 를 불러 그 종료 코드를 돌려준다.
///
/// 위저드 진입점(`bin/setup.dart`)이 부른다 — [runWizard] 를 직접 부르는 시험
/// 문맥은 시작 지문이 없어 빌드 입력 변경을 판정하지 않는다. 지문은 첫 검사
/// 전에 남긴다.
Future<int> runSetupWizard(
  WizardContext context,
  List<Step> steps, {
  WizardCompletion? onCompleted,
  StepListBuilder? rebuildSteps,
}) {
  recordBuildInputsAtStart(context);
  return runWizard(
    context,
    steps,
    onCompleted: onCompleted,
    rebuildSteps: rebuildSteps,
  );
}
