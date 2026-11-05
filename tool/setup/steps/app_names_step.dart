import 'dart:convert';
import 'dart:io';

import '../../launcher_names.dart'
    show
        GeneratorException,
        L10nConfig,
        appTitleKey,
        flavorDisplayNameSuffixes,
        hasLauncherNameWhitespaceIssue,
        readL10nConfig;
import '../arb_titles.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../git_tree.dart';
import '../locale_endonyms.dart';
import '../step.dart';
import '../terminal.dart';
import '../wizard.dart';
import 'identity_step.dart';

/// 언어별 앱 이름 단계 — 영어 아닌 ARB 마다 `appTitle`(홈 화면 이름)을 묻고 쓴다.
///
/// 대상 ARB 집합은 빌드 생성기와 같은 `l10n.yaml` 읽기로 정한다. 키가 있으면
/// 정한 언어, 없으면 아직 정하지 않은 언어로 보고 파일만 보고 판정한다. Enter 는
/// 기본 이름(영어 ARB 의 `appTitle`)을 그대로 값으로 쓴다. 위저드는 생성 dart 를
/// 만들지 않는다 — 다음 pub get · 빌드가 만든다.
final class AppNamesStep implements Step {
  /// 점검표 · 단계 머리에 보일 제목.
  static const String stepTitle = '언어별 앱 이름';

  /// 쓰기 전 확인 표의 제목.
  static const String confirmTitle = '언어별 앱 이름 — 확인';

  /// 확인 표 뒤 고르기 질문.
  static const String confirmQuestion = '이 값으로 진행할까요, 고칠까요?';

  /// 확인 표 뒤 진행 선택지.
  static const String proceedOption = '이대로 진행';

  /// 입력에 공백이 이어질 때의 안내.
  static const String repeatedWhitespaceMessage = '  낱말 사이 공백은 한 칸으로 둡니다';

  /// 기본 이름도 비어 있어 입력이 빈 값일 때의 안내.
  static const String emptyNameMessage = '  빈 이름은 쓸 수 없습니다';

  /// 한 언어가 끝까지 규칙에 맞지 않아 쓰지 않았을 때의 실패 요약.
  static const String invalidFormatFailure = '언어별 앱 이름 형식이 맞지 않아 진행하지 않았습니다';

  /// 같은 언어를 다시 묻는 최대 횟수.
  static const int maxInputAttempts = 3;

  /// 홈 화면 golden 이 찍는 언어 — 이 언어의 이름만 golden 을 바꾼다.
  static const String goldenLocale = 'ko';

  /// 홈 화면 golden 시험 파일의 저장소 상대 경로.
  static const String goldenTestPath =
      'test/features/home/home_announcement_golden_test.dart';

  /// golden 을 다시 찍는 명령 — 위저드는 안내만 하고 실행하지 않는다.
  static const String goldenCommand =
      'fvm flutter test --update-goldens $goldenTestPath';

  /// golden 이 다시 찍혀야 할 때 보이는 안내 문장(들여쓰기 없음).
  static const String goldenHintLine =
      'ko 앱 이름(홈 화면 제목)이 마지막 커밋과 달라 홈 화면 golden 2장이 다시 '
      '찍혀야 합니다: $goldenCommand';

  /// [goldenLocale] 의 실효 제목이 커밋된 상태(HEAD)와 달라 golden 이 다시
  /// 찍혀야 하면 true.
  ///
  /// 실효 제목은 [goldenLocale] ARB 의 `appTitle` 이 있으면 그 값, 없으면 영어
  /// (template) ARB 의 `appTitle` 이다 — 홈 화면 golden 이 그리는 AppBar 제목과
  /// 같다. 작업 트리 쪽은 파일을, 커밋된 쪽은 `git show HEAD:<경로>` 를 읽는다.
  /// [goldenTestPath] 시험 파일이 없거나 · `l10n.yaml` 을 읽지 못하거나 ·
  /// [goldenLocale] ARB 가 없거나 · 어느 쪽 실효 제목을 정하지 못하거나 · git
  /// 조회가 실패하면 false 다.
  static Future<bool> needsGoldenHint(WizardContext context) async {
    if (!File(context.resolve(goldenTestPath)).existsSync()) return false;
    final L10nConfig config;
    final List<LocalizedArb> arbs;
    try {
      config = readL10nConfig(context.projectRoot);
      arbs = listLocalizedArbs(context.projectRoot);
    } on GeneratorException {
      return false;
    }
    final LocalizedArb? goldenArb = arbs
        .where((LocalizedArb arb) => arb.locale == goldenLocale)
        .firstOrNull;
    if (goldenArb == null) return false;
    final String? current =
        readArbTitle(goldenArb.absolutePath) ??
        readArbTitle(context.resolve(config.templatePath));
    if (current == null) return false;
    final String? committed = await _readCommittedTitle(
      context,
      goldenArb.relativePath,
      config.templatePath,
    );
    return committed != null && committed != current;
  }

