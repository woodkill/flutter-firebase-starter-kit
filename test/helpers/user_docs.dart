// 사용자 문서 시험(`test/docs/`)이 검사할 파일을 규칙으로 모으는 헬퍼.
//
// 대상은 파일 이름이 아니라 규칙으로 고른다 — tracked md 가운데 비공개 작업 일지 ·
// Claude 설정 · 유지보수자 문서 디렉터리 아래와 Claude 지시 파일(어느 디렉터리든
// `CLAUDE.md`)을 뺀 전부에, 설정 위저드가 사용자 파일로 복사하는 예시 파일을 더한다.
// 새 md 가 생기면 시험을 고치지 않아도 대상에 든다.
//
// 다시 쓰기 목록([kDocsAwaitingRewrite])은 아직 금지 패턴이 남은 대상 파일이다. 그
// 파일을 다시 쓴 작업이 같은 커밋에서 목록에서 빼고, 목록이 비면 상수째 지운다.
// [kRetiringManualPath] 는 두 가이드로 나뉘어 곧 지워질 원본 매뉴얼이다 — 링크 · 실
// 값 시험은 이 파일을 검사 출발점에서 빼고, 파일을 지우는 작업이 상수도 함께 지운다.

import 'dart:convert';
import 'dart:io';

/// 사용자 문서 대상에서 빼는 디렉터리 접두(저장소 루트 기준)다.
///
/// 비공개 작업 일지 · Claude 설정 · 유지보수자 문서는 사용자 문서 규칙의 대상이
/// 아니다.
const List<String> kUserDocExcludedPrefixes = <String>[
  '.planning/',
  '.claude/',
  'docs/maintainer/',
];

/// 어느 디렉터리에 있든 대상에서 빼는 Claude 지시 파일 이름이다.
const String kClaudeInstructionFileName = 'CLAUDE.md';

/// 설정 위저드가 사용자 파일로 복사하는 예시 파일 — md 가 아니어도 대상에 든다.
const List<String> kUserExampleFiles = <String>[
  'ios/Flutter/dev.example.xcconfig',
  'ios/Flutter/stg.example.xcconfig',
  'ios/Flutter/prod.example.xcconfig',
  'extensions/firestore-send-email.env.example',
];

/// 아직 금지 패턴이 남아 다시 쓰기를 기다리는 대상 파일이다.
///
/// 목록 밖 대상은 금지 패턴 0 건을 단언받고, 목록 안 파일은 대상이면서 아직 1건
/// 이상 남아 있어야 한다 — 다시 쓴 파일을 목록에서 빼지 않으면 시험이 실패해 목록이
/// 줄어들게 한다.
const Set<String> kDocsAwaitingRewrite = <String>{
  'README.md',
  'assets/brand/apple/README.md',
  'assets/brand/google/README.md',
  'assets/fonts/googlesans/README.md',
  'assets/fonts/roboto/README.md',
  'assets/images/splash/README.md',
  'assets/test_fonts/README.md',
  'docs/manual.md',
  'ios/Flutter/dev.example.xcconfig',
  'ios/Flutter/prod.example.xcconfig',
  'ios/Flutter/stg.example.xcconfig',
};

/// 두 가이드로 나뉘어 지워질 원본 매뉴얼 경로다.
const String kRetiringManualPath = 'docs/manual.md';

/// 디렉터리 순회 대체 경로에서 들어가지 않는 디렉터리 이름이다(어느 깊이든).
const Set<String> _walkSkippedDirectoryNames = <String>{
  '.git',
  '.dart_tool',
  '.fvm',
  'build',
  'node_modules',
};

/// 디렉터리 순회 대체 경로에서 들어가지 않는 디렉터리 경로다(저장소 루트 기준).
const Set<String> _walkSkippedDirectoryPaths = <String>{'ios/Pods'};

/// [path](저장소 루트 기준)가 사용자 문서 md 인지 돌려준다.
///
/// `.md` 로 끝나고, [kUserDocExcludedPrefixes] 아래가 아니고, 파일 이름이
/// [kClaudeInstructionFileName] 이 아니면 참이다. 예시 파일은 md 가 아니므로 여기서
/// 고르지 않는다 — [collectUserDocTargets] 가 따로 더한다.
bool isUserDocPath(String path) {
  if (!path.endsWith('.md')) {
    return false;
  }
  for (final String prefix in kUserDocExcludedPrefixes) {
    if (path.startsWith(prefix)) {
      return false;
    }
  }
  return path.split('/').last != kClaudeInstructionFileName;
}

/// `git ls-files -z` 로 tracked 파일 경로 집합(저장소 루트 기준)을 돌려준다.
///
/// git 이 없거나 저장소가 아니어서 실패하면 `null` 을 돌려준다 — 호출자가 파일 존재
/// 검사나 디렉터리 순회로 대신한다. 실행 위치는 `flutter test` 의 CWD(프로젝트
/// 루트)다.
Set<String>? listTrackedFiles() {
  final ProcessResult result;
  try {
    result = Process.runSync('git', <String>[
      'ls-files',
      '-z',
    ], stdoutEncoding: utf8);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  return (result.stdout as String)
      .split('\u0000')
      .where((String path) => path.isNotEmpty)
      .toSet();
}

/// 사용자 문서 md 경로를 정렬해 돌려준다.
///
/// tracked 파일([listTrackedFiles])에서 [isUserDocPath] 로 고른다. git 을 쓸 수 없으면
/// 디렉터리를 순회해 같은 규칙을 적용한다 — 그때는 `.gitignore` 를 읽지 않으므로
/// 빌드 산출물 · 도구 캐시 · 의존성 디렉터리(`build/` · `.dart_tool/` · `.fvm/` ·
/// `node_modules/` · `ios/Pods/`)에 들어가지 않는다.
List<String> collectUserDocPaths() {
  final Iterable<String> candidates = listTrackedFiles() ?? _walkRepoFiles();
  return candidates.where(isUserDocPath).toList()..sort();
}

/// 사용자 문서 시험의 대상 — 사용자 문서 md 와 실재하는 예시 파일 — 을 정렬해
/// 돌려준다.
List<String> collectUserDocTargets() => <String>[
  ...collectUserDocPaths(),
  ...kUserExampleFiles.where((String path) => File(path).existsSync()),
]..sort();

/// 저장소 루트부터 파일 경로(루트 기준 상대 경로)를 모은다 — 건너뛰는 디렉터리에는
/// 들어가지 않고 심볼릭 링크는 따라가지 않는다.
List<String> _walkRepoFiles() {
  final files = <String>[];
  final pending = <Directory>[Directory('.')];
  while (pending.isNotEmpty) {
    final Directory directory = pending.removeLast();
    for (final FileSystemEntity entity in directory.listSync(
      followLinks: false,
    )) {
      final String relative = _toRepoRelative(entity.path);
      if (entity is Directory) {
        if (!_isSkippedDirectory(relative)) {
          pending.add(entity);
        }
      } else if (entity is File) {
        files.add(relative);
      }
    }
  }
  return files;
}

/// `./` 로 시작하는 순회 경로를 저장소 루트 기준 상대 경로로 바꾼다.
String _toRepoRelative(String path) =>
    path.startsWith('./') ? path.substring(2) : path;

/// 순회에서 들어가지 않는 디렉터리인지 돌려준다.
bool _isSkippedDirectory(String relative) =>
    _walkSkippedDirectoryPaths.contains(relative) ||
    _walkSkippedDirectoryNames.contains(relative.split('/').last);
