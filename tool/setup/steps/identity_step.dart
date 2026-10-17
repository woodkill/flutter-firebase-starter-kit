import 'dart:io';

import '../../../bin/rename.dart' as rename;
import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../flavor.dart';
import '../git_tree.dart';
import '../gradle_identity.dart';
import '../step.dart';
import '../terminal.dart';
import '../wizard.dart';
import 'configure_step.dart';

/// 앱 정체성 단계 — org · name 두 값으로 앱 ID · 번들 ID · 프로젝트 prefix ·
/// 표시 이름을 한 번의 확인으로 바꾼다.
///
/// 계산 · 검증 · 변경은 `bin/rename.dart` 의 공개 함수를 그대로 부른다. 확인은
/// 단계 진행 확인과 값 요약 표 한 번으로 끝나고 rename 도구 자체의 확인 질문은
/// 거치지 않는다. 표시 이름은 rename 뒤 사용자 파일의 `appName` · `DISPLAY_NAME`
/// 에 위저드가 직접 쓴다. 앱 ID 가 이미 바뀐 저장소에서 사용자 xcconfig 에 남은
/// 킷 번들 ID 는 묻지 않고 앱 ID 에 맞춘다.
///
/// 경로 · 표시 이름 접미사는 고른 flavor 를 따른다. 앱 ID 는 flavor 가 함께
/// 쓰므로 이름 바꾸기는 모든 flavor 를 바꾸지만, 표시 이름은 그 flavor 의
/// 사용자 파일에만 쓴다. dev 가 아닌 flavor 는 그 flavor 의 사용자 xcconfig
/// 번들 ID 만 맞춘다 — 다른 flavor 의 사용자 파일은 건드리지 않는다.
final class IdentityStep implements Step {
  /// 앱 정체성 단계를 만든다.
  IdentityStep();

  /// Android 앱 ID 를 읽는 Gradle 파일.
  static const String gradlePath = 'android/app/build.gradle.kts';

  /// 확인 표 제목.
  static const String confirmTitle = '앱 정체성 — 확인';

  /// 확인 표 경고.
  static const String storeWarning = '스토어에 올린 뒤에는 앱 ID 를 바꿀 수 없습니다.';

  /// 미리보기 뒤 고르기 질문.
  static const String previewChoiceQuestion = '미리보기 값으로 진행할까요, 고칠까요?';

  /// 미리보기 고르기 — 진행.
  static const String proceedOption = '이대로 진행';

  /// 미리보기 고르기 — 프로젝트 prefix 고치기.
  static const String editPrefixOption = '프로젝트 prefix 고치기';

  /// 미리보기 고르기 — 표시 이름 고치기.
  static const String editDisplayNameOption = '표시 이름 고치기';

  /// org 질문.
  static const String orgQuestion = 'org — 역순 도메인 (예: com.mycompany)';

  /// name 질문.
  static const String nameQuestion = 'name — 소문자 snake_case (예: my_app)';

  /// 프로젝트 prefix 질문.
  static const String prefixQuestion =
      '프로젝트 prefix — 소문자 · 숫자 · - 로 2~25자 (예: my-app)';

  /// 표시 이름 질문.
  static const String displayNameQuestion =
      '표시 이름 — 영문 · 숫자 · 공백 (예: My App Dev)';

  /// org 형식 오류.
  static const String invalidOrgMessage =
      '  org 형식이 아닙니다 — 소문자로 시작하는 역순 도메인이어야 합니다 (예: com.mycompany)';

  /// name 형식 오류.
  static const String invalidNameMessage =
      '  name 형식이 아닙니다 — 소문자로 시작하는 snake_case 여야 합니다 (예: my_app)';

  /// 프로젝트 prefix 형식 오류.
  static const String invalidPrefixMessage =
      '  프로젝트 prefix 형식이 아닙니다 — 소문자로 시작하고 소문자 · 숫자 · - 만 쓰며 '
      '- 로 끝나지 않는 2~25자여야 합니다';

  /// 표시 이름 형식 오류.
  static const String invalidDisplayNameMessage =
      '  표시 이름은 영문 · 숫자 · 공백만 쓸 수 있습니다';

  /// 고칠 파일에 미커밋 변경이 있을 때의 안내.
  static const String dirtyTreeGuidance = '커밋하거나 되돌린 뒤 다시 시도하세요';

