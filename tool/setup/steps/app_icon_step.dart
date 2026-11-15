import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../command_runner.dart';
import '../confirm.dart';
import '../file_mode.dart';
import '../git_tree.dart';
import '../icons/home_icon_specs.dart';
import '../icons/icon_pipeline.dart';
import '../providers/icon_specs.dart';
import '../providers/path_input.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../wizard.dart';

/// `sips -g` 로 읽은 이미지 크기 · 형식.
typedef ImageProbe = ({int width, int height, String format});

/// 홈 화면 아이콘 20장의 상태 — tracked 파일 바이트와 킷 기본 지문으로 가른다.
enum HomeIconState {
  /// 20장이 모두 킷 기본 지문과 같다 — 원본을 물어 새로 만든다.
  kitDefault,

  /// 20장이 모두 킷 기본 지문과 다르다 — 사용자가 고른 아이콘이다.
  mine,

  /// 일부만 킷 기본 지문과 같다 — 덮어쓰지 않는다.
  mixed,

  /// 하나라도 없거나 읽을 수 없다 — 덮어쓰지 않는다.
  missing,
}

/// 쓰다 실패한 경로 하나를 되돌리는 방법.
enum FailedWriteUndo {
  /// 쓰기 전에 있던 추적 파일 — git 으로 커밋 내용에 되돌린다.
  checkout,

  /// 이번에 새로 생긴 파일 — 지운다.
  delete,

  /// 폴더 · 링크 · 없음 — 건드리지 않는다.
  keep,
}

/// 직전 검사가 정한 실행 갈래.
enum _IconMode {
  /// 원본을 물어 홈 화면 · adaptive · 콘솔 아이콘을 모두 만든다.
  full,

  /// 원본을 묻지 않고 iOS 1024 에서 콘솔 아이콘만 다시 만든다.
  consoleOnly,

  /// 지금은 만들지 않는다(판정이 덮어쓰기를 막음 · 폴더 자리가 파일).
  deferred,

  /// 할 일이 없다.
  done,
}

/// 만들 파일 하나 — 저장소 상대 경로 · 바이트와 메모리 확인 기준.
final class _PlannedFile {
  const _PlannedFile(
    this.relativePath,
    this.bytes, {
    this.side,
    this.colorType,
    this.maxBytes,
  });

  /// 저장소 루트 기준 경로.
  final String relativePath;

  /// 쓸 바이트.
  final Uint8List bytes;

  /// PNG 면 기대하는 한 변 — PNG 가 아니면 null.
  final int? side;

  /// PNG 면 기대하는 color type — PNG 가 아니면 null.
  final int? colorType;

  /// 용량 상한 — 없으면 null.
  final int? maxBytes;
}

/// 원본 질문 결과 — 고른 원본 경로 또는 단계를 끝낼 결과 중 하나.
typedef _SourceAnswer = ({String? path, StepOutcome? outcome});

/// 그림 계산 결과 — 만들 파일 목록 또는 단계를 끝낼 결과 중 하나.
typedef _Rendered = ({List<_PlannedFile> files, StepOutcome? outcome});

/// 앱 아이콘 단계 — 원본 이미지 하나로 홈 화면 아이콘(iOS 15장 · Android legacy
/// 5장 · adaptive)과 켠 수단의 콘솔 아이콘을 함께 만든다.
///
/// 판정은 「킷 기본 그대로인가」 하나다 — 홈 화면 20장의 tracked 바이트를 킷
/// 기본 지문과 비교하고, 상태 파일로 위저드가 만든 아이콘인지 가르지 않는다.
/// 킷 기본이면 원본을 묻고, sips 로 sRGB PNG 로 바꾼 뒤 채운 그림 하나에서 모든
/// 크기를 만든다. 쓰기 전에 대상 경로의 미커밋 변경을 찾아 있으면 멈추고, 만든
/// 바이트는 메모리에서 크기 · 형식 · 용량을 확인한 뒤에만 쓴다.
final class AppIconStep implements DeferrableStep {
  /// 켠 로그인 수단 [enabledProviders] 에서 콘솔 아이콘 대상을 골라 단계를
  /// 만든다.
  ///
  /// [dependsOn] 은 기다릴 단계 id 다 — 아이콘만 다시 만드는 실행은 빈 목록을
  /// 넘긴다. [kitDefaultDigests] 는 킷 기본 지문 표(저장소 상대 경로 → sha256)를
  /// 바꿔 넣을 때만 준다 — 없으면 킷이 담은 지문이다.
  AppIconStep({
    required Set<String> enabledProviders,
    List<String> dependsOn = const <String>['providers'],
    Map<String, String>? kitDefaultDigests,
  }) : targets = selectIconTargets(enabledProviders),
       _dependsOn = dependsOn,
       _kitDigests = kitDefaultDigests ?? buildKitDefaultDigests();

  /// 단계 id.
  static const String stepId = 'app_icon';

  /// 단계 제목.
  static const String stepTitle = '앱 아이콘';

  /// 원본 경로를 다시 묻는 상한 — 맞지 않는 원본을 세 번 넣으면 멈춘다(빈 값은
  /// 언제든 지금 안 함).
  ///
  /// 콘솔 키 입력 상한(`maxKeyAttempts`)과 따로 둔다 — 키 정책이 바뀌어도 이
  /// 단계는 그대로다.
  static const int maxSourceAttempts = 3;

  /// 아이콘을 새 원본으로 다시 만드는 명령.
  static const String rebuildCommand = './setup.sh --app-icon';

  /// 아이콘을 바꾸는 법.
  static const String replaceHint = '바꾸려면: $rebuildCommand';

  /// 원본 질문 전에 보이는 안내.
  static const String sourceGuide =
      '홈 화면 앱 아이콘과 켠 로그인 수단의 콘솔 아이콘을 원본 이미지 하나로 '
      '만듭니다 — 정사각 · ${minSourceSide}x$minSourceSide 이상(PNG · JPEG · '
      'HEIC 등 — PDF · SVG 같은 벡터는 받지 않습니다). '
      'Finder 에서 파일을 이 창으로 끌어다 놓아도 됩니다';

  /// 원본 경로 질문.
  static const String sourceQuestion = '원본 이미지 경로 (빈 값 = 지금 안 함)';

  /// 원본 파일이 없을 때의 까닭 머리(뒤에 화면용 경로).
  static const String missingFileReason = '파일이 없습니다 — ';

  /// 원본 경로가 폴더일 때의 까닭 머리(뒤에 화면용 경로).
  static const String folderReason = '파일이 아니라 폴더입니다 — ';

  /// 이미지로 읽히지 않을 때의 까닭 머리(뒤에 화면용 경로).
  static const String notImageReason = '이미지 파일이 아닙니다 — ';

