// CJK 시험 글꼴 subset 스크립트(scripts/subset_cjk.py)의 잘못된 호출 처리를
// 실행해 고정한다 (Phase 21 TOOL-02 · D-34 — 리뷰 WR-03 · IN-05 · WR-04).
//
// 잘못 부르면 traceback 대신 한 줄 안내 + 종료 코드 1 로 끝나야 한다. 가드
// 6종(fontTools 없음 · 인자 0개 · 인자 2개 · 원본 없음 · 작업 위치 아님 · ARB
// 파일 없음)과, 가드가 올바른 입력에 과하게 반응하지 않음을 보이는 양성
// 대조(sha256 불일치까지 도달)를 고정한다.
//
// 고정력: 가짜 fontTools(빈 subset · 껍데기 TTFont)로는 build 가 첫 줄에서
// traceback 으로 죽어, 어떤 가드를 빼도 파일이 써지지 않는다. 그래서 「첫
// 쓰기 전에 멈춘다」 는 안내 원문 · traceback 부재 단언이 지키고(가드를 빼면
// 다음 가드의 안내나 traceback 이 나온다) `writtenCount == 0` 은 보조 단언이다.
// 실제 쓰기 순서(두 ARB 를 읽은 뒤 build)는 실제 원본이 있어야 해 시험 밖이다.
//
// 결정성: 호스트의 fontTools 설치 여부와 무관해야 한다. fontTools 없음 경우는
// `-S`(site-packages · user site 를 sys.path 에 넣지 않음)로 돌리고 PYTHONPATH
// 를 빈 디렉터리로 덮어써(키를 빼면 부모 환경 값이 상속된다) 진짜
// ModuleNotFoundError 를 낸다. 나머지 경우는 PYTHONPATH 앞의 가짜 fontTools
// 패키지가 설치본을 가린다(`-I` 는 PYTHONPATH 를 무시하므로 쓰지 않는다).
// 스크립트는 저장소 루트를 cwd 로 돌리지 않는다 — 항상 임시 sandbox 에서 돌려
// 추적 중인 assets/test_fonts 를 건드리지 않는다. 임시 디렉터리는 테스트가 끝나면
// 지운다.
//
// scripts/ 는 공개 mirror 에도 실리므로 .planning/ 에 기대지 않는다.
//
// **값 모양 리터럴을 두지 않는다** — digest 는 정규식으로만 대조한다.

import 'dart:convert';
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

/// 스크립트에 fontTools 를 보이는 방식.
enum _Stub {
  /// fontTools 를 찾을 수 없다(`-S` + 빈 PYTHONPATH — 진짜 ModuleNotFoundError).
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
    Directory('${root.path}/no-fonttools').createSync();
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

  /// cwd 아래에 lib/l10n(최소 ARB `{}` 두 개) · 빈 assets/test_fonts 를 만든다.
  void makeRepoLayout() {
    Directory('$cwd/lib/l10n').createSync(recursive: true);
    for (final locale in <String>['ko', 'ja']) {
      File('$cwd/lib/l10n/app_$locale.arb').writeAsStringSync('{}\n');
    }
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
///
/// [_Stub.missing] 이면 `-S` 를 앞에 붙이고 PYTHONPATH 를 빈 디렉터리로 둔다.
/// 스크립트는 `-X utf8` 로 쓰므로 stdout · stderr 를 UTF-8 로 읽는다 — 기본값
/// systemEncoding 은 Windows 에서 활성 code page 라 한국어 안내가 깨진다.
ProcessResult _run(_Sandbox box, _Stub stub, List<String> args) {
  final isMissing = stub == _Stub.missing;
  return Process.runSync(
    'python3',
    <String>[if (isMissing) '-S', '-X', 'utf8', _scriptPath(), ...args],
    workingDirectory: box.cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: <String, String>{
      'PYTHONPATH': isMissing
          ? '${box.dir}/no-fonttools'
          : '${box.dir}/stub-present',
    },
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

  test('T-21-SUBSET-07 app_ja.arb 가 없으면 sha256 · build 전에 그 파일 안내로 끝난다', () {
    box.makeRepoLayout();
    File('${box.cwd}/lib/l10n/app_ja.arb').deleteSync();
    final String err = _expectCleanFailure(
      _run(box, _Stub.present, <String>[box.makeFakeSource()]),
    );
    expect(err.trim(), 'ARB 파일이 없다: lib/l10n/app_ja.arb');
    expect(box.writtenCount, 0);
  }, skip: skip);
}