  /// 커밋된 상태(HEAD)의 실효 제목 — [goldenArbPath] 의 `appTitle`, 없으면
  /// [templatePath] 의 `appTitle` 이다.
  ///
  /// 어느 파일이든 git 이 읽지 못하면(HEAD 에 없음 포함) null 이다.
  static Future<String?> _readCommittedTitle(
    WizardContext context,
    String goldenArbPath,
    String templatePath,
  ) async {
    final String? goldenSource = await readCommittedFile(
      context,
      goldenArbPath,
    );
    if (goldenSource == null) return null;
    final String? goldenTitle = parseArbTitle(goldenSource);
    if (goldenTitle != null) return goldenTitle;
    final String? templateSource = await readCommittedFile(
      context,
      templatePath,
    );
    return templateSource == null ? null : parseArbTitle(templateSource);
  }

  _AppNamesMode _mode = _AppNamesMode.unreadable;
  String _reason = '';

  /// 직전 검사가 읽은 기본 이름(영어 ARB 의 `appTitle`).
  String _baseName = '';

  /// 직전 검사가 모은 물을 언어(ARB 파일 이름 순).
  List<_NameTarget> _targets = const <_NameTarget>[];

  @override
  String get id => 'app_names';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['identity'];

  // ARB 는 git 으로 되돌릴 수 있고 비용도 들지 않는다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    // 이전 검사의 대상을 들고 가지 않는다 — 아래 판정이 다시 채운다.
    _targets = const <_NameTarget>[];
    final L10nConfig config;
    final List<LocalizedArb> arbs;
    try {
      config = readL10nConfig(context.projectRoot);
      arbs = listLocalizedArbs(context.projectRoot);
    } on GeneratorException catch (e) {
      return _markUnreadable('언어별 ARB 목록을 읽지 못했습니다 — ${e.message}');
    }
    if (arbs.isEmpty) {
      _mode = _AppNamesMode.done;
      return Done('${config.arbDir} 에 영어 ARB 만 있어 물을 언어가 없습니다');
    }
    final String? baseName = readArbTitle(context.resolve(config.templatePath));
    if (baseName == null) {
      return _markUnreadable(
        '${config.templatePath} 에 $appTitleKey 문자열 값이 없습니다',
      );
    }
    _baseName = baseName;

