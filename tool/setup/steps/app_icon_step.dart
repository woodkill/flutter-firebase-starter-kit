import 'dart:io';

import '../command_runner.dart';
import '../confirm.dart';
import '../providers/icon_specs.dart';
import '../providers/keyed_provider_step.dart';
import '../providers/path_input.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../wizard.dart';

/// `sips -g` 로 읽은 이미지 크기 · 형식.
typedef ImageProbe = ({int width, int height, String format});

/// 직전 검사가 정한 실행 갈래.
enum _IconMode {
  /// 사본이 없어 원본 경로를 묻는다.
  askSource,

  /// 보관한 사본으로 없는 파일만 만든다.
  fromCopy,

  /// 지금은 만들 수 없다(사본 여럿 · 폴더 자리가 파일).
  deferred,

  /// 켠 대상 파일이 모두 있다.
  done,
}

/// 앱 아이콘 단계 — 켠 수단 중 콘솔 아이콘 칸이 있는 provider 마다 원본 하나로
/// 규격 PNG 를 만든다.
///
/// 파일이 있으면 끝난 것이다 — 상태 파일을 두지 않고 [iconsDirectory] 의 파일로
/// 판정한다. 원본은 바꾸지 않는다: 원본을 `source.<형식>` 사본으로 복사한 뒤 그
/// 사본에서 만들고, 자르기 · 여백 · 확대 없이 정사각 원본만 받는다. 사본이 있는
/// 다시 실행은 원본 경로를 묻지 않고 없는 파일만 만든다. 만든 뒤 크기 · 형식 ·
/// 용량을 다시 읽어 확인하고, 결과 표를 보인 뒤 Finder 로 폴더를 연다.
final class AppIconStep implements DeferrableStep {
  /// 켠 로그인 수단 [enabledProviders] 에서 아이콘 대상을 골라 단계를 만든다.
  AppIconStep({required Set<String> enabledProviders})
    : targets = selectIconTargets(enabledProviders);

  /// 단계 id.
  static const String stepId = 'app_icon';

  /// 단계 제목.
  static const String stepTitle = '앱 아이콘';

  /// 원본 질문 전에 보이는 안내.
  static const String sourceGuide =
      'provider 콘솔에 올릴 아이콘을 원본 이미지 하나로 만듭니다 — 정사각 · '
      '${minSourceSide}x$minSourceSide 이상(PNG · JPEG · HEIC 등). '
      'Finder 에서 파일을 이 창으로 끌어다 놓아도 됩니다';

  /// 원본 경로 질문.
  static const String sourceQuestion = '원본 이미지 경로 (빈 값 = 지금 안 함)';

  /// 원본 파일이 없을 때의 까닭 머리(뒤에 화면용 경로).
  static const String missingFileReason = '파일이 없습니다 — ';

  /// 이미지로 읽히지 않을 때의 까닭 머리(뒤에 화면용 경로).
  static const String notImageReason = '이미지 파일이 아닙니다 — ';

  /// 정사각이 아닐 때의 까닭 머리(뒤에 지금 크기).
  static const String notSquareReason = '정사각 이미지가 필요합니다 — 지금 ';

  /// 하한보다 작을 때의 까닭 머리(뒤에 지금 크기).
  static const String tooSmallReason =
      '${minSourceSide}x$minSourceSide 이상이 필요합니다 — 지금 ';

  /// 상한보다 클 때의 까닭 머리(뒤에 지금 크기).
  static const String tooLargeReason = '너무 큰 이미지입니다 — 지금 ';

  /// 아이콘을 바꾸는 법.
  static const String replaceHint = '바꾸려면 $iconsDirectory 를 지우고 다시 실행';

  /// 사본이 여럿일 때의 까닭.
  static const String multipleSourcesReason =
      '$iconsDirectory 에 원본 사본($sourceCopyBaseName.*)이 여럿입니다 — '
      '$iconsDirectory 를 지우고 다시 실행하세요';