  /// configure 스크립트의 Android 패키지 prefix 상수 이름.
  static const String androidPrefixKey = 'ANDROID_PACKAGE_PREFIX';

  /// configure 스크립트의 iOS 번들 ID prefix 상수 이름.
  static const String iosPrefixKey = 'IOS_BUNDLE_ID_PREFIX';

  /// Gradle 앱 ID 와 configure 스크립트 상수 · 추적 파일이 어긋났을 때의 안내.
  static const String inconsistentGuidance =
      '이름 바꾸기가 중간에 끊겼다면 git status 로 바뀐 파일을 확인하고 '
      'git restore . 로 되돌린 뒤 다시 실행하세요';

  /// Kotlin 디렉토리 이동의 복사 검증이 어긋났을 때의 안내.
  static const String moveFailedGuidance =
      'Kotlin 디렉토리를 옮기지 못했습니다 — git status 로 바뀐 파일을 확인하고 '
      'git restore . 로 되돌린 뒤 다시 시도하세요';

  /// 같은 질문을 다시 묻는 최대 횟수.
  static const int maxInputAttempts = 3;

  /// 표시 이름 규칙 — 영문 · 숫자 · 공백(앞뒤 공백은 뗀 뒤 검사).
  static final RegExp displayNamePattern = RegExp(r'^[A-Za-z0-9 ]+$');

  _IdentityMode _mode = _IdentityMode.unreadable;
  String _reason = '';
  String _applicationId = '';

  /// 직전 검사가 모은 사용자 xcconfig 의 킷 번들 ID 줄 변경.
  List<rename.FileChange> _xcconfigResidue = const <rename.FileChange>[];

  @override
  String get id => 'identity';

  @override
  String get title => '앱 정체성';

  @override
  List<String> get dependsOn => const <String>['user_files'];

  // 확인 표는 org · name 부터 진행하는 모드에서만 보인다 — 표시 이름만 쓰는
  // 모드 · 번들 ID 만 맞추는 모드 · 실패 전용 모드에는 안내가 붙지 않는다.
  @override
  bool get isCostlyOrIrreversible => _mode == _IdentityMode.full;

