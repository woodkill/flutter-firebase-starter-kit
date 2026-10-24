/// 위저드가 `.setup/` 아래에 만드는 디렉터리 · 파일의 권한을 좁히는 함수.
///
/// 실행 기록(`log_sink.dart`)과 다시 빌드 표지(`rebuild_markers.dart`)가 함께
/// 쓴다 — 디렉터리는 소유자만 열 수 있게(0700), 파일은 소유자만 읽고 쓸 수
/// 있게(0600) 만든다.
library;

import 'dart:io';

/// 소유자만 열 수 있는 디렉터리 권한.
const String ownerOnlyDirectoryMode = '700';

/// 소유자만 읽고 쓸 수 있는 파일 권한.
const String ownerOnlyFileMode = '600';

/// 고정 인자로 `chmod` 를 실행해 [target] 의 권한을 [mode] 로 좁힌다.
///
/// 종료 코드가 0 이 아니면 [FileSystemException] 을 던진다. `chmod` 를 실행하지
/// 못하면 [ProcessException] 이 그대로 나간다.
void restrictFileMode(String target, String mode) {
  final ProcessResult result = Process.runSync('chmod', <String>[mode, target]);
  if (result.exitCode != 0) {
    throw FileSystemException('권한을 $mode 로 바꾸지 못했습니다', target);
  }
}