  /// 결과 표 제목.
  static const String summaryTitle = 'provider 콘솔에 올릴 앱 아이콘';

  /// 결과 표 끝의 올리는 법 안내.
  static const String uploadGuide =
      '브라우저의 파일 선택 창에서 ⌘⇧G 로 $iconsDirectory 경로를 붙여 넣거나 '
      '열린 Finder 창에서 끌어다 놓으세요';

  /// Finder 열기가 실패했을 때의 한 줄.
  static const String openFailedNote =
      'Finder 를 열지 못했습니다 — 파일은 $iconsDirectory 에 있습니다';

  /// 켠 로그인 수단 [enabledProviders] 에 아이콘 대상이 있으면 true.
  static bool isRequiredFor(Set<String> enabledProviders) =>
      selectIconTargets(enabledProviders).isNotEmpty;

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

  /// [projectRoot] 의 사본 [sourceFileName] 에서 [spec] 규격 PNG 를 만드는 명령을
  /// 만든다.
  ///
  /// 크기는 높이 · 너비 순이고 형식은 소문자 `png` 다. 입력 · 출력은 늘
  /// [iconsDirectory] 안의 절대 경로이고 화면에는 상대 경로를 보인다.
  static Command buildResizeCommand(
    String projectRoot,
    String sourceFileName,
    IconSpec spec,
  ) {
    final side = '${spec.side}';
    final input = '$iconsDirectory/$sourceFileName';
    return Command(
      '/usr/bin/sips',
      <String>[
        '-z',
        side,
        side,
        '-s',
        'format',
        'png',
        '$projectRoot/$input',
        '--out',
        '$projectRoot/${spec.relativePath}',
      ],
      display:
          'sips -z $side $side -s format png $input '
          '--out ${spec.relativePath}',
    );
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

  /// 켠 수단 가운데 아이콘 대상의 규격(로그인 수단 표 순서).
  final List<IconSpec> targets;

  _IconMode _mode = _IconMode.askSource;
  List<IconSpec> _missing = const <IconSpec>[];
  String _sourceName = '';

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['providers'];

  @override
  String get proceedLabel => '진행';

  @override
  String get deferLabel => '지금 안 함';

  // 저장소 안 gitignored 파일만 만든다 — 지우고 다시 실행하면 되돌릴 수 있다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String folder = context.resolve(iconsDirectory);
    if (FileSystemEntity.typeSync(folder) == FileSystemEntityType.file) {
      _mode = _IconMode.deferred;
      return const Deferred(
        '$iconsDirectory 가 폴더가 아니라 파일입니다 — 그 파일을 옮기고 다시 실행하세요',
      );
    }
    _missing = targets
        .where(
          (IconSpec spec) =>
              !File(context.resolve(spec.relativePath)).existsSync(),
        )
        .toList();
    if (_missing.isEmpty) {
      _mode = _IconMode.done;
      return Done('${_joinNames(targets)} 용 ${targets.length}개 · $replaceHint');
    }
    final List<String> sources;
    try {
      sources = _listSourceCopies(folder);
    } on FileSystemException catch (e) {
      _mode = _IconMode.deferred;
      return Deferred('$iconsDirectory 를 읽지 못했습니다 — ${e.message}');
    }
    if (sources.length > 1) {
      _mode = _IconMode.deferred;
      return const Deferred(multipleSourcesReason);
    }
    if (sources.length == 1) {
      _mode = _IconMode.fromCopy;
      _sourceName = sources.single;
      return Todo('${_joinNames(_missing)} 용 파일이 없습니다 — 보관한 원본으로 만듭니다');
    }
    _mode = _IconMode.askSource;
    return Todo('원본 이미지가 없습니다 — 경로를 묻습니다 (${_joinNames(_missing)} 용)');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _IconMode.askSource => <String>[
      _buildAskSourceNote(),
      buildOpenCommand(context.projectRoot).render(),
    ],
    _IconMode.fromCopy => <String>[
      for (final IconSpec spec in _missing)
        buildResizeCommand(context.projectRoot, _sourceName, spec).render(),
      buildOpenCommand(context.projectRoot).render(),
    ],
    _IconMode.deferred || _IconMode.done => const <String>[],
  };

