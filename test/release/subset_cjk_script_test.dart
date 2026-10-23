// CJK 시험 글꼴 subset 스크립트(scripts/subset_cjk.py)의 잘못된 호출 처리를
// 실행해 고정한다 (Phase 21 TOOL-02 · D-34 — 리뷰 WR-03 · IN-05).
//
// 잘못 부르면 traceback 대신 한 줄 안내 + 종료 코드 1 로 끝나야 하고, 첫 쓰기
// (build) 전에 멈춰 아무것도 쓰지 않아야 한다. 가드 5종(fontTools 없음 · 인자
// 0개 · 인자 2개 · 원본 없음 · 작업 위치 아님)과, 가드가 올바른 입력에 과하게
// 반응하지 않음을 보이는 양성 대조(sha256 불일치까지 도달)를 고정한다.
//
// 결정성: 호스트의 fontTools 설치 여부와 무관하도록 PYTHONPATH 앞에 가짜
// fontTools 패키지를 둔다(`-I` 는 PYTHONPATH 를 무시하므로 쓰지 않는다).
// 스크립트는 저장소 루트를 cwd 로 돌리지 않는다 — 항상 임시 sandbox 에서 돌려
// 추적 중인 assets/test_fonts 를 건드리지 않는다. 임시 디렉터리는 테스트가 끝나면
// 지운다.
//
// scripts/ 는 공개 mirror 에도 실리므로 .planning/ 에 기대지 않는다.
//
// **값 모양 리터럴을 두지 않는다** — digest 는 정규식으로만 대조한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _scriptRel = 'scripts/subset_cjk.py';
const String _usageHead = '사용법: python -X utf8 ';
const String _usageArg = '<NotoSansCJK-Regular.ttc 경로>';

/// 스크립트가 없거나 python3 를 실행할 수 없으면 사유 문자열, 아니면 `false`.
Object _skipUnlessPython() {
  if (!File(_scriptRel).existsSync()) {
    return '$_scriptRel 이 없는 사본 — 건너뜀';
  }
  try {
    final ProcessResult r = Process.runSync('python3', <String>['--version']);
    return r.exitCode == 0 ? false : 'python3 실행 실패 — 건너뜀';
  } on ProcessException {
    return 'python3 가 없다 — 건너뜀';
  }
}

/// 가짜 fontTools 패키지의 종류.
enum _Stub {
  /// import 하면 ModuleNotFoundError.
  missing,

  /// import 되는 빈 패키지(subset · ttLib.TTFont 노출).
  present,
}

/// 테스트 하나가 쓰는 임시 작업 공간.
class _Sandbox {
  _Sandbox._(this.dir);

  /// 임시 디렉터리를 만들고 stub · cwd 하위 폴더를 채운다.
  factory _Sandbox.create() {
    final Directory root = Directory.systemTemp.createTempSync(
      'test-subset-cjk-',
    );
    Directory(
      '${root.path}/stub-missing/fontTools',
    ).createSync(recursive: true);
    File(
      '${root.path}/stub-missing/fontTools/__init__.py',
    ).writeAsStringSync('raise ModuleNotFoundError("fontTools")\n');
    Directory(
      '${root.path}/stub-present/fontTools/ttLib',
    ).createSync(recursive: true);
    File(
      '${root.path}/stub-present/fontTools/__init__.py',
    ).writeAsStringSync('');
    File('${root.path}/stub-present/fontTools/subset.py').writeAsStringSync('');
    File(
      '${root.path}/stub-present/fontTools/ttLib/__init__.py',
    ).writeAsStringSync('class TTFont:\n    pass\n');
    Directory('${root.path}/cwd').createSync();
    return _Sandbox._(root.path);
  }

  /// 임시 디렉터리 절대경로.
  final String dir;

  /// 스크립트를 돌릴 cwd.
  String get cwd => '$dir/cwd';

  /// cwd 아래에 lib/l10n · assets/test_fonts 를 빈 채로 만든다.
  void makeRepoLayout() {
    Directory('$cwd/lib/l10n').createSync(recursive: true);
    Directory('$cwd/assets/test_fonts').createSync(recursive: true);
  }

  /// 내용이 다른 작은 가짜 원본 파일을 만들어 경로를 돌려준다.
  String makeFakeSource() {
    final f = File('$dir/fake.ttc')..writeAsStringSync('not a font\n');
    return f.path;
  }