  @override
  Future<CheckResult> check(WizardContext context) async {
    // 이전 검사의 잔여를 들고 가지 않는다 — 아래 판정이 다시 채운다.
    _xcconfigResidue = const <rename.FileChange>[];
    final String? applicationId = readGradleApplicationId(
      context.resolve(gradlePath),
    );
    if (applicationId == null) {
      _mode = _IdentityMode.unreadable;
      _reason = '$gradlePath 에서 applicationId 를 읽지 못했습니다';
      return Todo(_reason);
    }
    _applicationId = applicationId;
    if (_applicationId == rename.currentAndroidPackage) {
      _mode = _IdentityMode.full;
      _reason = 'Android 앱 ID 가 킷 기본값입니다 ($_applicationId)';
      return Todo(_reason);
    }
    // 이름 바꾸기는 Gradle 줄을 가장 먼저 쓰므로, 뒤에 쓰는 스크립트 상수와
    // 마지막에 쓰는 placeholder 까지 같은 정체성인지 봐야 중간에 끊긴 상태를
    // 끝난 것으로 보지 않는다.
    final String? scriptMismatch = _findScriptMismatch(context, _applicationId);
    final _RenameResidue residue = scriptMismatch == null
        ? _collectRenameResidue(context, _applicationId)
        : _noRenameResidue;
    final String? mismatch =
        scriptMismatch ?? _describeTrackedResidue(context, residue.tracked);
    if (mismatch != null) {
      _mode = _IdentityMode.inconsistent;
      _reason = '앱 정체성이 파일마다 다릅니다 — $mismatch. $inconsistentGuidance';
      return Todo(_reason);
    }
    _xcconfigResidue = residue.userXcconfig;
    if (_isDisplayNameDefault(context)) {
      _mode = _IdentityMode.displayNameOnly;
      _reason = '표시 이름이 킷 기본값입니다';
      return Todo(_reason);
    }
    if (_xcconfigResidue.isNotEmpty) {
      final String paths = _listTargetPaths(
        context,
        _xcconfigResidue,
      ).join(' · ');
      _mode = _IdentityMode.bundleIdOnly;
      _reason = '$paths 의 번들 ID 가 킷 기본값입니다';
      return Todo(_reason);
    }
    _mode = _IdentityMode.done;
    return Done('Android 앱 ID $_applicationId');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    final FlavorPaths paths = context.paths;
    final List<String> displayNameLines = <String>[
      '(${paths.json} 의 appName 을 표시 이름으로 바꿈)',
      '(${paths.xcconfig} 의 DISPLAY_NAME 을 표시 이름으로 바꿈)',
    ];
    final List<String> bundleIdLines = <String>[
      for (final String path in _listTargetPaths(context, _xcconfigResidue))
        '($path 의 PRODUCT_BUNDLE_IDENTIFIER 를 앱 ID 에 맞춤)',
    ];
    return switch (_mode) {
      _IdentityMode.full => <String>[
        '(org · name 을 묻고 미리보기와 확인 표를 보인 뒤 아래와 같은 일을 합니다)',
        'fvm dart run bin/rename.dart --org <org> --name <name> '
            '--project-prefix <prefix> --apply --yes',
        ...displayNameLines,
      ],
      _IdentityMode.displayNameOnly => <String>[
        ...bundleIdLines,
        ...displayNameLines,
      ],
      _IdentityMode.bundleIdOnly => bundleIdLines,
      _IdentityMode.unreadable ||
      _IdentityMode.inconsistent ||
      _IdentityMode.done => const <String>[],
    };
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    try {
      return switch (_mode) {
        _IdentityMode.full => await _applyFull(context),
        _IdentityMode.displayNameOnly => _applyDisplayNameOnly(context),
        _IdentityMode.bundleIdOnly => _applyBundleIdOnly(),
        _IdentityMode.unreadable ||
        _IdentityMode.inconsistent => Failed(_reason),
        _IdentityMode.done => const Applied(),
      };
    } on GitTreeException catch (e) {
      return Failed(e.message, result: e.result);
    } on rename.MoveVerificationException catch (e) {
      // 앞서 적용된 치환은 이미 파일에 써진 상태다 — 되돌린 뒤 다시 시도하게 하고,
      // rename 의 원문은 결과로 넘겨 가림 터미널 · 실행 기록에 남긴다.
      return Failed(
        moveFailedGuidance,
        result: CommandResult(1, '', e.message),
      );
    } on FileSystemException catch (e) {
      return Failed('파일을 고치지 못했습니다 — $e');
    } on FormatException catch (e) {
      return Failed('${context.paths.json} 을 고치지 못했습니다 — $e');
    } on StateError catch (e) {
      return Failed('표시 이름을 쓰지 못했습니다 — ${e.message}');
    }
  }

