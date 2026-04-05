// Starter Kit의 Package Name / Bundle ID를 변경하는 CLI 스크립트.
// 구현 예정 -- TDD RED 단계 스텁

/// 변경 타입.
enum ChangeType {
  /// 파일 내 문자열 치환.
  replace,

  /// 파일/디렉토리 이동.
  move,
}

/// 파일 변경 정보를 담는 클래스.
class FileChange {
  /// 파일 변경 정보를 생성한다.
  const FileChange({
    required this.filePath,
    required this.type,
    required this.description,
    required this.oldValue,
    required this.newValue,
  });

  /// 대상 파일 경로.
  final String filePath;

  /// 변경 타입.
  final ChangeType type;

  /// 변경 설명.
  final String description;

  /// 변경 전 값.
  final String oldValue;

  /// 변경 후 값.
  final String newValue;
}

/// 입력 유효성 검증 결과.
class ValidateResult {
  /// 유효성 검증 결과를 생성한다.
  const ValidateResult({required this.isValid, this.error});

  /// 유효한지 여부.
  final bool isValid;

  /// 에러 메시지 (유효하지 않을 때).
  final String? error;
}

/// 입력 유효성을 검증한다.
ValidateResult validateInputs(String org, String name) {
  throw UnimplementedError();
}

/// snake_case를 UpperCamelCase로 변환한다.
String toUpperCamelCase(String snakeCase) {
  throw UnimplementedError();
}

/// snake_case를 lowerCamelCase로 변환한다.
String toLowerCamelCase(String snakeCase) {
  throw UnimplementedError();
}

/// snake_case를 Title Case(공백 구분)로 변환한다.
String toTitleCase(String snakeCase) {
  throw UnimplementedError();
}

/// 프로젝트 내 변경 대상을 수집한다.
List<FileChange> collectChanges(
  String projectRoot,
  String newOrg,
  String newName,
) {
  throw UnimplementedError();
}

/// dry-run 결과를 콘솔에 출력한다.
void printDryRun(List<FileChange> changes, String newOrg, String newName) {
  throw UnimplementedError();
}

/// 변경 사항을 실제로 적용한다.
void applyChanges(List<FileChange> changes) {
  throw UnimplementedError();
}

/// CLI 진입점.
void main(List<String> arguments) {
  throw UnimplementedError();
}