  /// assets/test_fonts 에 들어 있는 항목 수.
  int get writtenCount => Directory('$cwd/assets/test_fonts').listSync().length;

  /// 임시 디렉터리를 지운다.
  void dispose() {
    final d = Directory(dir);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
    }
  }
}

/// 스크립트 절대경로.
String _scriptPath() => '${Directory.current.path}/$_scriptRel';

/// 문서화된 방식(`python3 -X utf8 <스크립트> <인자>`)으로 sandbox 에서 돌린다.
ProcessResult _run(_Sandbox box, _Stub stub, List<String> args) {
  final stubDir = stub == _Stub.missing
      ? '${box.dir}/stub-missing'
      : '${box.dir}/stub-present';
  return Process.runSync(
    'python3',
    <String>['-X', 'utf8', _scriptPath(), ...args],
    workingDirectory: box.cwd,
    environment: <String, String>{'PYTHONPATH': stubDir},
  );
}

/// 공통 단언: 종료 코드 1 · traceback 없음. stderr 를 돌려준다.
String _expectCleanFailure(ProcessResult r) {
  final err = r.stderr as String;
  expect(r.exitCode, 1, reason: 'stderr: $err');
  expect(err, isNot(contains('Traceback')));
  return err;
}

void main() {
  final Object skip = _skipUnlessPython();
  late _Sandbox box;

  setUp(() => box = _Sandbox.create());
  tearDown(() => box.dispose());

  test('T-21-SUBSET-01 fontTools 가 없으면 traceback 없이 설치 안내로 끝난다', () {
    box.makeRepoLayout();
    final ProcessResult r = _run(box, _Stub.missing, <String>[
      box.makeFakeSource(),
    ]);
    final String err = _expectCleanFailure(r);
    expect(
      err.trim(),
      'fonttools 가 없다 — 머리 주석의 venv 명령으로 설치한 뒤 '
      '그 python 으로 돌린다.',
    );
    expect(box.writtenCount, 0);
  }, skip: skip);

  test('T-21-SUBSET-02 인자가 없으면 사용법 한 줄로 끝난다', () {
    box.makeRepoLayout();
    final String err = _expectCleanFailure(
      _run(box, _Stub.present, <String>[]),
    );
    expect(err.trim(), startsWith(_usageHead));
    expect(err, contains(_usageArg));
    expect(box.writtenCount, 0);
  }, skip: skip);

  test('T-21-SUBSET-03 인자가 둘이면 사용법 한 줄로 끝난다', () {
    box.makeRepoLayout();
    final String err = _expectCleanFailure(
      _run(box, _Stub.present, <String>['a.ttc', 'b.ttc']),
    );
    expect(err.trim(), startsWith(_usageHead));
    expect(err, contains(_usageArg));
    expect(box.writtenCount, 0);
  }, skip: skip);

  test('T-21-SUBSET-04 없는 원본 경로는 원본 파일이 없다 안내로 끝난다', () {
    box.makeRepoLayout();
    final missing = '${box.dir}/nope.ttc';
    final String err = _expectCleanFailure(
      _run(box, _Stub.present, <String>[missing]),
    );
    expect(err.trim(), '원본 파일이 없다: $missing');
    expect(box.writtenCount, 0);
  }, skip: skip);

  test('T-21-SUBSET-05 저장소 루트가 아니면 작업 위치 안내로 끝나고 쓰지 않는다', () {
    final String src = box.makeFakeSource();
    final String err = _expectCleanFailure(
      _run(box, _Stub.present, <String>[src]),
    );
    expect(err.trim(), 'lib/l10n · assets/test_fonts 가 없다 — 저장소 루트에서 돌린다.');
    expect(Directory('${box.cwd}/assets').existsSync(), isFalse);
  }, skip: skip);

  test('T-21-SUBSET-06 올바른 입력은 가드를 지나 sha256 불일치까지 가고 쓰지 않는다', () {
    box.makeRepoLayout();
    final String err = _expectCleanFailure(
      _run(box, _Stub.present, <String>[box.makeFakeSource()]),
    );
    expect(err.trim(), matches(RegExp(r'^원본 sha256 불일치: [0-9a-f]{64}$')));
    expect(box.writtenCount, 0);
  }, skip: skip);
}