  /// org · name 을 묻고 미리보기 · 확인 뒤 rename 함수와 표시 이름 쓰기를 실행한다.
  Future<StepOutcome> _applyFull(WizardContext context) async {
    final Terminal terminal = context.terminal;
    final ({String org, String name})? inputs = _askOrgAndName(terminal);
    if (inputs == null) return const Declined();
    final String org = inputs.org;
    final String name = inputs.name;
    if (org.isEmpty) {
      return const Failed('org · name 형식이 맞지 않아 진행하지 않았습니다');
    }

    String prefix = name.replaceAll('_', '-');
    final Flavor flavor = context.flavor;
    String displayName =
        '${rename.toTitleCase(name)}${flavor.displayNameSuffix}';
    while (true) {
      final List<SummaryRow> rows = _buildRows(
        org,
        name,
        prefix,
        displayName,
        flavor,
      );
      _writePreview(terminal, rows);
      final int? choice = terminal.choose(previewChoiceQuestion, const <String>[
        proceedOption,
        editPrefixOption,
        editDisplayNameOption,
      ]);
      if (choice == null) return const Declined();
      if (choice == 1) {
        final String? edited = _askValid(
          terminal,
          question: prefixQuestion,
          defaultValue: prefix,
          isValid: (String value) =>
              rename.validateProjectPrefix(value).isValid,
          invalidMessage: invalidPrefixMessage,
        );
        if (edited == null) return const Declined();
        if (edited.isNotEmpty) prefix = edited;
        continue;
      }
      if (choice == 2) {
        final String? edited = _askValid(
          terminal,
          question: displayNameQuestion,
          defaultValue: displayName,
          isValid: isValidDisplayName,
          invalidMessage: invalidDisplayNameMessage,
        );
        if (edited == null) return const Declined();
        if (edited.isNotEmpty) displayName = edited;
        continue;
      }
      if (!rename.validateProjectPrefix(prefix).isValid) {
        // name 에서 계산한 prefix 가 규칙 밖이면(예: 한 글자) 고친 뒤에만 진행한다.
        terminal.writeLine(invalidPrefixMessage);
        continue;
      }
      if (!confirmSummary(
        terminal,
        title: confirmTitle,
        rows: rows,
        warnings: const <String>[storeWarning],
      )) {
        return const Declined();
      }
      break;
    }

    final String? missingTarget = _findMissingDisplayNameTarget(context);
    if (missingTarget != null) return Failed(missingTarget);

    final List<rename.FileChange> changes = rename.collectChanges(
      context.projectRoot,
      org,
      name,
      projectIdPrefix: prefix,
    );
    final List<String> dirty = await findDirtyTrackedFiles(
      context,
      _listTargetPaths(context, changes),
    );
    if (dirty.isNotEmpty) {
      return Failed(
        '고칠 파일에 커밋하지 않은 변경이 있습니다 — $dirtyTreeGuidance\n'
        '${dirty.map((String path) => '    $path').join('\n')}',
      );
    }

    rename.applyChanges(changes);
    _writeDisplayName(context, displayName);
    return const Applied();
  }

  /// 표시 이름만 묻고 두 사용자 파일에 쓴다 — 추적 파일 이름 바꾸기는 하지
  /// 않는다.
  ///
  /// 직전 검사가 모은 사용자 xcconfig 의 킷 번들 ID 도 표시 이름이 정해진 뒤
  /// 함께 맞춘다 — 거절하면 아무 파일도 바꾸지 않는다.
  StepOutcome _applyDisplayNameOnly(WizardContext context) {
    final String? missingTarget = _findMissingDisplayNameTarget(context);
    if (missingTarget != null) return Failed(missingTarget);

    final String suggested =
        '${rename.toTitleCase(_applicationId.split('.').last)}'
        '${context.flavor.displayNameSuffix}';
    final String? displayName = _askValid(
      context.terminal,
      question: displayNameQuestion,
      defaultValue: isValidDisplayName(suggested) ? suggested : null,
      isValid: isValidDisplayName,
      invalidMessage: invalidDisplayNameMessage,
    );
    if (displayName == null) return const Declined();
    if (displayName.isEmpty) {
      return const Failed('표시 이름 형식이 맞지 않아 진행하지 않았습니다');
    }
    rename.applyChanges(_xcconfigResidue);
    _writeDisplayName(context, displayName);
    return const Applied();
  }

  /// 직전 검사가 모은 사용자 xcconfig 의 킷 번들 ID 줄만 앱 ID 에 맞춘다.
  ///
  /// 값은 앱 ID 에서 정해지므로 묻지 않는다. gitignored 사용자 파일이라 깨끗함
  /// 검사도 하지 않는다.
  StepOutcome _applyBundleIdOnly() {
    rename.applyChanges(_xcconfigResidue);
    return const Applied();
  }

  /// [value] 가 표시 이름 규칙(앞뒤 공백을 뗀 뒤 영문 · 숫자 · 공백, 빈 값 아님)에 맞는지 본다.
  static bool isValidDisplayName(String value) {
    final String trimmed = value.trim();
    return trimmed.isNotEmpty && displayNamePattern.hasMatch(trimmed);
  }

