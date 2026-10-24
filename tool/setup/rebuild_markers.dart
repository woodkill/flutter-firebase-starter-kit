/// 실행 경계를 넘는 다시 빌드 신호를 `.setup/` 의 flavor 별 표지 파일로 남긴다.
///
/// 위저드 판정 상태(`WizardSession`)는 메모리라 실행이 끝나면 사라진다. 앞 실행에서
/// App Check 디버그 토큰을 등록하거나 빌드 입력 파일을 바꾼 뒤 「앱 실행 · 로그인
/// 확인」 까지 가지 못하고 멈추면, 다음 실행의 실행 단계가 이 표지로 다시 빌드할지
/// 판정한다. 표지는 둘이다.
///
/// - 마지막 띄움 표지([buildLastLaunchMarkerPath]) — 앱을 띄운(`flutter run` 종료
///   코드 0) 때의 빌드 입력 합성 해시([computeBuildInputsHash]) 한 값.
/// - App Check 빌드 대기 표지([buildAppCheckPendingMarkerPath]) — 디버그 토큰을
///   새로 등록한 뒤 아직 앱을 띄우지 않았다는 뜻의 빈 파일.
///
/// 표지에는 합성 해시 한 값만 쓰고 파일 내용 · 파일별 지문은 쓰지 않는다 — 화면 ·
/// 실행 기록에도 쓰지 않는다. `.setup/` 은 `.gitignore` 의 `/.setup/` 로 저장소에
/// 들어가지 않고, 디렉터리는 0700 · 파일은 0600 이다. 표지를 읽거나 쓰거나 지우다
/// 실패해도 위저드를 실패시키지 않는다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'file_mode.dart';
import 'flavor.dart';
import 'wizard.dart';

/// 다시 빌드 표지를 두는 폴더 — 저장소 루트 기준.
///
/// `.setup/` 은 gitignored 이고 `flutter clean` 에도 지워지지 않는다.
const String rebuildMarkerDirectory = '.setup';

/// [flavor] 의 마지막 띄움 표지 경로(저장소 루트 기준).
String buildLastLaunchMarkerPath(Flavor flavor) =>
    '$rebuildMarkerDirectory/last-launch-${flavor.name}.sha256';

/// [flavor] 의 App Check 빌드 대기 표지 경로(저장소 루트 기준).
String buildAppCheckPendingMarkerPath(Flavor flavor) =>
    '$rebuildMarkerDirectory/app-check-rebuild-pending-${flavor.name}';

/// [digests] 의 `경로=지문` 줄을 키 순서대로 이은 문자열의 sha256 16진 값을
/// 돌려준다.
///
/// 지문이 null 인 경로(파일 없음)는 `경로=` 로 잇는다. [digests] 는
/// `readBuildInputDigests` 결과(빌드 입력 경로 순서)를 넘긴다.
String computeBuildInputsHash(Map<String, String?> digests) {
  final buffer = StringBuffer();
  for (final MapEntry<String, String?> entry in digests.entries) {
    buffer.writeln('${entry.key}=${entry.value ?? ''}');
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}

/// [context] flavor 의 마지막 띄움 표지가 있고 [current] 합성 해시와 다르면
/// true 다.
///
/// 표지가 없으면 false 다 — 위저드로 앱을 띄운 적이 없는 트리는 지금처럼
/// 판정한다. 표지가 있는데 읽지 못하거나 내용이 해시 꼴이 아니면 true 다 —
/// 같은지 확인할 수 없을 때는 빌드를 놓치지 않는 쪽(다시 빌드 1회 뒤 표지를
/// 새로 씀)을 고른다.
bool hasBuildInputsChangedSinceLastLaunch(
  WizardContext context,
  Map<String, String?> current,
) {
  final file = File(context.resolve(buildLastLaunchMarkerPath(context.flavor)));
  if (!file.existsSync()) return false;
  final String saved;
  try {
    saved = file.readAsStringSync().trim();
  } on FileSystemException {
    // 권한 실패 · UTF-8 디코딩 실패 모두 readAsStringSync 가 이 예외로 던진다.
    return true;
  }
  return saved != computeBuildInputsHash(current);
}

/// [context] flavor 의 App Check 빌드 대기 표지가 있으면 true 다.
bool hasAppCheckRebuildPending(WizardContext context) => File(
  context.resolve(buildAppCheckPendingMarkerPath(context.flavor)),
).existsSync();

/// [context] flavor 의 App Check 빌드 대기 표지를 남긴다 — App Check 단계가
/// 디버그 토큰을 새로 등록한 자리에서 부른다.
void markAppCheckRebuildPending(WizardContext context) {
  _writeMarker(context, buildAppCheckPendingMarkerPath(context.flavor), '');
}

/// 앱을 띄운 뒤 부른다 — 마지막 띄움 표지에 [digests] 합성 해시를 쓰고 App
/// Check 빌드 대기 표지를 지운다.
void recordAppLaunchMarkers(
  WizardContext context,
  Map<String, String?> digests,
) {
  _writeMarker(
    context,
    buildLastLaunchMarkerPath(context.flavor),
    '${computeBuildInputsHash(digests)}\n',
  );
  _deleteMarker(context, buildAppCheckPendingMarkerPath(context.flavor));
}

/// [relativePath] 표지에 [content] 를 쓴다 — 디렉터리 0700 · 파일 0600.
///
/// 내용을 쓰기 전에 빈 파일로 만들어 권한부터 좁힌다. 실패하면 조용히 그친다 —
/// 중간에 실패해 남은 빈 · 옛 표지는 읽는 쪽에서 「바뀜」 · 「대기」 로 보여
/// 빌드를 놓치지 않는다.
void _writeMarker(WizardContext context, String relativePath, String content) {
  final file = File(context.resolve(relativePath));
  try {
    file.parent.createSync(recursive: true);
    restrictFileMode(file.parent.path, ownerOnlyDirectoryMode);
    file.writeAsStringSync('');
    restrictFileMode(file.path, ownerOnlyFileMode);
    file.writeAsStringSync(content, flush: true);
  } on FileSystemException {
    return;
  } on ProcessException {
    return;
  }
}

/// [relativePath] 표지를 지운다 — 없거나 지우지 못하면 조용히 그친다.
///
/// 지우지 못한 대기 표지는 다음 실행에서 다시 빌드 1회를 더 부를 뿐이다.
void _deleteMarker(WizardContext context, String relativePath) {
  final file = File(context.resolve(relativePath));
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    return;
  }
}
