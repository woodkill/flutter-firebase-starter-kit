// 홈 화면 앱 아이콘 시험 도우미 — 진짜 PNG 바이트 · 홈 화면 아이콘 20장 ·
// 표식 · 실제 git 임시 저장소 · git 만 실제로 돌리는 실행기.
//
// 단계 시험 · 흐름 시험 · 되돌림 시험이 함께 쓴다. 킷 기본 아이콘은 저장소의
// tracked 아이콘을 복사하지 않고 짧은 바이트와 그 지문 표를 주입해 만든다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import 'fakes.dart';

final Map<int, Uint8List> _opaqueRgbCache = <int, Uint8List>{};

/// 한 변 [side] 의 불투명 3채널(color type 2) PNG 바이트를 만든다.
///
/// 가장자리와 가운데 색이 다른 그림이라 가장자리 평균색이 흰색 · 검정이 아니다.
/// 같은 [side] 는 한 번만 만들어 재사용한다.
Uint8List buildOpaqueRgbIconPng({int side = 1024}) => _opaqueRgbCache
    .putIfAbsent(side, () => img.encodePng(_paintIcon(side, numChannels: 3)));

/// 한 변 [side] 의 알파 채널이 있는(color type 6) PNG 바이트를 만든다 — 모든
/// 픽셀의 알파는 255 다.
Uint8List buildOpaqueRgbaIconPng({int side = 1024}) =>
    img.encodePng(_paintIcon(side, numChannels: 4));

/// 한 변 [side] 의 투명 로고 PNG 바이트를 만든다.
///
/// 가장자리는 완전 투명, 가운데 원은 불투명, 그 둘레 고리는 반투명이다.
Uint8List buildTransparentLogoPng({int side = 1024}) {
  final image = img.Image(width: side, height: side, numChannels: 4);
  final double center = side / 2;
  final double inner = side * 0.3;
  final double outer = side * 0.36;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final double dx = x + 0.5 - center;
      final double dy = y + 0.5 - center;
      final double distance = dx * dx + dy * dy;
      if (distance <= inner * inner) {
        image.setPixelRgba(x, y, 200, 40, 60, 255);
      } else if (distance <= outer * outer) {
        image.setPixelRgba(x, y, 200, 40, 60, 128);
      } else {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return img.encodePng(image);
}

/// 불투명한 시험 그림 — 가장자리 띠 · 가운데 네모의 색이 다르다.
img.Image _paintIcon(int side, {required int numChannels}) {
  final image = img.Image(width: side, height: side, numChannels: numChannels);
  final int band = side ~/ 8;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final bool isEdge =
          x < band || y < band || x >= side - band || y >= side - band;
      if (isEdge) {
        image.setPixelRgba(x, y, 30, 90, 160, 255);
      } else {
        image.setPixelRgba(x, y, 250, 210, 40, 255);
      }
    }
  }
  return image;
}

/// [bytes] 의 sha256 소문자 16진을 계산한다.
String computeDigest(List<int> bytes) => sha256.convert(bytes).toString();

/// [root] 저장소의 [relativePath] 에 [bytes] 를 쓴다(부모 폴더를 만든다).
void _writeRepoFile(String root, String relativePath, List<int> bytes) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

/// [root] 저장소에 「내 아이콘」 20장을 쓴다.
///
/// iOS 1024 는 [buildOpaqueRgbIconPng] 결과(진짜 불투명 RGB PNG)이고, 나머지는
/// 킷 지문과 다른 짧은 바이트(`mine:<경로>`)다.
void writeMyHomeIcons(String root) {
  for (final HomeIconFile file in homeIconFiles) {
    _writeRepoFile(
      root,
      file.relativePath,
      file.relativePath == ios1024Path
          ? buildOpaqueRgbIconPng()
          : utf8.encode('mine:${file.relativePath}'),
    );
  }
}