    final unreadable = <String>[];
    final missing = <String>[];
    final violations = <String>[];
    final targets = <_NameTarget>[];
    final decided = <String>[];
    for (final arb in arbs) {
      final String? invalidJson = findInvalidJson(
        arb.absolutePath,
        arb.relativePath,
      );
      if (invalidJson != null) {
        unreadable.add(invalidJson);
        continue;
      }
      final Object? decoded = jsonDecode(
        File(arb.absolutePath).readAsStringSync(),
      );
      // 위 검사가 JSON 객체만 통과시킨다.
      if (decoded is! Map<String, Object?>) continue;
      final Object? value = decoded[appTitleKey];
      if (value == null) {
        // 키가 없거나 값이 null 이면 생성기도 이름 없음으로 본다.
        missing.add(arb.relativePath);
        targets.add(_NameTarget(arb));
        continue;
      }
      final String? violation = _findValueViolation(arb.relativePath, value);
      if (violation != null) {
        violations.add(violation);
        targets.add(_NameTarget(arb, currentValue: value));
        continue;
      }
      decided.add('${arb.locale} $value');
    }
    if (unreadable.isNotEmpty) return _markUnreadable(unreadable.join(' · '));
    if (targets.isEmpty) {
      _mode = _AppNamesMode.done;
      return Done(decided.join(' · '));
    }
    _mode = _AppNamesMode.ask;
    _targets = targets;
    _reason = <String>[
      if (missing.isNotEmpty)
        '${formatArbPaths(missing)} 에 $appTitleKey 이 없습니다',
      ...violations,
    ].join(' · ');
    return Todo(_reason);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    if (_mode != _AppNamesMode.ask) return const <String>[];
    final String paths = formatArbPaths(
      _targets.map((_NameTarget target) => target.arb.relativePath),
    );
    final line =
        '($paths 의 $appTitleKey 에 입력한 이름을 씀 — 키가 없으면 더하고 있으면 '
        '바꾸며, 다음 pub get · 빌드가 lib/l10n/generated/ 를 다시 만듭니다)';
    return <String>[line];
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    try {
      return switch (_mode) {
        _AppNamesMode.unreadable => Failed(_reason),
        _AppNamesMode.done => const Applied(),
        _AppNamesMode.ask => await _applyAsk(context),
      };
    } on GitTreeException catch (e) {
      return Failed(e.message, result: e.result);
    } on FileSystemException catch (e) {
      return Failed('파일을 고치지 못했습니다 — $e');
    } on FormatException catch (e) {
      return Failed('ARB 를 고치지 못했습니다 — $e');
    } on ConfigEditException catch (e) {
      return Failed('언어별 앱 이름을 쓰지 못했습니다 — ${e.message}');
    } on GeneratorException catch (e) {
      return Failed(e.message);
    }
  }

  /// 읽지 못함 모드로 두고 [reason] 을 사유로 한 [Todo] 를 돌려준다.
  Todo _markUnreadable(String reason) {
    _mode = _AppNamesMode.unreadable;
    _reason = reason;
    return Todo(reason);
  }

  /// [relativePath] ARB 의 `appTitle` [value] 가 생성기 규칙에 어긋나는 사유 —
  /// 맞으면 null.
  ///
  /// flavor 접미사로 끝나는 값은 생성기가 받으므로 사유로 삼지 않는다.
  static String? _findValueViolation(String relativePath, Object value) {
    if (value is! String) {
      return '$relativePath 의 $appTitleKey 이 문자열이 아닙니다';
    }
    if (value.trim().isEmpty) {
      return '$relativePath 의 $appTitleKey 이 비어 있습니다';
    }
    if (value != value.trim()) {
      return '$relativePath 의 $appTitleKey "$value" 의 앞뒤에 공백이 있습니다';
    }
    if (hasLauncherNameWhitespaceIssue(value)) {
      return '$relativePath 의 $appTitleKey "$value" 의 공백이 이어집니다';
    }
    return null;
  }

  /// 언어마다 이름을 묻고 확인 표 뒤 대상 ARB 에 쓴다.
  Future<StepOutcome> _applyAsk(WizardContext context) async {
    final Terminal terminal = context.terminal;
    final String flavorName = context.flavor.name;
    final String suffix = flavorDisplayNameSuffixes[flavorName] ?? '';
    final String? appName = _readJsonAppName(
      context.resolve(context.paths.json),
    );
    final bool showsSuffix =
        suffix.isNotEmpty && appName != null && appName.endsWith(suffix);
    if (showsSuffix) {
      terminal
        ..writeLine(
          '  기본 이름은 "$_baseName" 입니다. flavor 접미사("$suffix")는 빌드가 '
          '붙이므로 접미사 없는 이름을 입력하고,',
        )
        ..writeLine('  기본 이름 그대로 쓰려면 Enter 를 누릅니다.');
    } else {
      terminal.writeLine(
        '  기본 이름은 "$_baseName" 입니다. 기본 이름 그대로 쓰려면 Enter 를 '
        '누릅니다.',
      );
    }
    terminal.writeLine('');

    final Map<String, String> endonyms = readLocaleEndonyms(
      context.projectRoot,
    );
    final labels = <String>[
      for (final _NameTarget target in _targets)
        formatLocaleLabel(target.arb.locale, endonyms),
    ];
    final names = List<String>.filled(_targets.length, '');
    for (var i = 0; i < _targets.length; i++) {
      final String? name = _askName(terminal, _targets[i], labels[i]);
      if (name == null) return const Declined();
      if (name.isEmpty) return const Failed(invalidFormatFailure);
      names[i] = name;
    }

    final notes = <String>[
      if (showsSuffix) '$flavorName 빌드에서는 뒤에 "$suffix" 가 붙어 보입니다',
    ];
    // 「<코드> 고치기」 는 그 언어만 다시 묻고 표를 다시 보인다.
    while (true) {
      terminal.writeLine('');
      writeSummary(
        terminal,
        title: confirmTitle,
        rows: <SummaryRow>[
          for (var i = 0; i < _targets.length; i++)
            SummaryRow(labels[i], names[i]),
        ],
        notes: notes,
      );
      terminal.writeLine('');
      final int? choice = terminal.choose(confirmQuestion, <String>[
        proceedOption,
        for (final _NameTarget target in _targets) '${target.arb.locale} 고치기',
      ]);
      if (choice == null) return const Declined();
      if (choice == 0) break;
      final int index = choice - 1;
      final String? name = _askName(terminal, _targets[index], labels[index]);
      if (name == null) return const Declined();
      if (name.isEmpty) return const Failed(invalidFormatFailure);
      names[index] = name;
    }

    return await _writeNames(context, names);
  }

  /// [target] 언어의 이름을 규칙에 맞을 때까지 [maxInputAttempts] 번까지 묻는다.
  ///
  /// 지금 값이 규칙에 어긋나면 그 값을 질문 글에 보이고, 기본값은 늘 기본 이름이다.
  /// 입력 끝이면 null, 끝까지 틀리면 빈 문자열을 돌려준다.
  String? _askName(Terminal terminal, _NameTarget target, String label) {
    final Object? current = target.currentValue;
    final question = current == null
        ? '  $label 앱 이름'
        : '  $label 앱 이름(지금 값 ${jsonEncode(current)})';
    for (var attempt = 0; attempt < maxInputAttempts; attempt++) {
      final String? answer = terminal.ask(question, defaultValue: _baseName);
      if (answer == null) return null;
      final String name = answer.trim();
      final String? problem = _findInputProblem(name);
      if (problem == null) return name;
      terminal.writeLine(problem);
    }
    return '';
  }

  /// 입력 [name] 이 받을 수 없는 이름이면 다시 물을 때의 안내 — 받으면 null.
  ///
  /// 접미사는 빌드가 붙이므로 어느 flavor 접미사로 끝나는 이름도 받지 않는다.
  /// 공백 규칙은 빌드 생성기의 판정을 그대로 쓴다.
  static String? _findInputProblem(String name) {
    if (name.isEmpty) return emptyNameMessage;
    for (final MapEntry<String, String> entry
        in flavorDisplayNameSuffixes.entries) {
      final String suffix = entry.value;
      final String flavorName = entry.key;
      if (suffix.isNotEmpty && name.endsWith(suffix)) {
        return '  "$suffix" 는 $flavorName 빌드가 붙이므로 접미사 없는 이름을 입력하세요';
      }
    }
    if (hasLauncherNameWhitespaceIssue(name)) return repeatedWhitespaceMessage;
    return null;
  }

  /// 쓰기 전 검사를 모두 통과하면 대상 ARB 마다 [names] 를 쓴다.
  ///
  /// 고칠 ARB 에 미커밋 변경이 있거나 · 하나라도 JSON 객체로 읽히지 않으면 어떤
  /// 파일도 쓰지 않고, 쓰다가 실패하면 이미 쓴 파일을 되돌린다.
  Future<StepOutcome> _writeNames(
    WizardContext context,
    List<String> names,
  ) async {
    final List<String> dirty = await findDirtyTrackedFiles(context, <String>[
      for (final _NameTarget target in _targets) target.arb.relativePath,
    ]);
    if (dirty.isNotEmpty) {
      return Failed(
        '고칠 파일에 커밋하지 않은 변경이 있습니다 — ${IdentityStep.dirtyTreeGuidance}\n'
        '${dirty.map((String path) => '    $path').join('\n')}',
      );
    }
    for (final _NameTarget target in _targets) {
      final String? invalidJson = findInvalidJson(
        target.arb.absolutePath,
        target.arb.relativePath,
      );
      if (invalidJson != null) return Failed(invalidJson);
    }
    _writeTitlesAtomically(names);
    // 실행 블록 끝(✓ 줄 바로 앞)에 golden 안내만 보이고 명령은 실행하지 않는다.
    if (await needsGoldenHint(context)) {
      context.terminal.writeLine('  $goldenHintLine');
    }
    return const Applied();
  }

  /// 대상 ARB 마다 [names] 를 차례로 쓰고, 하나라도 실패하면 이미 쓴 파일을
  /// 원본으로 되돌린 뒤 그 예외를 그대로 올린다 — 일부 파일만 바뀐 상태를 남기지
  /// 않는다.
  void _writeTitlesAtomically(List<String> names) {
    final originals = <String, String>{
      for (final _NameTarget target in _targets)
        target.arb.absolutePath: File(
          target.arb.absolutePath,
        ).readAsStringSync(),
    };
    final written = <String>[];
    try {
      for (var i = 0; i < _targets.length; i++) {
        final String path = _targets[i].arb.absolutePath;
        writeArbTitle(path, names[i]);
        written.add(path);
      }
    } on Exception {
      for (final path in written) {
        writeFileAtomically(path, originals[path]!);
      }
      rethrow;
    }
  }

  /// [path] JSON 의 `appName` 문자열 값을 읽는다 — 파일이나 값이 없으면 null.
  static String? _readJsonAppName(String path) =>
      File(path).existsSync() ? readJsonString(path, 'appName') : null;
}

/// 언어별 앱 이름 단계의 실행 모드 — 직전 검사가 정한다.
enum _AppNamesMode {
  /// ARB 목록 · 기본 이름 · ARB 내용을 읽지 못함 — 실행은 그 사유로 실패한다.
  unreadable,

  /// 물을 언어가 있음.
  ask,

  /// 모든 언어가 정해졌거나 물을 언어가 없음.
  done,
}

/// 물을 언어 하나 — ARB 와 규칙에 어긋난 지금 값(키가 없으면 null).
final class _NameTarget {
  const _NameTarget(this.arb, {this.currentValue});

  final LocalizedArb arb;
  final Object? currentValue;
}