  /// 답을 풀어낸 경로가 빌 때(`""` · `''`)의 까닭 — 경로는 보이지 않는다.
  static const String emptyPathReason = '경로가 비었습니다';

  /// `file://` 주소를 파일 경로로 바꾸지 못할 때의 까닭 — 경로는 보이지 않는다.
  ///
  /// 따옴표로 감싼 주소는 따옴표를 벗긴 뒤 한 번 더 바꾸고 나서 가른다.
  static const String unconvertibleAddressReason = '파일 경로로 바꿀 수 없는 주소입니다';

  /// 정사각이 아닐 때의 까닭 머리(뒤에 지금 크기).
  static const String notSquareReason = '정사각 이미지가 필요합니다 — 지금 ';

  /// 하한보다 작을 때의 까닭 머리(뒤에 지금 크기).
  static const String tooSmallReason =
      '${minSourceSide}x$minSourceSide 이상이 필요합니다 — 지금 ';

  /// 상한보다 클 때의 까닭 머리(뒤에 지금 크기).
  static const String tooLargeReason = '너무 큰 이미지입니다 — 지금 ';

  /// 홈 화면 아이콘이 킷 기본 그대로일 때의 까닭.
  static const String kitDefaultReason = '킷 기본 아이콘입니다 — 원본 이미지를 묻습니다';

  /// 쓰기 대상에 커밋하지 않은 변경이 있을 때의 까닭(뒤에 경로 줄).
  static const String dirtyReason =
      '홈 화면 아이콘 파일에 커밋하지 않은 변경이 있습니다 — 커밋하거나 되돌린 뒤 '
      '다시 실행하세요';

  /// 원본을 PNG 로 바꾸지 못했을 때의 까닭 머리(뒤에 종료 코드).
  ///
  /// 원문에는 저장소 밖 원본의 절대 경로가 섞일 수 있어 종료 코드만 보인다.
  static const String convertFailedReason =
      '원본 이미지를 PNG 로 바꾸지 못했습니다 — sips 종료 코드 ';

  /// 바꾼 원본을 PNG 로 읽지 못했을 때의 까닭.
  static const String unreadableConvertedReason = '바꾼 원본을 읽지 못했습니다';

  /// 결과 표 제목.
  static const String summaryTitle = '만든 앱 아이콘';

  /// 투명한 원본일 때 배경색 질문 전에 보이는 안내.
  static const String backgroundGuide =
      '원본에 투명하거나 반투명한 픽셀이 있어 그 자리를 채울 색을 정합니다 — '
      '홈 화면 · 콘솔 아이콘과 Android adaptive 배경이 같은 색이 됩니다';

  /// 배경색 질문.
  static const String backgroundQuestion = '배경색 (#RRGGBB)';

  /// 배경색 꼴이 맞지 않을 때의 까닭.
  static const String backgroundFormatReason =
      '배경색은 #RRGGBB 꼴의 16진 6자리입니다 (예: #1A2B3C)';

  /// 이미 있던 콘솔 아이콘을 바꿨을 때의 결과 표 노트.
  static const String reuploadNote = '콘솔 아이콘이 바뀌었습니다 — 각 콘솔에 다시 올리세요';

  /// 같은 이름의 Android 아이콘 리소스가 이미 있을 때의 까닭(뒤에 경로 줄).
  static const String conflictReason =
      '같은 이름의 아이콘 리소스가 이미 있습니다 — 옮기거나 지운 뒤 다시 실행하세요 '
      '(빌드가 같은 이름 리소스를 함께 받지 못합니다)';

  /// 홈 화면 아이콘을 쓰다 실패해 되돌렸을 때의 까닭 머리(뒤에 실패 까닭).
  static const String rolledBackReason = '홈 화면 아이콘을 쓰지 못해 쓰기 전으로 되돌렸습니다 — ';

  /// 쓰다 실패한 뒤 git 되돌림도 실패했을 때의 까닭 머리(뒤에 실패 까닭).
  static const String restoreFailedReason =
      '홈 화면 아이콘을 쓰지 못했고 쓰기 전으로 되돌리지도 못했습니다 — ';

  /// git 되돌림이 실패했을 때 경로 줄 앞에 보이는 안내.
  static const String restoreGuide = '아래 파일을 git checkout -- <경로> 로 되돌리세요';

  /// 되돌릴 때 새로 만든 파일을 지우지 못했을 때 경로 줄 앞에 보이는 안내.
  static const String deleteGuide = '새로 만든 아래 파일을 지우지 못했습니다 — 지운 뒤 다시 실행하세요';

  /// adaptive 배경색 리소스 이름 — 다른 values 파일이 같은 이름을 정의하면
  /// 빌드가 실패한다.
  static const String _backgroundResourceName = 'ic_launcher_background';

  /// values XML 안의 배경색 리소스 정의(`name="…"` · 작은따옴표도 받음).
  static final RegExp _backgroundDefinitionPattern = RegExp(
    'name\\s*=\\s*["\']$_backgroundResourceName["\']',
  );

  /// mipmap 폴더에서 이 단계의 리소스와 이름이 겹치는 파일 이름(확장자 앞).
  static const Set<String> _launcherResourceNames = <String>{
    'ic_launcher',
    'ic_launcher_foreground',
  };

  static final RegExp _hexColorPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

  /// 배경색 답 [answer] 를 `0xRRGGBB` 로 읽는다 — 꼴이 맞지 않으면 null.
  ///
  /// 앞뒤 공백은 무시하고 `#` 는 있어도 없어도 된다. 16진 6자리만 받고 대소문자는
  /// 가리지 않는다 — 3자리 줄임 꼴은 받지 않는다.
  static int? parseBackgroundColor(String answer) {
    final String? hex = _hexColorPattern.firstMatch(answer.trim())?.group(1);
    return hex == null ? null : int.parse(hex, radix: 16);
  }

  /// 표식 한 줄 — `<sha256 소문자 16진 64자> <수단 token>`.
  static final RegExp _markerLinePattern = RegExp(r'^([0-9a-f]{64}) (\S+)$');

  /// 표식 본문 [text] 를 수단 token → 그 콘솔 아이콘을 만든 iOS 1024 지문 표로
  /// 읽는다.
  ///
  /// 줄마다 `<sha256> <token>` 이다. 앞뒤 공백은 무시하고 꼴이 맞지 않는 줄은
  /// 건너뛴다 — 꼴이 다른 표식은 빈 표가 되어 모든 콘솔 아이콘을 다시 만든다.
  static Map<String, String> parseMarker(String text) => <String, String>{
    for (final String line in const LineSplitter().convert(text))
      if (_markerLinePattern.firstMatch(line.trim()) case final RegExpMatch m)
        m.group(2)!: m.group(1)!,
  };