  /// org · name 을 묻는다 — 입력 끝이면 null, 형식이 [maxInputAttempts] 번 틀리면
  /// 빈 org 를 돌려준다.
  ///
  /// 맞다고 판정된 org 는 다음 시도로 들고 가 다시 묻지 않고 name 만 묻는다.
  /// org 가 틀린 시도 뒤에는 org 부터 다시 묻는다. 시도는 org · name 을 묻든
  /// name 만 묻든 한 번으로 센다.
  ({String org, String name})? _askOrgAndName(Terminal terminal) {
    String? validOrg;
    for (int attempt = 0; attempt < maxInputAttempts; attempt++) {
      final String? org = validOrg ?? terminal.ask(orgQuestion);
      if (org == null) return null;
      final String? name = terminal.ask(nameQuestion);
      if (name == null) return null;
      if (rename.validateInputs(org, name).isValid) {
        return (org: org, name: name);
      }
      // name 자리에 늘 맞는 값을 넣어 어느 쪽이 틀렸는지 가린다.
      final bool isOrgValid = rename.validateInputs(org, 'app').isValid;
      validOrg = isOrgValid ? org : null;
      terminal.writeLine(isOrgValid ? invalidNameMessage : invalidOrgMessage);
    }
    return (org: '', name: '');
  }

  /// [question] 을 규칙에 맞을 때까지 [maxInputAttempts] 번까지 묻는다.
  ///
  /// 입력 끝이면 null, 끝까지 틀리면 빈 문자열을 돌려준다.
  String? _askValid(
    Terminal terminal, {
    required String question,
    required bool Function(String value) isValid,
    required String invalidMessage,
    String? defaultValue,
  }) {
    for (int attempt = 0; attempt < maxInputAttempts; attempt++) {
      final String? answer = terminal.ask(question, defaultValue: defaultValue);
      if (answer == null) return null;
      final String trimmed = answer.trim();
      if (isValid(trimmed)) return trimmed;
      terminal.writeLine(invalidMessage);
    }
    return '';
  }

  /// 미리보기 · 확인 표의 값 행을 만든다 — 앱 ID 뒤에 [flavor] 접미사를
  /// 괄호로 붙인다(접미사가 없는 flavor 는 붙이지 않는다).
  List<SummaryRow> _buildRows(
    String org,
    String name,
    String prefix,
    String displayName,
    Flavor flavor,
  ) {
    final String suffix = flavor.suffix.isEmpty ? '' : '(${flavor.suffix})';
    return <SummaryRow>[
      SummaryRow('org', org),
      SummaryRow('name', name),
      SummaryRow('Android 앱 ID', '$org.$name$suffix'),
      SummaryRow('iOS 번들 ID', '$org.${rename.toLowerCamelCase(name)}$suffix'),
      SummaryRow('프로젝트 prefix', prefix),
      SummaryRow('표시 이름', displayName),
    ];
  }

  /// 미리보기 표를 보인다 — 라벨은 화면 폭 기준으로 맞춘다.
  void _writePreview(Terminal terminal, List<SummaryRow> rows) {
    final int labelWidth = rows.fold<int>(0, (int widest, SummaryRow row) {
      final int width = measureDisplayWidth(row.label);
      return width > widest ? width : widest;
    });
    terminal.writeLine('앱 정체성 — 미리보기');
    for (final SummaryRow row in rows) {
      final int padding = labelWidth - measureDisplayWidth(row.label);
      terminal.writeLine('  ${row.label}${' ' * padding}  ${row.value}');
    }
  }

  /// rename 변경 목록을 깨끗함 검사 대상(저장소 상대 경로)으로 바꾼다.
  ///
  /// 디렉터리 이동은 이동 원본 디렉터리 항목 하나로 넣는다(그 아래 추적 파일 전부가
  /// 대상). 이동 뒤 새 경로를 가리키는 변경은 아직 없는 파일이라 넣지 않는다.
  List<String> _listTargetPaths(
    WizardContext context,
    List<rename.FileChange> changes,
  ) {
    final String rootPrefix = '${context.projectRoot}/';
    final List<String> paths = <String>[];
    for (final rename.FileChange change in changes) {
      final bool isMove = change.type == rename.ChangeType.move;
      if (!isMove && !File(change.filePath).existsSync()) continue;
      final String relative = change.filePath.startsWith(rootPrefix)
          ? change.filePath.substring(rootPrefix.length)
          : change.filePath;
      if (!paths.contains(relative)) paths.add(relative);
    }
    return paths;
  }