/// [root] 저장소에 킷 기본 자리의 20장(`kit:<경로>` 바이트)을 쓰고 경로 → sha256
/// 표를 돌려준다 — 단계 생성자에 지문으로 주입한다.
Map<String, String> writeKitDefaultHomeIcons(String root) {
  final digests = <String, String>{};
  for (final HomeIconFile file in homeIconFiles) {
    final List<int> bytes = utf8.encode('kit:${file.relativePath}');
    _writeRepoFile(root, file.relativePath, bytes);
    digests[file.relativePath] = computeDigest(bytes);
  }
  return digests;
}

/// [root] 저장소의 지금 iOS 1024 바이트 sha256 을 읽는다.
String readHomeIconDigest(String root) =>
    computeDigest(File('$root/$ios1024Path').readAsBytesSync());

/// [root] 저장소의 지금 iOS 1024 지문으로 [tokens] 수단마다 한 줄씩 쓴 표식
/// 본문 — 줄은 `<sha256> <token>` 이고 token 순이다.
String buildHomeIconMarkerText(String root, Iterable<String> tokens) {
  final String digest = readHomeIconDigest(root);
  final List<String> sorted = tokens.toList()..sort();
  return sorted.map((String token) => '$digest $token\n').join();
}

/// [root] 저장소에 지금 iOS 1024 지문의 표식을 쓴다 — 줄은 [tokens] 수단마다
/// 하나이고, 없으면 콘솔 아이콘 칸이 있는 모든 수단이다.
void writeHomeIconMarker(String root, {Iterable<String>? tokens}) {
  File('$root/$homeIconMarkerPath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      buildHomeIconMarkerText(
        root,
        tokens ?? iconSpecs.map((IconSpec spec) => spec.token),
      ),
    );
}

/// [root] 저장소의 앱 아이콘 쓰기 대상 가운데 지금 파일로 있는 것 — 링크를
/// 따라가지 않은 종류가 파일인 경로만 [AppIconStep.listWritePaths] 순서로 고른다.
List<String> listExistingWriteTargets(String root) => <String>[
  for (final String path in AppIconStep.listWritePaths())
    if (FileSystemEntity.typeSync('$root/$path', followLinks: false) ==
        FileSystemEntityType.file)
      path,
];

/// [root] 의 지금 파일로 있는 쓰기 대상을 모두 추적 파일로 답하는 `git ls-files`
/// 명령 키와 결과 — 파일로 있는 대상이 없으면 null(단계가 git 을 부르지 않는다).
///
/// 키는 등록하는 순간의 디스크 상태로 정해지므로 대상 파일을 다 둔 뒤에 부른다.
({String key, CommandResult result})? buildTrackedTargetsAnswer(String root) {
  final List<String> existing = listExistingWriteTargets(root);
  if (existing.isEmpty) return null;
  return (
    key: FakeCommandRunner.buildKey(
      AppIconStep.buildTrackedFilesCommand(existing),
    ),
    result: CommandResult(
      0,
      existing.map((String path) => '$path\n').join(),
      '',
    ),
  );
}

/// 가짜 실행기 [runner] 에 [root] 의 [buildTrackedTargetsAnswer] 를 등록한다 —
/// 파일로 있는 대상이 없으면 아무것도 등록하지 않는다.
void registerTrackedFiles(FakeCommandRunner runner, String root) {
  final ({String key, CommandResult result})? answer =
      buildTrackedTargetsAnswer(root);
  if (answer != null) runner.on(answer.key, answer.result);
}

/// [root] 저장소용 git 실행 환경 — 부모의 `GIT_*` 를 빼고 사용자 · 시스템 설정을
/// 끈다. [root] 의 부모에서 저장소 찾기를 멈춘다.
Map<String, String> buildGitFixtureEnvironment(String root) => <String, String>{
  for (final MapEntry<String, String> entry in Platform.environment.entries)
    if (!entry.key.startsWith('GIT_')) entry.key: entry.value,
  'GIT_CONFIG_GLOBAL': '/dev/null',
  'GIT_CONFIG_NOSYSTEM': '1',
  'GIT_ATTR_NOSYSTEM': '1',
  'GIT_CEILING_DIRECTORIES': Directory(root).parent.path,
};