  /// 수단 token → iOS 1024 지문 표 [entries] 를 token 순 표식 본문으로 쓴다.
  static String formatMarker(Map<String, String> entries) {
    final List<String> tokens = entries.keys.toList()..sort();
    return tokens.map((String token) => '${entries[token]} $token\n').join();
  }

  /// 결과 표 끝의 올리는 법 안내를 만든다 — [iconsPath] 는 아이콘 폴더의 절대
  /// 경로이고 `~` 로 줄이지 않는다.
  ///
  /// 파일 선택 창의 ⌘⇧G 는 지금 연 폴더와 상관없이 절대 경로를 받는다. 실행
  /// 기록은 이미 저장소 절대 경로를 남긴다.
  static String buildUploadGuide(String iconsPath) =>
      '브라우저의 파일 선택 창에서 ⌘⇧G 로 $iconsPath 경로를 붙여 넣거나 '
      '열린 Finder 창에서 끌어다 놓으세요';

  /// Finder 열기가 실패했을 때의 한 줄.
  static const String openFailedNote =
      'Finder 를 열지 못했습니다 — 파일은 $iconsDirectory 에 있습니다';

  /// 원본을 쓰기 전에 미커밋 변경을 찾는 경로 — 홈 화면 20장 · adaptive 7개.
  static List<String> listWritePaths() => <String>[
    for (final HomeIconFile file in homeIconFiles) file.relativePath,
    ...listAdaptiveFilePaths(),
  ];

  /// [absolutePath] 이미지의 크기 · 형식을 읽는 명령을 만든다.
  static Command buildProbeCommand(String absolutePath) =>
      Command('/usr/bin/sips', <String>[
        '-g',
        'pixelWidth',
        '-g',
        'pixelHeight',
        '-g',
        'format',
        absolutePath,
      ]);

  /// [sourcePath] 이미지를 sRGB PNG [outputPath] 로 바꾸는 명령을 만든다.
  ///
  /// 크기는 바꾸지 않는다 — 줄이기 · 합성은 그림 계산이 한다. 화면에는 원본
  /// 자리에 [display] 를, 출력 자리에 작업 폴더의 상대 경로를 보인다.
  static Command buildConvertCommand(
    String sourcePath,
    String outputPath, {
    required String display,
  }) => Command(
    '/usr/bin/sips',
    <String>[
      '-s',
      'format',
      'png',
      '-m',
      srgbProfilePath,
      sourcePath,
      '--out',
      outputPath,
    ],
    display:
        'sips -s format png -m ${quoteForShellDisplay(srgbProfilePath)} '
        '${quoteForShellDisplay(display)} --out $iconWorkDirectory/source.png',
  );

  static final RegExp _widthPattern = RegExp(
    r'^\s*pixelWidth:\s*(\d+)\s*$',
    multiLine: true,
  );

  static final RegExp _heightPattern = RegExp(
    r'^\s*pixelHeight:\s*(\d+)\s*$',
    multiLine: true,
  );

  static final RegExp _formatPattern = RegExp(
    r'^\s*format:\s*(\w+)\s*$',
    multiLine: true,
  );

  /// `sips -g` 결과 [result] 에서 크기 · 형식을 읽는다 — 이미지가 아니면 null.
  ///
  /// `sips -g` 는 없는 파일 · 폴더 · 이미지가 아닌 파일에도 종료 코드 0 이라
  /// 종료 코드로 판정하지 않는다. 표준 오류에 `not a valid file` 이 있거나 세 값
  /// 가운데 하나라도 없거나 `<nil>` 이면 이미지가 아니다.
  static ImageProbe? parseProbe(CommandResult result) {
    if (result.stderr.contains('not a valid file')) return null;
    final int? width = int.tryParse(
      _widthPattern.firstMatch(result.stdout)?.group(1) ?? '',
    );
    final int? height = int.tryParse(
      _heightPattern.firstMatch(result.stdout)?.group(1) ?? '',
    );
    final String? format = _formatPattern.firstMatch(result.stdout)?.group(1);
    if (width == null || height == null || format == null) return null;
    return (width: width, height: height, format: format);
  }

  /// 쓰기 전에 있던 [relativePaths] 를 커밋 내용으로 되돌리는 명령을 만든다.
  ///
  /// 쓰기 전 미커밋 검사를 지난 경로만 넘긴다 — 그래서 커밋 내용이 곧 쓰기 전
  /// 내용이다. 추적하지 않는 경로가 섞이면 git 이 아무것도 되돌리지 않고 실패한다.
  static Command buildRestoreCommand(
    List<String> relativePaths, {
    String? workingDirectory,
  }) => Command('git', <String>[
    'checkout',
    '--',
    ...relativePaths,
  ], workingDirectory: workingDirectory);

  /// 쓰다 실패한 경로를 되돌리는 방법을 정한다.
  ///
  /// 쓰기 전에 있던 경로([existedBefore])는 열린 뒤 잘렸을 수 있어 git 으로
  /// 커밋 내용에 되돌린다 — 바뀌지 않은 파일을 되돌려도 해가 없다. 없던 경로는
  /// 지금 종류([currentType] · 링크를 따라가지 않은 종류)가 파일일 때만 지우고,
  /// 폴더 · 링크 · 없음은 이 단계가 만든 것이 아니므로 그대로 둔다.
  static FailedWriteUndo decideFailedWriteUndo({
    required bool existedBefore,
    required FileSystemEntityType currentType,
  }) {
    if (existedBefore) return FailedWriteUndo.checkout;
    return currentType == FileSystemEntityType.file
        ? FailedWriteUndo.delete
        : FailedWriteUndo.keep;
  }

  /// 제자리에 쓴 iOS 1024 바이트 [bytes] 가 맞지 않는 까닭을 찾는다 — 맞으면 null.
  ///
  /// 한 변 [filledIconSide] 의 정사각 · color type 2(RGB) · 투명색 청크 없음이어야
  /// 한다 — App Store 는 알파 채널이 있는 앱 아이콘을 거절한다.
  static String? findPlacedIos1024Problem(Uint8List bytes) {
    final PngHeader? header = readPngHeader(bytes);
    if (header == null) return 'PNG 로 읽지 못했습니다';
    if (header.width != filledIconSide || header.height != filledIconSide) {
      return '${filledIconSide}x$filledIconSide 가 아닙니다 — 지금 '
          '${header.width}x${header.height}';
    }
    if (header.colorType != 2 || readPngHasAlpha(bytes) != false) {
      return '알파 채널이 있습니다';
    }
    return null;
  }