  /// 원본 경로를 묻는 갈래의 계획 안내 줄을 만든다.
  String _buildAskSourceNote() =>
      '(원본 이미지 경로를 물은 뒤 $iconsDirectory/$sourceCopyBaseName.<원본 형식> '
      '으로 복사하고 ${_joinNames(_missing)} 용 PNG 를 sips 로 만듭니다)';

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _IconMode.deferred || _IconMode.done:
        return const Applied();
      case _IconMode.fromCopy:
        return await _applyFromCopy(context);
      case _IconMode.askSource:
        return await _applyAskSource(context);
    }
  }

  /// 원본 경로를 묻고 검사한 뒤 사본을 만들고 아이콘을 만든다.
  ///
  /// 빈 값은 미루기, 입력 끝 · [maxKeyAttempts] 회 틀림은 거절이다. 맞지 않는
  /// 원본은 까닭 한 줄 뒤 경로만 다시 묻는다.
  Future<StepOutcome> _applyAskSource(WizardContext context) async {
    context.terminal.writeLine('  $sourceGuide');
    for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
      final String? answer = context.terminal.ask(sourceQuestion);
      if (answer == null) return const Declined();
      final String trimmed = answer.trim();
      if (trimmed.isEmpty) return DeferredByUser(deferLabel);
      final String path = expandInputPath(context, parseDroppedPath(trimmed));
      final String shown = describePath(context, path);
      if (!File(path).existsSync()) {
        context.terminal.writeLine('  $missingFileReason$shown');
        continue;
      }
      final ImageProbe? probe = parseProbe(
        await context.runner.capture(buildProbeCommand(path)),
      );
      if (probe == null) {
        context.terminal.writeLine('  $notImageReason$shown');
        continue;
      }
      final String? problem = findSourceProblem(probe);
      if (problem != null) {
        context.terminal.writeLine('  $problem');
        continue;
      }
      final copyName = '$sourceCopyBaseName.${probe.format}';
      final String copyPath = context.resolve('$iconsDirectory/$copyName');
      try {
        Directory(context.resolve(iconsDirectory)).createSync(recursive: true);
        if (path != copyPath) File(path).copySync(copyPath);
      } on FileSystemException catch (e) {
        return Failed('원본 사본을 만들지 못했습니다 — ${e.message}');
      }
      return await _buildIcons(context, copyName);
    }
    return const Declined();
  }

  /// 보관한 사본을 다시 읽어 검사한 뒤 없는 아이콘만 만든다.
  Future<StepOutcome> _applyFromCopy(WizardContext context) async {
    final shown = '$iconsDirectory/$_sourceName';
    final ImageProbe? probe = parseProbe(
      await context.runner.capture(buildProbeCommand(context.resolve(shown))),
    );
    final String? problem = probe == null
        ? '이미지로 읽히지 않습니다'
        : findSourceProblem(probe);
    if (problem != null) {
      return Failed('보관한 원본 $shown 이 맞지 않습니다 — $problem — $replaceHint');
    }
    return await _buildIcons(context, _sourceName);
  }

  /// 사본 [sourceName] 에서 없는 대상 아이콘을 만들고 확인 · 결과 표 · Finder 를
  /// 잇는다.
  ///
  /// 이미 있는 대상 파일은 건드리지 않는다. 확인에 걸린 파일은 지워 다시 실행이
  /// 다시 만들게 한다.
  Future<StepOutcome> _buildIcons(
    WizardContext context,
    String sourceName,
  ) async {
    final String root = context.projectRoot;
    try {
      // sips 는 --out 의 부모 폴더가 없으면 엉뚱한 이름의 파일을 만든다.
      Directory(context.resolve(iconsDirectory)).createSync(recursive: true);
    } on FileSystemException catch (e) {
      return Failed('$iconsDirectory 를 만들지 못했습니다 — ${e.message}');
    }
    for (final IconSpec spec in _missing) {
      final CommandResult result = await context.runner.stream(
        buildResizeCommand(root, sourceName, spec),
      );
      if (!result.isSuccess) {
        _discard(context, spec);
        return Failed('${_findName(spec)} 아이콘을 만들지 못했습니다', result: result);
      }
    }
    for (final IconSpec spec in _missing) {
      final String? problem = await _verifyIcon(context, spec);
      if (problem != null) {
        _discard(context, spec);
        return Failed(problem);
      }
    }
    writeSummary(
      context.terminal,
      title: summaryTitle,
      rows: <SummaryRow>[
        for (final IconSpec spec in targets)
          SummaryRow(
            '${_findName(spec)} — ${spec.rowLabel}',
            spec.relativePath,
          ),
      ],
      notes: <String>[
        for (final IconSpec spec in targets)
          if (buildIconNote(spec) case final String note) note,
        uploadGuide,
      ],
    );
    final CommandResult opened = await context.runner.stream(
      buildOpenCommand(root),
    );
    if (!opened.isSuccess) context.terminal.writeLine('  $openFailedNote');
    return const Applied();
  }

  /// 만든 [spec] 파일의 크기 · 형식 · 용량을 확인한다 — 맞으면 null, 아니면 실패 문장.
  Future<String?> _verifyIcon(WizardContext context, IconSpec spec) async {
    final String path = context.resolve(spec.relativePath);
    final String name = _findName(spec);
    final ImageProbe? probe = parseProbe(
      await context.runner.capture(buildProbeCommand(path)),
    );
    if (probe == null) {
      return '$name 아이콘을 읽지 못했습니다 — ${spec.relativePath}';
    }
    final int bytes;
    try {
      bytes = File(path).lengthSync();
    } on FileSystemException catch (e) {
      return '$name 아이콘 용량을 읽지 못했습니다 — ${e.message}';
    }
    final bool isSpec =
        probe.width == spec.side &&
        probe.height == spec.side &&
        probe.format == 'png' &&
        bytes <= spec.maxBytes;
    if (isSpec) return null;
    return '$name 아이콘이 규격과 다릅니다 — ${spec.relativePath}: '
        '지금 ${formatSize(probe)} ${probe.format} · $bytes 바이트 '
        '(규격 ${spec.side}x${spec.side} png · ${spec.maxBytes} 바이트 이하)';
  }

  /// 이번 실행에서 만들다 만 [spec] 파일을 지운다 — 지우지 못해도 넘어간다.
  void _discard(WizardContext context, IconSpec spec) {
    final file = File(context.resolve(spec.relativePath));
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // 남은 파일은 다시 실행의 검사 · 확인이 다시 본다.
      return;
    }
  }

  /// [folder] 안에서 `source.` 로 시작하는 파일 이름을 이름 순으로 모은다.
  ///
  /// 폴더가 없으면 빈 목록이다.
  List<String> _listSourceCopies(String folder) {
    final directory = Directory(folder);
    if (!directory.existsSync()) return const <String>[];
    final names = <String>[
      for (final FileSystemEntity entity in directory.listSync())
        if (entity is File)
          entity.path.substring(entity.path.lastIndexOf('/') + 1),
    ];
    return names
        .where((String name) => name.startsWith('$sourceCopyBaseName.'))
        .toList()
      ..sort();
  }

  /// [spec] 의 화면 이름을 찾는다.
  String _findName(IconSpec spec) =>
      findProvider(spec.token)?.displayName ?? spec.token;

  /// [specs] 의 화면 이름을 ` · ` 로 잇는다.
  String _joinNames(List<IconSpec> specs) => specs.map(_findName).join(' · ');
}
