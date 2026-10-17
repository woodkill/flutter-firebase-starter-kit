import 'dart:io';

/// Functions 소스 디렉터리(저장소 상대 경로).
const String functionsSourceDirectory = 'functions/src';

/// `defineSecret("NAME")` 선언 — group 1 = secret 이름. 인자 앞뒤 공백 · 줄바꿈을
/// 허용하고, 따옴표 이름이 없는 `defineSecret()` 언급(주석 등)은 잡지 않는다.
final RegExp defineSecretPattern = RegExp(
  r'defineSecret\(\s*"([A-Z0-9_]+)"\s*\)',
);

/// [projectRoot] 의 Functions 소스가 선언한 secret 이름을 정렬 · 중복 제거해 돌려준다.
///
/// [functionsSourceDirectory] 아래 `.ts` 파일을 재귀로 읽는다. `test` 디렉터리
/// 안 파일과 `.test.ts` 파일은 뺀다. Firebase CLI 는 배포할 함수와 관계없이 코드가
/// 선언한 secret 전부를 확인하므로, 이 목록이 배포 전에 있어야 하는 secret 이다.
/// 소스 디렉터리가 없으면 빈 목록이다.
List<String> extractDeclaredSecretNames(String projectRoot) {
  final source = Directory('$projectRoot/$functionsSourceDirectory');
  if (!source.existsSync()) return <String>[];
  final prefix = '${source.path}/';
  final names = <String>{};
  for (final FileSystemEntity entity in source.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final String path = entity.path;
    if (!path.endsWith('.ts') || path.endsWith('.test.ts')) continue;
    final String relative = path.startsWith(prefix)
        ? path.substring(prefix.length)
        : path;
    final List<String> segments = relative.split('/');
    if (segments.sublist(0, segments.length - 1).contains('test')) continue;
    for (final RegExpMatch match in defineSecretPattern.allMatches(
      entity.readAsStringSync(),
    )) {
      names.add(match.group(1)!);
    }
  }
  return names.toList()..sort();
}