  /// [projectRoot] 의 Android 리소스에서 이 단계가 쓸 리소스와 이름이 겹치는
  /// 파일을 찾아 저장소 상대 경로를 정렬해 돌려준다.
  ///
  /// `mipmap-*` 폴더의 `ic_launcher.*` · `ic_launcher_foreground.*` 가운데 이
  /// 단계가 쓰는 경로가 아닌 것과, adaptive 배경색 파일 밖의 `values*` XML 가운데
  /// 같은 배경색 이름을 정의하는 것이다. 같은 이름을 둘 받으면 빌드가 실패한다.
  /// `drawable*` 은 리소스 종류가 달라 보지 않는다. 리소스 폴더가 없으면 빈
  /// 목록이다.
  static List<String> findConflictingIconResources(String projectRoot) {
    final res = Directory('$projectRoot/$androidResDirectory');
    if (!res.existsSync()) return const <String>[];
    final Set<String> ownPaths = listWritePaths().toSet();
    final found = <String>[];
    for (final FileSystemEntity folder in res.listSync()) {
      if (folder is! Directory) continue;
      final String folderName = _readBaseName(folder.path);
      final bool isMipmap = folderName.startsWith('mipmap-');
      final bool isValues =
          folderName == 'values' || folderName.startsWith('values-');
      if (!isMipmap && !isValues) continue;
      for (final FileSystemEntity entry in folder.listSync()) {
        if (entry is! File) continue;
        final String name = _readBaseName(entry.path);
        final relativePath = '$androidResDirectory/$folderName/$name';
        if (ownPaths.contains(relativePath)) continue;
        final bool isConflict = isMipmap
            ? _launcherResourceNames.contains(name.split('.').first)
            : name.endsWith('.xml') && _hasBackgroundDefinition(entry);
        if (isConflict) found.add(relativePath);
      }
    }
    return found..sort();
  }

  /// [path] 의 마지막 이름.
  static String _readBaseName(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  /// values XML [file] 이 adaptive 배경색 이름을 정의하는지 — 읽지 못하면 false.
  static bool _hasBackgroundDefinition(File file) {
    try {
      return _backgroundDefinitionPattern.hasMatch(
        utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      );
    } on FileSystemException {
      return false;
    }
  }

  /// [projectRoot] 의 [iconsDirectory] 를 Finder 로 여는 명령을 만든다.
  static Command buildOpenCommand(String projectRoot) => Command(
    '/usr/bin/open',
    <String>['$projectRoot/$iconsDirectory'],
    display: 'open $iconsDirectory',
  );

  /// [probe] 의 크기를 `<너비>x<높이>` 로 쓴다.
  static String formatSize(ImageProbe probe) =>
      '${probe.width}x${probe.height}';

  /// 원본 [probe] 가 맞지 않는 까닭을 찾는다 — 맞으면 null.
  ///
  /// 판정 순서는 상한 초과 · 정사각 아님 · 하한 미만이다.
  static String? findSourceProblem(ImageProbe probe) {
    final String size = formatSize(probe);
    if (probe.width > maxSourceSide || probe.height > maxSourceSide) {
      return '$tooLargeReason$size';
    }
    if (probe.width != probe.height) return '$notSquareReason$size';
    if (probe.width < minSourceSide) return '$tooSmallReason$size';
    return null;
  }

  /// [projectRoot] 의 홈 화면 아이콘 20장을 킷 기본 지문 [kitDigests] 와 비교해
  /// 상태를 가른다.
  ///
  /// 하나라도 없거나 읽을 수 없으면 [HomeIconState.missing], 모두 지문과 같으면
  /// [HomeIconState.kitDefault], 모두 다르면 [HomeIconState.mine], 그 밖은
  /// [HomeIconState.mixed] 다. 파일 바이트만 보고 프로세스를 부르지 않는다.
  static HomeIconState classifyHomeIcons(
    String projectRoot,
    Map<String, String> kitDigests,
  ) {
    var kitMatches = 0;
    for (final HomeIconFile file in homeIconFiles) {
      final List<int> bytes;
      try {
        bytes = File('$projectRoot/${file.relativePath}').readAsBytesSync();
      } on FileSystemException {
        return HomeIconState.missing;
      }
      if (sha256.convert(bytes).toString() == kitDigests[file.relativePath]) {
        kitMatches++;
      }
    }
    if (kitMatches == homeIconFiles.length) return HomeIconState.kitDefault;
    if (kitMatches == 0) return HomeIconState.mine;
    return HomeIconState.mixed;
  }

  /// 켠 수단 가운데 콘솔 아이콘 대상의 규격(로그인 수단 표 순서).
  final List<IconSpec> targets;

  final List<String> _dependsOn;
  final Map<String, String> _kitDigests;

  _IconMode _mode = _IconMode.deferred;

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => _dependsOn;

  @override
  String get proceedLabel => '진행';

  @override
  String get deferLabel => '지금 안 함';

  // tracked 파일은 미커밋 검사 뒤에만 쓰고 git 으로 되돌릴 수 있다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    _mode = _IconMode.deferred;
    final String folder = context.resolve(iconsDirectory);
    if (targets.isNotEmpty &&
        FileSystemEntity.typeSync(folder) == FileSystemEntityType.file) {
      return const Deferred(
        '$iconsDirectory 가 폴더가 아니라 파일입니다 — 그 파일을 옮기고 다시 실행하세요',
      );
    }
    if (context.session.isAppIconRebuildRequested) {
      _mode = _IconMode.full;
      return Todo(
        targets.isEmpty
            ? '새 원본 이미지로 홈 화면 아이콘을 다시 만듭니다'
            : '새 원본 이미지로 홈 화면 아이콘과 콘솔 아이콘을 다시 만듭니다',
      );
    }
    switch (classifyHomeIcons(context.projectRoot, _kitDigests)) {
      case HomeIconState.kitDefault:
        _mode = _IconMode.full;
        return const Todo(kitDefaultReason);
      case HomeIconState.mine:
        return _checkMine(context);
      case HomeIconState.mixed:
        return const Deferred(
          '홈 화면 아이콘 일부만 킷 기본입니다 — 덮어쓰지 않습니다 · '
          '다시 만들려면: $rebuildCommand',
        );
      case HomeIconState.missing:
        return Deferred(
          '홈 화면 아이콘 파일이 없습니다(${_countUnreadableHomeIcons(context)}개) '
          '— 다시 만들려면: $rebuildCommand',
        );
    }
  }

