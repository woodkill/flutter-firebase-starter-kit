import 'command_runner.dart';
import 'wizard.dart';

/// 값이 아직 없는 secret 을 만들어 둘 때 쓰는 자리표시 값 — 이 값은 「없음」 과
/// 같게 본다.
const String secretPlaceholderValue = 'unset';

/// Firebase CLI 가 없는 secret 을 읽을 때 출력에 쓰는 HTTP 상태 조각.
const String secretNotFoundStatusMarker = '404';

/// Firebase CLI 가 없는 secret 을 읽을 때 출력에 쓰는 문장 조각.
const String secretNotFoundTextMarker = 'not found';

/// [projectId] 의 Secret Manager [name] 최신 값을 읽는 명령.
///
/// 표준 출력이 비밀 값이라 민감 출력으로 실행한다.
Command buildSecretReadCommand(String name, String projectId) => Command(
  'firebase',
  <String>['functions:secrets:access', name, '--project', projectId],
  isOutputSensitive: true,
);

/// [projectId] 의 Secret Manager [name] 에 [value] 를 새 버전으로 쓰는 명령.
///
/// 값은 표준 입력으로만 넘기고, 화면 · 기록에는 값 대신 [valueLabel] 을 넣은
/// `printf '<valueLabel>' | …` 표시형을 보인다. 출력은 민감 출력으로 실행한다.
Command buildSecretWriteCommand(
  String name,
  String projectId, {
  required String value,
  required String valueLabel,
}) => Command(
  'firebase',
  <String>[
    'functions:secrets:set',
    name,
    '--project',
    projectId,
    '--data-file',
    '-',
  ],
  stdinText: value,
  display:
      "printf '$valueLabel' | firebase functions:secrets:set $name "
      '--project $projectId --data-file -',
  isOutputSensitive: true,
);

/// Secret Manager 값 읽기 결과.
sealed class SecretRead {
  /// 하위 클래스만 만든다.
  const SecretRead();
}

/// 값을 읽었다 — 값은 읽자마자 가림 함수에 등록돼 있다.
final class SecretFound extends SecretRead {
  /// 읽은 [value] 로 만든다.
  const SecretFound(this.value);

  /// 읽은 값(앞뒤 공백을 뗀 값).
  final String value;
}

/// secret 이 없거나 버전이 없다.
final class SecretMissing extends SecretRead {
  /// 없음 결과를 만든다.
  const SecretMissing();
}

/// 읽지 못했다 — 권한 · 네트워크 등.
final class SecretReadFailed extends SecretRead {
  /// 실패 [reason] 과 표준 출력을 뗀 [result] 로 만든다.
  const SecretReadFailed(this.reason, this.result);

  /// 실패 요약.
  final String reason;

  /// 표준 출력을 뗀 명령 결과(오류 원문).
  final CommandResult result;
}

/// [projectId] 의 Secret Manager [name] 값을 읽는다.
///
/// 성공하면 값을 [WizardContext.redactor] 에 등록한 뒤 [SecretFound] 를 돌려준다.
/// Firebase CLI 는 없는 secret 의 오류(`HTTP Error: 404 … not found or has no
/// versions`)를 표준 출력에 쓰므로, 실패 출력에 [secretNotFoundStatusMarker] 와
/// [secretNotFoundTextMarker] 가 함께 있으면 [SecretMissing] 이다. 그 밖의 실패는
/// [SecretReadFailed] 다.
Future<SecretRead> readSecret(
  WizardContext context,
  String name,
  String projectId,
) async {
  final CommandResult result = await context.runner.capture(
    buildSecretReadCommand(name, projectId),
  );
  if (result.isSuccess) {
    final String value = result.stdout.trim();
    context.redactor.register(value);
    return SecretFound(value);
  }
  final String output = '${result.stdout}\n${result.stderr}';
  if (output.contains(secretNotFoundStatusMarker) &&
      output.contains(secretNotFoundTextMarker)) {
    return const SecretMissing();
  }
  return SecretReadFailed(
    'Secret Manager 의 $name 을 읽지 못했습니다 (종료 코드 ${result.exitCode})',
    result.withoutStdout(),
  );
}