  /// 표시 이름을 쓸 키 · 변수가 없으면 그 사유를 돌려준다 — 모두 있으면 null.
  String? _findMissingDisplayNameTarget(WizardContext context) {
    final FlavorPaths paths = context.paths;
    final String jsonPath = context.resolve(paths.json);
    final String xcconfigPath = context.resolve(paths.xcconfig);
    if (!File(jsonPath).existsSync() ||
        readJsonString(jsonPath, 'appName') == null) {
      return '${paths.json} 에 appName 문자열 값이 없습니다';
    }
    if (!File(xcconfigPath).existsSync() ||
        readXcconfigValue(xcconfigPath, 'DISPLAY_NAME') == null) {
      return '${paths.xcconfig} 에 DISPLAY_NAME 이 없습니다';
    }
    return null;
  }

  /// 표시 이름을 고른 flavor 의 사용자 JSON `appName` · xcconfig
  /// `DISPLAY_NAME` 에 쓴다.
  void _writeDisplayName(WizardContext context, String displayName) {
    replaceJsonString(
      context.resolve(context.paths.json),
      'appName',
      displayName,
    );
    replaceXcconfigValue(
      context.resolve(context.paths.xcconfig),
      'DISPLAY_NAME',
      displayName,
    );
  }

  /// configure 스크립트의 prefix 상수가 [applicationId] 와 같은 정체성인지 본다.
  ///
  /// `ANDROID_PACKAGE_PREFIX` 는 앱 ID 와 같고, `IOS_BUNDLE_ID_PREFIX` 는
  /// org + name 의 lowerCamel 이어야 한다(이름 바꾸기 규칙). 어긋난 첫 상수를
  /// 설명하는 문장을, 모두 같으면 null 을 돌려준다.
  static String? _findScriptMismatch(
    WizardContext context,
    String applicationId,
  ) {
    final String scriptPath = ConfigureStep.scriptPath;
    final File script = File(context.resolve(scriptPath));
    if (!script.existsSync()) return '$scriptPath 이 없습니다';
    final String content = script.readAsStringSync();
    final int nameStart = applicationId.lastIndexOf('.');
    // 점이 없는 앱 ID 는 org 가 없다 — 그때는 앱 ID 를 그대로 기대한다.
    final String org = nameStart < 0
        ? ''
        : applicationId.substring(0, nameStart);
    final String name = applicationId.substring(nameStart + 1);
    final String expectedIos = nameStart < 0
        ? applicationId
        : '$org.${rename.toLowerCamelCase(name)}';
    for (final (String key, String expected) in <(String, String)>[
      (androidPrefixKey, applicationId),
      (iosPrefixKey, expectedIos),
    ]) {
      final String? actual = _readScriptConstant(content, key);
      if (actual != expected) {
        return '$scriptPath 의 $key 가 ${actual ?? '(없음)'} 입니다(기대 $expected)';
      }
    }
    return null;
  }

  /// 이름 바꾸기 대상 가운데 아직 킷 옛 값을 담은 곳을 추적 파일 몫과 사용자
  /// xcconfig 몫으로 나눠 모은다.
  ///
  /// [applicationId] 를 org · name 으로 나눠 `rename.collectChanges` 를 한 번
  /// 부르면 각 수집기가 옛 값이 남은 대상만 돌려준다 — 끝난 저장소는 둘 다
  /// 빈 목록이다. 사용자 config appName 은 옛 값과 관계없이 표시 이름이 다르면
  /// 늘 등록하므로 버린다(표시 이름은 [_isDisplayNameDefault] 가 따로 본다).
  /// 사용자 xcconfig 번들 ID 는 추적 파일 몫에서 빼서 따로 돌려준다 — 사용자
  /// 파일 잔여는 위저드가 직접 맞춘다. 있는 파일만 수집되므로 없는 stg · prod
  /// 사용자 파일은 건너뛴다. dev 실행은 있는 모든 flavor 의 사용자 xcconfig 를,
  /// 다른 flavor 실행은 그 flavor 의 사용자 xcconfig 만 맞추고 나머지는 버린다.
  /// 프로젝트 prefix 는 사용자가 고른 값이라 킷 값을 넘겨 변경 없음으로 빠지게
  /// 한다.
  _RenameResidue _collectRenameResidue(
    WizardContext context,
    String applicationId,
  ) {
    final int nameStart = applicationId.lastIndexOf('.');
    // org 가 없는 앱 ID 는 이름 바꾸기 규칙 밖이라 대조하지 않는다.
    if (nameStart <= 0) return _noRenameResidue;
    final Set<String> configPaths = <String>{
      for (final String fileName in rename.userConfigFileNames)
        context.resolve('config/$fileName'),
    };
    final Set<String> xcconfigPaths = <String>{
      for (final String fileName in rename.userXcconfigFileNames)
        context.resolve('ios/Flutter/$fileName'),
    };
    final String ownXcconfigPath = context.resolve(context.paths.xcconfig);
    final bool isDevFlavor = context.flavor == Flavor.dev;
    final List<rename.FileChange> tracked = <rename.FileChange>[];
    final List<rename.FileChange> userXcconfig = <rename.FileChange>[];
    for (final rename.FileChange change in rename.collectChanges(
      context.projectRoot,
      applicationId.substring(0, nameStart),
      applicationId.substring(nameStart + 1),
      projectIdPrefix: rename.currentProjectIdPrefix,
    )) {
      if (configPaths.contains(change.filePath)) continue;
      if (xcconfigPaths.contains(change.filePath)) {
        if (isDevFlavor || change.filePath == ownXcconfigPath) {
          userXcconfig.add(change);
        }
      } else {
        tracked.add(change);
      }
    }
    return (tracked: tracked, userXcconfig: userXcconfig);
  }