  /// 「내 아이콘」 의 iOS 1024 알파와 콘솔 아이콘 상태를 판정한다.
  ///
  /// iOS 1024 를 읽지 못하거나 알파가 있으면 덮어쓰지 않는 남은 일이다. 켠 대상이
  /// 없으면 표식을 보지 않고 끝난 것이다. 켠 대상마다 파일이 있고 표식의 그 수단
  /// 줄이 지금 iOS 1024 지문이면 끝났고, 하나라도 아니면 콘솔 아이콘만 다시
  /// 만든다.
  CheckResult _checkMine(WizardContext context) {
    final Uint8List ios1024 = File(
      context.resolve(ios1024Path),
    ).readAsBytesSync();
    final bool? hasAlpha = readPngHasAlpha(ios1024);
    if (hasAlpha == null) {
      return const Deferred(
        'iOS 1024 아이콘을 PNG 로 읽지 못했습니다 — 다시 만들려면: $rebuildCommand',
      );
    }
    if (hasAlpha) {
      return const Deferred(
        'iOS 1024 아이콘에 알파 채널이 있습니다 — App Store 업로드가 거절될 수 '
        '있습니다 · 다시 만들려면: $rebuildCommand',
      );
    }
    if (targets.isEmpty) {
      _mode = _IconMode.done;
      return const Done('내 아이콘 · $replaceHint');
    }
    final digest = sha256.convert(ios1024).toString();
    final Map<String, String> made = _readMarker(context);
    final List<IconSpec> missing = _findMissingTargets(context);
    final bool isCurrent = targets.every(
      (IconSpec spec) => made[spec.token] == digest,
    );
    if (isCurrent && missing.isEmpty) {
      _mode = _IconMode.done;
      return Done(
        '내 아이콘 · ${_joinNames(targets)} 콘솔용 ${targets.length}개 · '
        '$replaceHint',
      );
    }
    _mode = _IconMode.consoleOnly;
    final bool hasExistingIcon = missing.length < targets.length;
    return Todo(
      '${_joinNames(targets)} 콘솔 아이콘을 홈 화면 아이콘(iOS 1024)에서 만듭니다'
      '${hasExistingIcon ? ' — 만든 뒤 콘솔에 다시 올리세요' : ''}',
    );
  }

  /// 홈 화면 아이콘 가운데 없거나 읽을 수 없는 파일 수.
  int _countUnreadableHomeIcons(WizardContext context) => homeIconFiles
      .where(
        (HomeIconFile file) =>
            !File(context.resolve(file.relativePath)).existsSync(),
      )
      .length;

  /// 표식 파일을 수단 token → iOS 1024 지문 표로 읽는다 — 없거나 읽지 못하면
  /// 빈 표다.
  Map<String, String> _readMarker(WizardContext context) {
    try {
      return parseMarker(
        File(context.resolve(homeIconMarkerPath)).readAsStringSync(),
      );
    } on FileSystemException {
      return const <String, String>{};
    }
  }

