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

/// 직전 검사가 정한 실행 갈래.
enum _IconMode {
  /// 원본을 물어 홈 화면 · adaptive · 콘솔 아이콘을 모두 만든다.
  full,

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

  /// 켠 로그인 수단 [enabledProviders] 에 콘솔 아이콘 대상이 있으면 true.
  static bool isRequiredFor(Set<String> enabledProviders) =>
      selectIconTargets(enabledProviders).isNotEmpty;

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
      return const Todo(kitDefaultReason);
    }
    switch (classifyHomeIcons(context.projectRoot, _kitDigests)) {
      case HomeIconState.kitDefault:
        _mode = _IconMode.full;
        return const Todo(kitDefaultReason);
      case HomeIconState.mine:
        return _checkMine(context);
      case HomeIconState.mixed || HomeIconState.missing:
        return const Deferred('홈 화면 아이콘을 덮어쓰지 않습니다 — 다시 만들려면: $rebuildCommand');
    }
  }

  /// 「내 아이콘」 의 콘솔 아이콘 상태를 판정한다.
  CheckResult _checkMine(WizardContext context) {
    if (targets.isEmpty) {
      _mode = _IconMode.done;
      return const Done('내 아이콘 · $replaceHint');
    }
    final Uint8List ios1024 = File(
      context.resolve(ios1024Path),
    ).readAsBytesSync();
    final isMarkerCurrent =
        _readMarker(context) == sha256.convert(ios1024).toString();
    if (isMarkerCurrent && _findMissingTargets(context).isEmpty) {
      _mode = _IconMode.done;
      return Done(
        '내 아이콘 · ${_joinNames(targets)} 콘솔용 ${targets.length}개 · '
        '$replaceHint',
      );
    }
    return const Deferred('콘솔 아이콘이 홈 화면 아이콘과 다릅니다 — 다시 만들려면: $rebuildCommand');
  }

  /// 표식 파일 한 줄을 읽는다 — 없거나 읽지 못하면 null.
  String? _readMarker(WizardContext context) {
    try {
      return File(
        context.resolve(homeIconMarkerPath),
      ).readAsStringSync().trim();
    } on FileSystemException {
      return null;
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
    final _SourceAnswer answer = await _askSource(context);
    final String? source = answer.path;
    if (source == null) return answer.outcome ?? const Declined();
    final (:Uint8List? bytes, :StepOutcome? outcome) = await _convertSource(
      context,
      source,
      display: describePath(context, source),
    );
    if (bytes == null) return outcome ?? const Declined();
    final _Rendered rendered = _renderAll(bytes);
    if (rendered.outcome case final StepOutcome stop) return stop;
    return await _writeAll(context, rendered.files, includesHomeIcons: true);
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
  _Rendered _renderAll(Uint8List converted) {
    final decoded = decodeIconPng(converted);
    if (decoded == null) {
      return (
        files: const <_PlannedFile>[],
        outcome: const Failed(unreadableConvertedReason),
      );
    }
    final normalized = normalizeIcon(decoded);
    final filled = buildFilledIcon(
      normalized,
      backgroundRgb: defaultBackgroundRgb,
    );
    final squares = <int, Uint8List>{};
    Uint8List encodeSide(int side) =>
        squares.putIfAbsent(side, () => encodeSquareIcon(filled, side));
    final int adaptiveBackground = switch (paintedBackground) {
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
        for (final AdaptiveDensity density in adaptiveDensities)
          _PlannedFile(
            density.foregroundPath,
            encodeAdaptiveForeground(
              filled,
              canvasSide: density.canvasSide,
              logoDp: paintedForegroundDp,
            ),
            side: density.canvasSide,
            colorType: 6,
          ),
        _PlannedFile(adaptiveIconXmlPath, utf8.encode(buildAdaptiveIconXml())),
        _PlannedFile(
          adaptiveBackgroundPath,
          utf8.encode(buildAdaptiveBackgroundXml(adaptiveBackground)),
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
  /// 하나라도 확인에 걸리면 아무것도 쓰지 않는다. 콘솔 아이콘을 모두 쓴 뒤
  /// 마지막에 표식을 쓴다 — 중간에 실패하면 다음 실행이 콘솔 아이콘을 다시
  /// 만든다. 켠 대상이 없으면 [iconsDirectory] 를 만들지 않는다.
  Future<StepOutcome> _writeAll(
    WizardContext context,
    List<_PlannedFile> files, {
    required bool includesHomeIcons,
  }) async {
    for (final file in files) {
      final String? problem = _findOutputProblem(file);
      if (problem != null) return Failed(problem);
    }
    for (final file in files) {
      File(context.resolve(file.relativePath))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(file.bytes, flush: true);
    }
    if (targets.isNotEmpty) {
      final Uint8List ios1024 = File(
        context.resolve(ios1024Path),
      ).readAsBytesSync();
      _writeMarker(context, sha256.convert(ios1024).toString());
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

  /// 표식 파일에 [digest] 한 줄을 쓴다 — 파일 0600.
  ///
  /// 내용을 쓰기 전에 빈 파일로 만들어 권한부터 좁힌다. 실패하면 조용히 그친다
  /// — 표식이 없거나 옛 값이면 다음 실행이 콘솔 아이콘을 다시 만들 뿐이다.
  void _writeMarker(WizardContext context, String digest) {
    final file = File(context.resolve(homeIconMarkerPath));
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('');
      restrictFileMode(file.path, ownerOnlyFileMode);
      file.writeAsStringSync('$digest\n', flush: true);
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
