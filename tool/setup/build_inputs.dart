/// 빌드 입력 파일의 경로와 지문(sha256)을 읽고, 코드 생성 파일이 없는지 본다.
///
/// 위저드 실행 단계가 앱을 다시 빌드해야 하는지 판정하는 데 쓴다 — 파일별 지문은
/// 메모리(`WizardSession`)에만 두고 화면 · 기록에 쓰지 않는다. 실행 경계를 넘는
/// 판정은 `rebuild_markers.dart` 가 합성 해시 한 값을 표지로 남긴다. 위저드
/// 진입점은 [runSetupWizard] 로 시작 지문을 남긴 뒤 위저드를 실행한다.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'flavor.dart';
import 'step.dart';
import 'wizard.dart';

/// [flavor] 앱 빌드에 들어가는 사용자 파일 · 설정 파일의 저장소 상대 경로를
/// 돌려준다.
///
/// 순서는 config(`config/<flavor>.json`) · xcconfig · Dart 설정 파일 · iOS
/// Firebase 설정 파일 · Android Firebase 설정 파일이다.
List<String> buildInputPaths(Flavor flavor) {
  final paths = FlavorPaths(flavor);
  return <String>[
    paths.json,
    paths.xcconfig,
    paths.dartOptions,
    paths.iosPlist,
    paths.androidJson,
  ];
}

/// [context] flavor 의 빌드 입력 파일마다 파일 바이트의 sha256 16진 지문을 읽는다.
///
/// 키는 [buildInputPaths] 의 저장소 상대 경로 그대로 · 같은 순서다. 파일이
/// 없거나 읽지 못하면 그 경로의 값은 null 이다.
Map<String, String?> readBuildInputDigests(WizardContext context) =>
    <String, String?>{
      for (final String path in buildInputPaths(context.flavor))
        path: _readDigest(context.resolve(path)),
    };

/// [absolutePath] 파일 바이트의 sha256 16진 지문 — 없거나 읽지 못하면 null.
String? _readDigest(String absolutePath) {
  try {
    return sha256.convert(File(absolutePath).readAsBytesSync()).toString();
  } on FileSystemException {
    return null;
  }
}

/// [before] 와 [after] 지문 사이에서 값이 다른 경로를 [after] 의 키 순서로
/// 돌려준다 — 같으면 빈 목록.
///
/// 파일이 새로 생긴 경로(null → 지문) · 사라진 경로(지문 → null)도 바뀐 것으로
/// 본다. 경로만 돌려주고 지문 값은 돌려주지 않는다.
List<String> findChangedBuildInputs(
  Map<String, String?> before,
  Map<String, String?> after,
) => <String>[
  for (final MapEntry<String, String?> entry in after.entries)
    if (before[entry.key] != entry.value) entry.key,
];

/// 이번 실행을 시작할 때의 빌드 입력 지문을 [context] 세션에 한 번만 남긴다.
///
/// 이미 남겼으면 그대로 둔다 — 실행 단계가 이 지문과 지금 지문을 비교해 이번
/// 실행에서 빌드 입력이 바뀌었는지 판정한다.
void recordBuildInputsAtStart(WizardContext context) {
  context.session.buildInputsAtStart ??= readBuildInputDigests(context);
}

/// 코드 생성 지시문(`part '<이름>.g.dart';` · `part '<이름>.freezed.dart';`) 꼴.
final RegExp _generatedPartDirective = RegExp(
  r"^part '([^']+\.(g|freezed)\.dart)';",
);

/// [projectRoot] 의 `lib` 아래 소스가 가리키는 코드 생성 파일 가운데 없는 것이
/// 하나라도 있으면 true 다.
///
/// `lib` 아래 `.dart` 파일(이름이 `.g.dart` · `.freezed.dart` 로 끝나는 생성 파일은
/// 건너뜀)의 코드 생성 지시문마다 그 소스 파일 디렉터리 기준으로 대상 파일이
/// 있는지 보고, 처음 찾은 없는 자리에서 멈춘다. `part of` 줄은 지시문이 아니다.
/// 고정 파일 이름 하나가 아니라 지시문이 가리키는 파일의 존재로 판정하므로 킷
/// 사용자가 데모 파일을 지워도 맞다. `lib` 이 없으면 false 이고, 읽지 못하는
/// 파일은 건너뛴다.
bool hasMissingGeneratedParts(String projectRoot) {
  final lib = Directory('$projectRoot/lib');
  if (!lib.existsSync()) return false;
  final List<FileSystemEntity> entities;
  try {
    entities = lib.listSync(recursive: true, followLinks: false);
  } on FileSystemException {
    return false;
  }
  for (final entity in entities) {
    if (entity is! File || !_isHandWrittenDartFile(entity.path)) continue;
    final List<String> lines;
    try {
      lines = entity.readAsLinesSync();
    } on FileSystemException {
      continue;
    }
    for (final line in lines) {
      final RegExpMatch? match = _generatedPartDirective.firstMatch(line);
      if (match == null) continue;
      if (!File('${entity.parent.path}/${match.group(1)}').existsSync()) {
        return true;
      }
    }
  }
  return false;
}

/// [path] 가 손으로 쓴 `.dart` 소스(코드 생성 파일이 아님)인지 본다.
bool _isHandWrittenDartFile(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.g.dart') &&
    !path.endsWith('.freezed.dart');

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