  /// 켠 대상 가운데 콘솔 아이콘 파일이 없는 것.
  List<IconSpec> _findMissingTargets(WizardContext context) => targets
      .where(
        (IconSpec spec) =>
            !File(context.resolve(spec.relativePath)).existsSync(),
      )
      .toList();

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _IconMode.full => <String>[
      _buildFullNote(),
      _buildTrackedNote(),
      buildConvertCommand(
        '<원본 이미지>',
        context.resolve('$iconWorkDirectory/source.png'),
        display: '<원본 이미지>',
      ).render(),
      if (targets.isNotEmpty) buildOpenCommand(context.projectRoot).render(),
    ],
    _IconMode.consoleOnly => <String>[
      buildConvertCommand(
        context.resolve(ios1024Path),
        context.resolve('$iconWorkDirectory/source.png'),
        display: ios1024Path,
      ).render(),
      buildOpenCommand(context.projectRoot).render(),
    ],
    _IconMode.deferred || _IconMode.done => const <String>[],
  };

  /// 원본을 묻는 갈래의 첫 계획 안내 줄을 만든다.
  String _buildFullNote() {
    final consoles = targets.isEmpty ? '을' : '과 ${_joinNames(targets)} 콘솔 아이콘을';
    return '(원본 이미지 경로를 물은 뒤 PNG 로 바꾸고 홈 화면 아이콘 iOS '
        '${_countIosFiles()}장 · Android legacy ${_countLegacyFiles()}장 · '
        'adaptive ${listAdaptiveFilePaths().length}개 파일$consoles 만듭니다)';
  }

  /// 원본을 묻는 갈래가 바꾸는 · 새로 쓰는 파일 안내 줄을 만든다.
  String _buildTrackedNote() =>
      '(바뀌는 추적 파일: $iosAppIconDirectory/Icon-App-*.png '
      '${_countIosFiles()} · $androidResDirectory/mipmap-*/ic_launcher.png '
      '${_countLegacyFiles()} — 새 파일: '
      '$androidResDirectory/mipmap-*/ic_launcher_foreground.png '
      '${adaptiveDensities.length} · $adaptiveIconXmlPath · '
      '$adaptiveBackgroundPath)';

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    try {
      return switch (_mode) {
        _IconMode.full => await _applyFull(context),
        _IconMode.consoleOnly => await _applyConsoleOnly(context),
        _IconMode.deferred || _IconMode.done => const Applied(),
      };
    } on GitTreeException catch (e) {
      return Failed(e.message, result: e.result);
    } on FileSystemException catch (e) {
      return Failed('아이콘 파일을 쓰지 못했습니다 — ${e.message}');
    } finally {
      _deleteWorkDirectory(context);
    }
  }

  /// 미커밋 검사 뒤 원본을 물어 홈 화면 · adaptive · 콘솔 아이콘을 모두 만든다.
  Future<StepOutcome> _applyFull(WizardContext context) async {
    final List<String> dirty = await findUncommittedFiles(
      context,
      listWritePaths(),
    );
    if (dirty.isNotEmpty) {
      return Failed(
        '$dirtyReason\n${dirty.map((String path) => '    $path').join('\n')}',
      );
    }
    final List<String> conflicts = findConflictingIconResources(
      context.projectRoot,
    );
    if (conflicts.isNotEmpty) {
      return Failed(
        '$conflictReason\n'
        '${conflicts.map((String path) => '    $path').join('\n')}',
      );
    }
    final _SourceAnswer answer = await _askSource(context);
    final String? source = answer.path;
    if (source == null) return answer.outcome ?? const Declined();
    final (:Uint8List? bytes, :StepOutcome? outcome) = await _convertSource(
      context,
      source,
      display: describePath(context, source),
    );
    if (bytes == null) return outcome ?? const Declined();
    final _Rendered rendered = _renderAll(context, bytes);
    if (rendered.outcome case final StepOutcome stop) return stop;
    return await _writeAll(context, rendered.files, includesHomeIcons: true);
  }

  /// 원본을 묻지 않고 저장소의 iOS 1024 에서 켠 대상의 콘솔 아이콘만 다시
  /// 만든다.
  ///
  /// gitignored 파일만 쓰므로 미커밋 검사를 하지 않는다.
  Future<StepOutcome> _applyConsoleOnly(WizardContext context) async {
    final (:Uint8List? bytes, :StepOutcome? outcome) = await _convertSource(
      context,
      context.resolve(ios1024Path),
      display: ios1024Path,
    );
    if (bytes == null) return outcome ?? const Declined();
    final decoded = decodeIconPng(bytes);
    if (decoded == null) return const Failed(unreadableConvertedReason);
    final normalized = normalizeIcon(decoded);
    if (normalized.width != filledIconSide ||
        normalized.height != filledIconSide) {
      return Failed(
        'iOS 1024 아이콘이 ${filledIconSide}x$filledIconSide 가 아닙니다 — 지금 '
        '${normalized.width}x${normalized.height} · 다시 만들려면: '
        '$rebuildCommand',
      );
    }
    final filled = buildFilledIcon(
      normalized,
      backgroundRgb: defaultBackgroundRgb,
    );
    return await _writeAll(
      context,
      _planConsoleFiles((int side) => encodeSquareIcon(filled, side)),
      includesHomeIcons: false,
    );
  }

  /// 투명한 원본을 채울 배경색을 묻는다 — 고른 `0xRRGGBB` 또는 거절.
  ///
  /// 빈 값은 흰색이다. 꼴이 맞지 않으면 까닭 한 줄 뒤 다시 묻고
  /// [maxSourceAttempts] 번 틀리거나 입력이 끝나면 거절이다.
  int? _askBackgroundColor(WizardContext context) {
    context.terminal.writeLine('  $backgroundGuide');
    for (var attempt = 0; attempt < maxSourceAttempts; attempt++) {
      final String? answer = context.terminal.ask(
        backgroundQuestion,
        defaultValue: '#FFFFFF',
      );
      if (answer == null) return null;
      if (answer.trim().isEmpty) return defaultBackgroundRgb;
      final int? rgb = parseBackgroundColor(answer);
      if (rgb != null) return rgb;
      context.terminal.writeLine('  $backgroundFormatReason');
    }
    return null;
  }

  /// 원본 경로를 묻고 검사한다.
  ///
  /// 빈 값은 미루기, 입력 끝 · [maxSourceAttempts] 회 틀림은 거절이다. 맞지 않는
  /// 원본은 까닭 한 줄 뒤 경로만 다시 묻는다.
  Future<_SourceAnswer> _askSource(WizardContext context) async {
    context.terminal.writeLine('  $sourceGuide');
    for (var attempt = 0; attempt < maxSourceAttempts; attempt++) {
      final String? answer = context.terminal.ask(sourceQuestion);
      if (answer == null) return (path: null, outcome: const Declined());
      final String trimmed = answer.trim();
      if (trimmed.isEmpty) {
        return (path: null, outcome: DeferredByUser(deferLabel));
      }
      final String unquoted = parseDroppedPath(trimmed);
      // 따옴표로 감싼 `file://` 답은 따옴표만 벗겨진 주소로 돌아오므로 그 값으로
      // 한 번 더 바꾼다. 바꿀 수 없는 주소는 손대지 않은 값이 돌아와 그대로다.
      final String parsed = unquoted.startsWith('file://')
          ? parseDroppedPath(unquoted)
          : unquoted;
      // 풀어낸 값이 비거나 한 번 더 바꾸고도 `file://` 주소로 남으면 확장 · 존재
      // 검사 전에 까닭 한 줄로 다시 묻는다 — 확장하면 저장소 루트가 붙어 넣은 주소와
      // 다른 경로가 보인다. 주소 안에 홈 경로가 있을 수 있어 답은 되풀이하지 않는다.
      if (parsed.isEmpty) {
        context.terminal.writeLine('  $emptyPathReason');
        continue;
      }
      if (parsed.startsWith('file://')) {
        context.terminal.writeLine('  $unconvertibleAddressReason');
        continue;
      }
      final String path = expandInputPath(context, parsed);
      final String shown = describePath(context, path);
      // File.existsSync 는 폴더에 false 라 폴더를 먼저 가려 까닭을 맞춘다.
      if (FileSystemEntity.isDirectorySync(path)) {
        context.terminal.writeLine('  $folderReason$shown');
        continue;
      }
      if (!File(path).existsSync()) {
        context.terminal.writeLine('  $missingFileReason$shown');
        continue;
      }
      final CommandResult probed = await context.runner.capture(
        buildProbeCommand(path),
      );
      if (!probed.isSuccess) {
        // 원문에는 저장소 밖 원본의 절대 경로가 섞일 수 있어 화면에는 종료 코드만
        // 보인다. 실행 기록(.setup/logs, gitignored)에는 명령 줄 · 출력 원문과
        // 함께 그 경로가 남는다 — sips -g 출력 첫 줄이 경로 자체라 표시형만 바꿔서는
        // 가릴 수 없다.
        return (
          path: null,
          outcome: Failed(
            '원본 이미지 크기를 읽지 못했습니다 — sips 종료 코드 ${probed.exitCode}',
          ),
        );
      }
      final ImageProbe? probe = parseProbe(probed);
      if (probe == null) {
        context.terminal.writeLine('  $notImageReason$shown');
        continue;
      }
      final String? problem = findSourceProblem(probe);
      if (problem != null) {
        context.terminal.writeLine('  $problem');
        continue;
      }
      return (path: path, outcome: null);
    }
    return (path: null, outcome: const Declined());
  }

  /// [source] 를 작업 폴더의 sRGB PNG 로 바꾸고 그 바이트를 읽는다.
  ///
  /// 작업 폴더는 지우고 새로 만든다. 화면에는 원본 자리에 [display] 를 보인다.
  Future<({Uint8List? bytes, StepOutcome? outcome})> _convertSource(
    WizardContext context,
    String source, {
    required String display,
  }) async {
    final work = Directory(context.resolve(iconWorkDirectory));
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    final output = '${work.path}/source.png';
    final CommandResult converted = await context.runner.capture(
      buildConvertCommand(source, output, display: display),
    );
    if (!converted.isSuccess) {
      return (
        bytes: null,
        outcome: Failed('$convertFailedReason${converted.exitCode}'),
      );
    }
    final file = File(output);
    if (!file.existsSync()) {
      return (bytes: null, outcome: const Failed(unreadableConvertedReason));
    }
    return (bytes: file.readAsBytesSync(), outcome: null);
  }

  /// 바꾼 원본 [converted] 에서 홈 화면 · adaptive · 콘솔 파일을 모두 계산한다.
  ///
  /// 투명 · 반투명 픽셀이 없으면 묻지 않고 알파만 없앤 그림이 전경 재료다. 있으면
  /// 배경색을 한 번 물어 그 색으로 채우고, 전경은 알파를 남긴 로고, adaptive
  /// 배경은 같은 색이다.
  _Rendered _renderAll(WizardContext context, Uint8List converted) {
    final decoded = decodeIconPng(converted);
    if (decoded == null) {
      return (
        files: const <_PlannedFile>[],
        outcome: const Failed(unreadableConvertedReason),
      );
    }
    final normalized = normalizeIcon(decoded);
    final bool isTransparent = countTransparentPixels(normalized) > 0;
    final int? chosenRgb = isTransparent ? _askBackgroundColor(context) : null;
    if (isTransparent && chosenRgb == null) {
      return (files: const <_PlannedFile>[], outcome: const Declined());
    }
    final filled = buildFilledIcon(
      normalized,
      backgroundRgb: chosenRgb ?? defaultBackgroundRgb,
    );
    final foregroundLayer = isTransparent ? buildLogoLayer(normalized) : filled;
    final num foregroundDp = isTransparent
        ? logoForegroundDp
        : paintedForegroundDp;
    final squares = <int, Uint8List>{};
    Uint8List encodeSide(int side) =>
        squares.putIfAbsent(side, () => encodeSquareIcon(filled, side));
    final int adaptiveBackground =
        chosenRgb ??
        switch (paintedBackground) {
          PaintedBackground.edge => averageEdgeRgb(filled),
          PaintedBackground.white => defaultBackgroundRgb,
        };
    return (
      files: <_PlannedFile>[
        for (final HomeIconFile file in homeIconFiles)
          _PlannedFile(
            file.relativePath,
            encodeSide(file.side),
            side: file.side,
            colorType: 2,
          ),
        _PlannedFile(adaptiveIconXmlPath, utf8.encode(buildAdaptiveIconXml())),
        _PlannedFile(
          adaptiveBackgroundPath,
          utf8.encode(buildAdaptiveBackgroundXml(adaptiveBackground)),
        ),
        for (final AdaptiveDensity density in adaptiveDensities)
          _PlannedFile(
            density.foregroundPath,
            encodeAdaptiveForeground(
              foregroundLayer,
              canvasSide: density.canvasSide,
              logoDp: foregroundDp,
            ),
            side: density.canvasSide,
            colorType: 6,
          ),
        ..._planConsoleFiles(encodeSide),
      ],
      outcome: null,
    );
  }

  /// 켠 대상의 콘솔 아이콘 파일을 [encodeSide] 로 계산한다.
  List<_PlannedFile> _planConsoleFiles(Uint8List Function(int) encodeSide) =>
      <_PlannedFile>[
        for (final IconSpec spec in targets)
          _PlannedFile(
            spec.relativePath,
            encodeSide(spec.side),
            side: spec.side,
            colorType: 2,
            maxBytes: spec.maxBytes,
          ),
      ];

  /// [files] 를 메모리에서 확인한 뒤 쓰고 표식 · 결과 표 · Finder 를 잇는다.
  ///
  /// 하나라도 확인에 걸리면 아무것도 쓰지 않는다. 홈 화면 · adaptive 파일을 먼저
  /// 쓰고 iOS 1024 를 다시 읽는다 — 그 사이 실패하면 쓰기 전으로 되돌리고 멈춘다.
  /// 그 뒤 콘솔 아이콘을 모두 쓰고 마지막에 표식의 켠 대상 줄만 지금 iOS 1024
  /// 지문으로 바꾼다 — 끈 수단 줄은 그 파일처럼 그대로 둔다. 콘솔 쪽에서
  /// 실패하면 홈 화면은 그대로 두고 다음 실행이 콘솔 아이콘을 다시 만든다. 켠
  /// 대상이 없으면 [iconsDirectory] 를 만들지 않는다.
  Future<StepOutcome> _writeAll(
    WizardContext context,
    List<_PlannedFile> files, {
    required bool includesHomeIcons,
  }) async {
    for (final file in files) {
      final String? problem = _findOutputProblem(file);
      if (problem != null) return Failed(problem);
    }
    final bool hasReplacedConsoleIcon = targets.any(
      (IconSpec spec) => File(context.resolve(spec.relativePath)).existsSync(),
    );
    final Set<String> homePaths = listWritePaths().toSet();
    if (includesHomeIcons) {
      final StepOutcome? failure = await _placeHomeIcons(
        context,
        <_PlannedFile>[
          for (final file in files)
            if (homePaths.contains(file.relativePath)) file,
        ],
      );
      if (failure != null) return failure;
    }
    for (final file in files) {
      if (homePaths.contains(file.relativePath)) continue;
      File(context.resolve(file.relativePath))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(file.bytes, flush: true);
    }
    if (targets.isNotEmpty) {
      final Uint8List ios1024 = File(
        context.resolve(ios1024Path),
      ).readAsBytesSync();
      final digest = sha256.convert(ios1024).toString();
      _writeMarker(context, <String, String>{
        ..._readMarker(context),
        for (final IconSpec spec in targets) spec.token: digest,
      });
    }
    writeSummary(
      context.terminal,
      title: summaryTitle,
      rows: <SummaryRow>[
        if (includesHomeIcons) ...<SummaryRow>[
          SummaryRow(
            '홈 화면 — iOS',
            '$iosAppIconDirectory/Icon-App-*.png ${_countIosFiles()}장',
          ),
          SummaryRow(
            '홈 화면 — Android',
            '$androidResDirectory/mipmap-*/ic_launcher.png '
                '${_countLegacyFiles()}장',
          ),
          SummaryRow(
            '홈 화면 — Android adaptive',
            '$androidResDirectory/mipmap-*/ic_launcher_foreground.png '
                '${adaptiveDensities.length}장 · ic_launcher.xml · '
                'ic_launcher_background.xml',
          ),
        ],
        for (final IconSpec spec in targets)
          SummaryRow(
            '${_findName(spec)} — ${spec.rowLabel}',
            spec.relativePath,
          ),
      ],
      notes: <String>[
        for (final IconSpec spec in targets)
          if (buildIconNote(spec) case final String note) note,
        if (hasReplacedConsoleIcon) reuploadNote,
        if (targets.isNotEmpty)
          buildUploadGuide(context.resolve(iconsDirectory)),
      ],
    );
    if (targets.isNotEmpty) {
      final CommandResult opened = await context.runner.stream(
        buildOpenCommand(context.projectRoot),
      );
      if (!opened.isSuccess) context.terminal.writeLine('  $openFailedNote');
    }
    context.session.isAppIconRebuildRequested = false;
    return const Applied();
  }

  /// 홈 화면 · adaptive 파일 [files] 를 순서대로 제자리에 쓰고 iOS 1024 를 다시
  /// 읽는다 — 끝나면 null, 실패하면 쓰기 전으로 되돌린 뒤의 결과다.
  ///
  /// 쓰기 전에 디스크에 있던 경로를 먼저 적어 둔다. 미커밋 검사를 지났으므로 그
  /// 경로는 모두 깨끗한 추적 파일이다. 쓰다 실패한 경로는
  /// [decideFailedWriteUndo] 가 정한 대로 되돌림에 넣는다.
  Future<StepOutcome?> _placeHomeIcons(
    WizardContext context,
    List<_PlannedFile> files,
  ) async {
    final existedBefore = <String>{
      for (final file in files)
        if (File(context.resolve(file.relativePath)).existsSync())
          file.relativePath,
    };
    final written = <String>[];
    for (final file in files) {
      try {
        File(context.resolve(file.relativePath))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(file.bytes, flush: true);
      } on FileSystemException catch (e) {
        final FailedWriteUndo undo = decideFailedWriteUndo(
          existedBefore: existedBefore.contains(file.relativePath),
          currentType: FileSystemEntity.typeSync(
            context.resolve(file.relativePath),
            followLinks: false,
          ),
        );
        return await _restoreHomeIcons(
          context,
          <String>[
            ...written,
            if (undo != FailedWriteUndo.keep) file.relativePath,
          ],
          existedBefore,
          '${file.relativePath} (${_describeFileError(e)})',
        );
      }
      written.add(file.relativePath);
    }
    final String? problem = _checkPlacedIos1024(context);
    if (problem == null) return null;
    return await _restoreHomeIcons(context, written, existedBefore, problem);
  }

  /// 제자리의 iOS 1024 를 디스크에서 다시 읽어 맞지 않는 까닭을 찾는다 — 맞으면
  /// null.
  String? _checkPlacedIos1024(WizardContext context) {
    final Uint8List bytes;
    try {
      bytes = File(context.resolve(ios1024Path)).readAsBytesSync();
    } on FileSystemException catch (e) {
      return '$ios1024Path 를 다시 읽지 못했습니다 (${_describeFileError(e)})';
    }
    final String? problem = findPlacedIos1024Problem(bytes);
    return problem == null ? null : '다시 읽은 $ios1024Path — $problem';
  }

  /// 이번에 쓴 [written] 을 쓰기 전으로 되돌리고 실패 결과를 만든다 — [reason] 은
  /// 쓰기를 멈춘 까닭이다.
  ///
  /// 쓰기 전에 있던 파일([existedBefore])은 지우지 않고 git 으로 커밋 내용에
  /// 되돌리고, 새로 만든 파일은 지운다.
  Future<StepOutcome> _restoreHomeIcons(
    WizardContext context,
    List<String> written,
    Set<String> existedBefore,
    String reason,
  ) async {
    final tracked = <String>[];
    final created = <String>[];
    for (final path in written) {
      if (existedBefore.contains(path)) {
        tracked.add(path);
      } else {
        created.add(path);
      }
    }
    final undeleted = <String>[];
    for (final path in created) {
      try {
        File(context.resolve(path)).deleteSync();
      } on FileSystemException catch (e) {
        undeleted.add('    $path (${_describeFileError(e)})');
      }
    }
    if (tracked.isNotEmpty) {
      final CommandResult restored = await context.runner.capture(
        buildRestoreCommand(tracked, workingDirectory: context.projectRoot),
      );
      if (!restored.isSuccess) {
        return Failed(
          '$restoreFailedReason$reason\n$restoreGuide\n'
          '${tracked.map((String path) => '    $path').join('\n')}'
          '${undeleted.isEmpty ? '' : '\n$deleteGuide\n${undeleted.join('\n')}'}',
          result: restored,
        );
      }
    }
    if (undeleted.isNotEmpty) {
      return Failed(
        '$rolledBackReason$reason\n$deleteGuide\n${undeleted.join('\n')}',
      );
    }
    return Failed('$rolledBackReason$reason');
  }

  /// 파일 예외 [error] 의 OS 까닭 한 줄 — 경로는 넣지 않는다.
  static String _describeFileError(FileSystemException error) =>
      error.osError?.message ?? error.message;

  /// 만든 [file] 이 기대와 다른 까닭을 찾는다 — 맞으면 null.
  String? _findOutputProblem(_PlannedFile file) {
    final int? side = file.side;
    if (side != null) {
      final PngHeader? header = readPngHeader(file.bytes);
      if (header == null ||
          header.width != side ||
          header.height != side ||
          header.colorType != file.colorType) {
        return '만든 아이콘이 규격과 다릅니다 — ${file.relativePath}';
      }
    }
    final int? maxBytes = file.maxBytes;
    if (maxBytes != null && file.bytes.length > maxBytes) {
      return '만든 아이콘이 용량 상한을 넘습니다 — ${file.relativePath}: '
          '${file.bytes.length} 바이트 (상한 $maxBytes 바이트)';
    }
    return null;
  }

  /// 표식 파일에 수단 token → iOS 1024 지문 표 [entries] 를 쓴다 — 파일 0600.
  ///
  /// 내용을 쓰기 전에 빈 파일로 만들어 권한부터 좁힌다. 실패하면 조용히 그친다
  /// — 표식이 없거나 옛 값이면 다음 실행이 콘솔 아이콘을 다시 만들 뿐이다.
  void _writeMarker(WizardContext context, Map<String, String> entries) {
    final file = File(context.resolve(homeIconMarkerPath));
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('');
      restrictFileMode(file.path, ownerOnlyFileMode);
      file.writeAsStringSync(formatMarker(entries), flush: true);
    } on FileSystemException {
      return;
    } on ProcessException {
      return;
    }
  }

  /// 작업 폴더를 지운다 — 없거나 지우지 못하면 조용히 그친다.
  void _deleteWorkDirectory(WizardContext context) {
    final work = Directory(context.resolve(iconWorkDirectory));
    try {
      if (work.existsSync()) work.deleteSync(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  /// iOS 홈 화면 아이콘 수.
  int _countIosFiles() => homeIconFiles
      .where(
        (HomeIconFile file) =>
            file.relativePath.startsWith(iosAppIconDirectory),
      )
      .length;

  /// Android legacy 홈 화면 아이콘 수.
  int _countLegacyFiles() => homeIconFiles.length - _countIosFiles();

  /// [spec] 의 화면 이름을 찾는다.
  String _findName(IconSpec spec) =>
      findProvider(spec.token)?.displayName ?? spec.token;

  /// [specs] 의 화면 이름을 ` · ` 로 잇는다.
  String _joinNames(List<IconSpec> specs) => specs.map(_findName).join(' · ');
}
