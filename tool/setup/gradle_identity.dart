import 'dart:io';

/// Gradle 의 `applicationId = "…"` 줄 — group 1 = 앱 ID.
///
/// 완료 요약 · 앱 등록 검사 · 앱 정체성 판정이 모두 이 정규식 하나로 읽어야
/// 세 곳이 같은 값을 본다.
final RegExp _applicationIdPattern = RegExp(r'applicationId\s*=\s*"([^"]+)"');

/// [gradleFilePath] 의 Gradle 파일에서 첫 `applicationId` 값을 읽는다.
///
/// 파일이 없거나 `applicationId` 줄이 없으면 null. 읽기 실패는
/// [FileSystemException] 으로 그대로 던진다.
String? readGradleApplicationId(String gradleFilePath) {
  final File file = File(gradleFilePath);
  if (!file.existsSync()) return null;
  return _applicationIdPattern.firstMatch(file.readAsStringSync())?.group(1);
}