/// [root] 저장소에서 실제 git 을 [arguments] 로 실행한다.
ProcessResult runFixtureGit(
  String root,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.runSync(
  'git',
  arguments,
  workingDirectory: workingDirectory ?? root,
  environment: buildGitFixtureEnvironment(root),
  includeParentEnvironment: false,
);

/// [root] 저장소에서 실제 git 을 실행하고 실패면 [StateError] 로 알린다.
String _runFixtureGitChecked(String root, List<String> arguments) {
  final ProcessResult result = runFixtureGit(root, arguments);
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} 실패: ${result.stderr}');
  }
  return result.stdout as String;
}

/// [root] 를 빈 git 저장소로 만든다.
///
/// 사용자 전역 ignore 파일(`~/.config/git/ignore` 등)이 시험 경로를 숨기지 않게
/// 저장소 설정의 `core.excludesFile` 을 빈 파일로 둔다 — 위저드가 부르는 git 도
/// 이 설정을 읽는다.
void initGitFixture(String root) {
  _runFixtureGitChecked(root, const <String>['init', '-q']);
  _runFixtureGitChecked(root, const <String>[
    'config',
    'core.excludesFile',
    '/dev/null',
  ]);
}

/// [root] 저장소의 모든 파일을 [message] 로 커밋한다 — 서명 · hook 없이.
void commitGitFixture(String root, String message) {
  _runFixtureGitChecked(root, const <String>['add', '--all']);
  _runFixtureGitChecked(root, <String>[
    '-c',
    'user.name=fixture',
    '-c',
    'user.email=fixture@example.invalid',
    '-c',
    'commit.gpgsign=false',
    '-c',
    'core.hooksPath=/dev/null',
    'commit',
    '-q',
    '--allow-empty',
    '-m',
    message,
  ]);
}

/// git 은 [root] 저장소에서 실제로 돌리고 그 밖 명령은 가짜 실행기에 넘기는 실행기.
///
/// git 은 작업 디렉터리가 [root] 안일 때만 돌린다. 그 밖 명령의 결과 · 효과는
/// 가짜 실행기 [fake] 에 등록한 대로다.
final class IconFlowRunner implements CommandRunner {
  /// [root] 저장소와 가짜 실행기 [fake] 로 실행기를 만든다.
  IconFlowRunner(this.root, this.fake);

  /// git 을 실제로 돌릴 저장소 루트.
  final String root;

  /// git 밖 명령을 받을 가짜 실행기.
  final FakeCommandRunner fake;

  /// 실제 git 으로 실행한 명령 키(순서대로).
  final List<String> gitKeys = <String>[];

  /// 실제 git 명령의 작업 디렉터리(순서대로).
  final List<String?> gitWorkingDirectories = <String?>[];

  Future<CommandResult> _execute(RunMode mode, Command command) async {
    final String key = FakeCommandRunner.buildKey(command);
    if (command.executable != 'git') {
      return await switch (mode) {
        RunMode.capture => fake.capture(command),
        RunMode.stream => fake.stream(command),
        RunMode.interactive => CommandResult(
          await fake.interactive(command),
          '',
          '',
        ),
      };
    }
    final String? directory = command.workingDirectory;
    if (directory == null ||
        (directory != root && !directory.startsWith('$root/'))) {
      throw StateError('fixture 밖 git 실행: $key');
    }
    gitKeys.add(key);
    gitWorkingDirectories.add(directory);
    final ProcessResult result = runFixtureGit(
      root,
      command.arguments,
      workingDirectory: directory,
    );
    return CommandResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  @override
  Future<CommandResult> capture(Command command) =>
      _execute(RunMode.capture, command);

  @override
  Future<int> interactive(Command command) async =>
      (await _execute(RunMode.interactive, command)).exitCode;

  @override
  Future<CommandResult> stream(Command command) =>
      _execute(RunMode.stream, command);
}

/// 파일 하나에 주입할 실패 종류.
enum FileFault {
  /// 고른 차례의 `writeAsBytesSync` 가 아무것도 쓰지 않고 실패한다.
  failWrite,