  /// 추적 파일 잔여 [residue] 를 설명하는 문장을 만든다 — 없으면 null.
  String? _describeTrackedResidue(
    WizardContext context,
    List<rename.FileChange> residue,
  ) {
    if (residue.isEmpty) return null;
    final String paths = _listTargetPaths(context, residue).join(' · ');
    return '옛 앱 ID 가 남은 파일: $paths';
  }

  /// 스크립트 본문에서 줄 머리가 `[key]="…"` 인 상수 값을 읽는다 — 없으면 null.
  static String? _readScriptConstant(String content, String key) => RegExp(
    '^${RegExp.escape(key)}="([^"]*)"',
    multiLine: true,
  ).firstMatch(content)?.group(1);

  /// 표시 이름이 킷 기본값(appName 이 킷 이름으로 시작 · DISPLAY_NAME 이 example 값)인지 본다.
  bool _isDisplayNameDefault(WizardContext context) {
    final FlavorPaths paths = context.paths;
    final String jsonPath = context.resolve(paths.json);
    final String xcconfigPath = context.resolve(paths.xcconfig);
    final String examplePath = context.resolve(paths.xcconfigExample);
    final String? appName = File(jsonPath).existsSync()
        ? readJsonString(jsonPath, 'appName')
        : null;
    if (appName == null || appName.startsWith(rename.currentAppName)) {
      return true;
    }
    final String? displayName = File(xcconfigPath).existsSync()
        ? readXcconfigValue(xcconfigPath, 'DISPLAY_NAME')
        : null;
    final String? exampleDisplayName = File(examplePath).existsSync()
        ? readXcconfigValue(examplePath, 'DISPLAY_NAME')
        : null;
    return displayName == null || displayName == exampleDisplayName;
  }
}

/// 직전 검사의 판정.
enum _IdentityMode {
  /// 앱 ID 가 킷 기본값 — org · name 부터 진행.
  full,

  /// 앱 ID 는 바뀌었고 표시 이름이 기본값 — 사용자 xcconfig 의 킷 번들 ID 가
  /// 남았으면 함께 맞춘다.
  displayNameOnly,

  /// 앱 ID · 표시 이름은 바뀌었고 사용자 xcconfig 의 번들 ID 만 킷 값.
  bundleIdOnly,

  /// Gradle 파일에서 앱 ID 를 읽지 못함.
  unreadable,

  /// Gradle 앱 ID 와 configure 스크립트 상수 · 추적 파일이 다름 — 이름 바꾸기가
  /// 중간에 끊김.
  inconsistent,

  /// 끝남.
  done,
}

/// 이름 바꾸기 잔여 — 추적 파일 몫과 사용자 xcconfig 번들 ID 몫.
typedef _RenameResidue = ({
  List<rename.FileChange> tracked,
  List<rename.FileChange> userXcconfig,
});

/// 대조하지 않았거나 남은 것이 없는 잔여.
const _RenameResidue _noRenameResidue = (
  tracked: <rename.FileChange>[],
  userXcconfig: <rename.FileChange>[],
);