  /// 고른 차례의 `writeAsBytesSync` 가 앞 절반만 쓰고 실패한다.
  partialWrite,

  /// `deleteSync` 가 늘 실패한다.
  failDelete,
}

/// 고른 절대 경로의 [File] 에만 실패를 주입하는 [IOOverrides].
///
/// `File(path)` 생성자가 [IOOverrides.current] 를 따르므로
/// [IOOverrides.runWithIOOverrides] 안의 실행이 그 경로로 만든 파일만 감싼다 —
/// 그 밖 경로는 실제 파일 그대로다. 쓰기 차례는 경로마다 1부터 세고, 같은 경로의
/// 파일 객체를 새로 만들어도 이어서 센다.
final class FileFaultOverrides extends IOOverrides {
  /// 절대 경로 → (실패 종류 · 실패시킬 쓰기 차례) 표 [faults] 로 만든다.
  FileFaultOverrides(this.faults);

  /// 절대 경로 → (실패 종류 · 실패시킬 쓰기 차례). 지우기 실패는 차례를 보지 않는다.
  final Map<String, ({FileFault fault, int call})> faults;

  final Map<String, int> _writeCalls = <String, int>{};

  /// 주입한 실패가 실제로 일어난 경로(순서대로).
  final List<String> firedPaths = <String>[];

  @override
  File createFile(String path) {
    final File real = super.createFile(path);
    final ({FileFault fault, int call})? fault = faults[path];
    return fault == null ? real : _FaultyFile(real, this, fault);
  }

  /// [path] 의 쓰기 차례를 하나 올려 돌려준다.
  int _countWrite(String path) =>
      _writeCalls[path] = (_writeCalls[path] ?? 0) + 1;
}

/// [FileFaultOverrides] 가 고른 경로에 돌려주는 파일 — 단계가 쓰는 멤버만 실제
/// 파일에 넘기고 나머지는 [UnsupportedError] 다.
final class _FaultyFile implements File {
  _FaultyFile(this._real, this._owner, this._fault);

  final File _real;
  final FileFaultOverrides _owner;
  final ({FileFault fault, int call}) _fault;

  /// 주입한 실패 예외를 만든다.
  FileSystemException _buildFault(String operation) {
    _owner.firedPaths.add(_real.path);
    return FileSystemException(
      '$operation 실패(주입)',
      _real.path,
      const OSError('주입한 실패', 5),
    );
  }

  @override
  String get path => _real.path;

  @override
  Directory get parent => _real.parent;

  @override
  bool existsSync() => _real.existsSync();

  @override
  Uint8List readAsBytesSync() => _real.readAsBytesSync();

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    final int call = _owner._countWrite(_real.path);
    if (call == _fault.call) {
      switch (_fault.fault) {
        case FileFault.failWrite:
          throw _buildFault('쓰기');
        case FileFault.partialWrite:
          _real.writeAsBytesSync(
            bytes.sublist(0, bytes.length ~/ 2),
            mode: mode,
            flush: true,
          );
          throw _buildFault('쓰기');
        case FileFault.failDelete:
          break;
      }
    }
    _real.writeAsBytesSync(bytes, mode: mode, flush: flush);
  }

  @override
  void deleteSync({bool recursive = false}) {
    if (_fault.fault == FileFault.failDelete) throw _buildFault('지우기');
    _real.deleteSync(recursive: recursive);
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('주입 파일이 넘기지 않는 멤버: ${invocation.memberName}');
}
