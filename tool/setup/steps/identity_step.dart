import 'dart:io';

import '../../../bin/rename.dart' as rename;
import '../../launcher_names.dart' show GeneratorException, stripFlavorSuffix;
import '../arb_titles.dart'
    show
        findInvalidArbTitle,
        findInvalidJson,
        formatArbPaths,
        listLocalizedArbs,
        readArbTitle;
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
/// 거치지 않는다. rename 변경 가운데 사용자 config `appName` 치환은 적용하지
/// 않는다 — 다른 flavor 에 정해진 표시 이름을 덮지 않기 위함이다. 표시 이름은
/// rename 뒤 고른 flavor 사용자 파일의 `appName` · `DISPLAY_NAME`
/// 에 위저드가 직접 쓰고, 영어 ARB([arbPath])의 `appTitle` 에는 그 flavor
/// 접미사를 뗀 기본 이름을 쓴다(빌드의 홈 화면 이름 생성기와 같은 규칙). 앱 ID 가
/// 이미 바뀐 저장소에서 사용자 xcconfig 에 남은 킷 번들 ID 는 묻지 않고 앱 ID 에
/// 맞춘다. 표시 이름이 이미 정해졌는데 영어 ARB `appTitle` 만 그 기본 이름과
/// 다르면 묻지 않고 ARB 를 맞춘다. JSON `appName` 과 xcconfig `DISPLAY_NAME` 이
/// 서로 다르면 표시 이름을 다시 묻고 두 곳에 같은 값을 쓴다. 다시 물을 때 다른
/// flavor 의 기본 이름이 없으면 킷 기본값이 아닌 이 flavor JSON `appName` 을
/// 제안한다.
///
/// 영어 ARB `appTitle` 은 세 flavor 가 함께 쓴다. 그래서 다른 flavor 사용자
/// 파일에 이미 정해진 표시 이름이 있으면 그 기본 이름을 표시 이름 제안값에 쓰고,
/// 쓰려는 기본 이름이 그것과 다르면 어느 파일도 바꾸지 않고 실패한다. 다른 flavor
/// 파일이 없거나 킷 기본값이면 대조하지 않는다.
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

  /// 표시 이름의 기본 이름(flavor 접미사를 뗀 값)을 `appTitle` 로 쓰는 영어 ARB.
  ///
  /// 빌드는 이 값이 config 기본 이름과 다르면 멈추므로 표시 이름과 함께 쓴다.
  static const String arbPath = 'lib/l10n/app_en.arb';

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

  /// 쓰려는 기본 이름이 다른 flavor 의 기본 이름과 다를 때 붙이는 안내.
  static const String baseNameConflictGuidance =
      '영어 appTitle 은 세 flavor 가 함께 쓰므로 세 flavor 의 표시 이름은 flavor '
      '접미사를 뗀 기본 이름이 같아야 합니다';

  /// 세 flavor 의 기본 이름이 어긋나 표시 이름 하나로 풀 수 없을 때의 안내.
  static const String alignFlavorsGuidance =
      '세 flavor 사용자 파일의 표시 이름을 같은 기본 이름으로 맞춘 뒤 다시 실행하세요';

  /// 같은 질문을 다시 묻는 최대 횟수.
  static const int maxInputAttempts = 3;

  /// 표시 이름 규칙 — 영문 · 숫자 · 공백(앞뒤 공백은 뗀 뒤 검사).
  static final RegExp displayNamePattern = RegExp(r'^[A-Za-z0-9 ]+$');

  _IdentityMode _mode = _IdentityMode.unreadable;
  String _reason = '';
  String _applicationId = '';

  /// 직전 검사가 읽은 표시 이름의 기본 이름(flavor 접미사를 뗀 config 값).
  String _baseName = '';

  /// 직전 검사가 모은 사용자 xcconfig 의 킷 번들 ID 줄 변경.
  List<rename.FileChange> _xcconfigResidue = const <rename.FileChange>[];

  /// 직전 검사가 모은 — 영어 ARB 의 지금 `appTitle` 과 같은 값을 가진 다른 언어
  /// ARB 의 저장소 상대 경로(파일 이름 순).
  List<String> _arbCopyPaths = const <String>[];

  @override
  String get id => 'identity';

  @override
  String get title => '앱 정체성';

  @override
  List<String> get dependsOn => const <String>['user_files'];

  // 확인 표는 org · name 부터 진행하는 모드에서만 보인다 — 표시 이름만 쓰는
  // 모드 · 번들 ID 만 맞추는 모드 · 영어 ARB 만 맞추는 모드 · 실패 전용 모드에는
  // 안내가 붙지 않는다.
  @override
  bool get isCostlyOrIrreversible => _mode == _IdentityMode.full;

  @override
  Future<CheckResult> check(WizardContext context) async {
    // 이전 검사의 잔여를 들고 가지 않는다 — 아래 판정이 다시 채운다.
    _xcconfigResidue = const <rename.FileChange>[];
    _arbCopyPaths = const <String>[];
    final String? applicationId = readGradleApplicationId(
      context.resolve(gradlePath),
    );
    if (applicationId == null) {
      _mode = _IdentityMode.unreadable;
      _reason = '$gradlePath 에서 applicationId 를 읽지 못했습니다';
      return Todo(_reason);
    }
    _applicationId = applicationId;
    // 계획 줄 · 미커밋 검사가 어느 판정으로 돌아가도 같은 목록을 쓰도록 판정
    // 앞에서 모은다 — 판정 · 사유는 바꾸지 않는다.
    _arbCopyPaths = _collectArbCopyPaths(context);
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
    final String? defaultDisplayName = _describeDefaultDisplayName(context);
    if (defaultDisplayName != null) {
      _mode = _IdentityMode.displayNameOnly;
      _reason = defaultDisplayName;
      return Todo(_reason);
    }
    // 표시 이름이 기본값이 아니면 config appName · xcconfig DISPLAY_NAME 은
    // 이미 읽힌 값이다.
    final String appName =
        readJsonString(context.resolve(context.paths.json), 'appName') ?? '';
    final String? xcconfigDisplayName = _readXcconfigDisplayName(
      context.resolve(context.paths.xcconfig),
    );
    if (xcconfigDisplayName != appName) {
      // 빌드의 기본 이름 원본은 Android 가 JSON appName, iOS 가 xcconfig
      // DISPLAY_NAME 이다 — 둘이 다르면 영어 ARB 를 어느 쪽에 맞춰도 한 플랫폼
      // 빌드가 멈추므로 표시 이름을 다시 묻고 두 곳에 같은 값을 쓴다.
      _mode = _IdentityMode.displayNameOnly;
      _reason =
          '${context.paths.json} 의 appName("$appName")과 '
          '${context.paths.xcconfig} 의 DISPLAY_NAME("$xcconfigDisplayName")이 '
          '다릅니다';
      return Todo(_reason);
    }
    _baseName = stripFlavorSuffix(appName, context.flavor.displayNameSuffix);
    if (_baseName.trim().isEmpty) {
      // 기본 이름이 비면 영어 ARB 에 쓸 값이 없다 — 표시 이름을 다시 묻는다.
      _mode = _IdentityMode.displayNameOnly;
      _reason =
          '${context.paths.json} 의 appName("$appName")에서 flavor 접미사를 빼면 '
          '빈 이름입니다';
      return Todo(_reason);
    }
    final String? titleMismatch = _findArbTitleMismatch(context, _baseName);
    if (titleMismatch != null) {
      // 다른 flavor 의 기본 이름과 다르면 ARB 를 이 flavor 쪽으로 맞추는 순간
      // 그 flavor 빌드가 멈춘다 — 맞추지 않고 두 값을 적어 실패한다.
      final String? conflict = _findBaseNameConflict(context, _baseName);
      if (conflict != null) {
        _mode = _IdentityMode.nameConflict;
        _reason = '$conflict — $alignFlavorsGuidance';
        return Todo(_reason);
      }
      _mode = _IdentityMode.titleOnly;
      _reason = titleMismatch;
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
    // 위저드는 gen-l10n 을 부르지 않는다 — 생성 dart 는 다음 pub get · 빌드가
    // 다시 만든다.
    const arbLine =
        '($arbPath 의 appTitle 을 표시 이름에서 flavor 접미사를 뺀 값으로 바꿈 — '
        '다음 pub get · 빌드가 lib/l10n/generated/ 를 다시 만듭니다)';
    // 영어 값을 그대로 따르던 다른 언어 이름도 영어 ARB 와 함께 바뀐다 — 그런
    // 파일이 있을 때만 적는다.
    final arbCopyLines = <String>[
      if (_arbCopyPaths.isNotEmpty)
        '(${formatArbPaths(_arbCopyPaths)} 의 appTitle 도 옛 기본 이름과 같아 새 이름으로 바꿈)',
    ];
    // _applyFull 은 rename 변경에서 사용자 config appName 치환을 빼므로 CLI
    // 만 적으면 다른 flavor 의 appName 까지 바뀐다고 읽힌다 — 빼는 일을 함께
    // 적는다. 이 flavor 의 appName 은 바로 다음 줄(displayNameLines 첫 줄)이
    // 쓴다.
    const renameLine =
        'fvm dart run bin/rename.dart --org <org> --name <name> '
        '--project-prefix <prefix> --apply --yes '
        '(단 config/{dev,stg,prod}.json 의 appName 치환은 빼고 — '
        '이 flavor 의 appName 만 바로 아래 줄에서 씀)';
    final displayNameLines = <String>[
      '(${paths.json} 의 appName 을 표시 이름으로 바꿈)',
      '(${paths.xcconfig} 의 DISPLAY_NAME 을 표시 이름으로 바꿈)',
      arbLine,
      ...arbCopyLines,
    ];
    final bundleIdLines = <String>[
      for (final String path in _listTargetPaths(context, _xcconfigResidue))
        '($path 의 PRODUCT_BUNDLE_IDENTIFIER 를 앱 ID 에 맞춤)',
    ];
    return switch (_mode) {
      _IdentityMode.full => <String>[
        '(org · name 을 묻고 미리보기와 확인 표를 보인 뒤 아래와 같은 일을 합니다)',
        renameLine,
        ...displayNameLines,
      ],
      _IdentityMode.displayNameOnly => <String>[
        ...bundleIdLines,
        ...displayNameLines,
      ],
      _IdentityMode.bundleIdOnly => bundleIdLines,
      _IdentityMode.titleOnly => <String>[
        ...bundleIdLines,
        arbLine,
        ...arbCopyLines,
      ],
      _IdentityMode.unreadable ||
      _IdentityMode.inconsistent ||
      _IdentityMode.nameConflict ||
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
        _IdentityMode.titleOnly => _applyTitleOnly(context),
        _IdentityMode.unreadable ||
        _IdentityMode.inconsistent ||
        _IdentityMode.nameConflict => Failed(_reason),
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
    } on ConfigEditException catch (e) {
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
    var displayName =
        '${_findOtherFlavorBaseName(context) ?? rename.toTitleCase(name)}'
        '${flavor.displayNameSuffix}';
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
    final String? unwritableArb = _findUnwritableLocalizedArb(context);
    if (unwritableArb != null) return Failed(unwritableArb);
    final String? conflict = _findDisplayNameConflict(context, displayName);
    if (conflict != null) return Failed(conflict);

    // 사용자 config appName 은 이 단계가 직접 쓴다 — rename 은 그 값을 늘
    // toTitleCase(name) 으로 바꾸므로, 그대로 적용하면 다른 flavor 에 이미 정해진
    // 표시 이름을 덮어써 세 flavor 의 기본 이름이 갈린다(_collectRenameResidue 와
    // 같은 기준으로 뺀다). 킷 기본값인 다른 flavor 는 그 flavor 의 다음 실행이
    // 이 flavor 의 기본 이름을 제안한다.
    final Set<String> configPaths = _resolveUserConfigPaths(context);
    final changes = <rename.FileChange>[
      for (final rename.FileChange change in rename.collectChanges(
        context.projectRoot,
        org,
        name,
        projectIdPrefix: prefix,
      ))
        if (!configPaths.contains(change.filePath)) change,
    ];
    // 영어 값을 따르던 다른 언어 ARB 도 함께 고치므로 같은 검사에 넣는다.
    final List<String> dirty = await findDirtyTrackedFiles(context, <String>[
      ..._listTargetPaths(context, changes),
      ..._arbCopyPaths,
    ]);
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
    final String? unwritableArb = _findUnwritableLocalizedArb(context);
    if (unwritableArb != null) return Failed(unwritableArb);

    final String suggested = _suggestDisplayName(context);
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
    final String? conflict = _findDisplayNameConflict(context, displayName);
    if (conflict != null) return Failed(conflict);
    rename.applyChanges(_xcconfigResidue);
    _writeDisplayName(context, displayName);
    return const Applied();
  }

  /// 표시 이름을 다시 물을 때의 제안값을 고른다.
  ///
  /// 우선순위는 다른 flavor 에 정해진 기본 이름 + 이 flavor 접미사 → 이 flavor
  /// JSON `appName`(킷 기본값이 아니고, 표시 이름 규칙에 맞고, 접미사를 떼도
  /// 이름이 남을 때) → 앱 ID 이름 + 접미사다. 이미 적힌 값이 있으면 Enter 만
  /// 쳐도 그 값을 지키게 하기 위함이다.
  String _suggestDisplayName(WizardContext context) {
    final String suffix = context.flavor.displayNameSuffix;
    final String? otherBaseName = _findOtherFlavorBaseName(context);
    if (otherBaseName != null) return '$otherBaseName$suffix';
    final String? appName = _readJsonAppName(
      context.resolve(context.paths.json),
    );
    // 접미사 판정은 검사와 같이 읽은 값 그대로 한다 — 접미사뿐인 값(" Dev")을
    // 다듬어 "Dev" 로 제안하지 않는다.
    if (appName != null &&
        !_isKitAppName(appName) &&
        isValidDisplayName(appName) &&
        stripFlavorSuffix(appName, suffix).trim().isNotEmpty) {
      return appName.trim();
    }
    return '${rename.toTitleCase(_applicationId.split('.').last)}$suffix';
  }

  /// 직전 검사가 모은 사용자 xcconfig 의 킷 번들 ID 줄만 앱 ID 에 맞춘다.
  ///
  /// 값은 앱 ID 에서 정해지므로 묻지 않는다. gitignored 사용자 파일이라 깨끗함
  /// 검사도 하지 않는다.
  StepOutcome _applyBundleIdOnly() {
    rename.applyChanges(_xcconfigResidue);
    return const Applied();
  }

  /// 영어 ARB `appTitle` 을 직전 검사가 읽은 기본 이름에 맞춘다 — 묻지 않는다.
  ///
  /// 직전 검사가 모은 사용자 xcconfig 의 킷 번들 ID 도 함께 맞춘다. ARB 에
  /// `appTitle` 문자열 값이 없으면 어느 파일도 바꾸지 않고 실패한다.
  StepOutcome _applyTitleOnly(WizardContext context) {
    final String? missingTitle = _findMissingArbTitle(context);
    if (missingTitle != null) return Failed(missingTitle);
    final String? unwritableArb = _findUnwritableLocalizedArb(context);
    if (unwritableArb != null) return Failed(unwritableArb);
    rename.applyChanges(_xcconfigResidue);
    _writeArbTitle(context, _baseName);
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
    for (var attempt = 0; attempt < maxInputAttempts; attempt++) {
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
    for (var attempt = 0; attempt < maxInputAttempts; attempt++) {
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
    final suffix = flavor.suffix.isEmpty ? '' : '(${flavor.suffix})';
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
    for (final row in rows) {
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
    final rootPrefix = '${context.projectRoot}/';
    final paths = <String>[];
    for (final change in changes) {
      final isMove = change.type == rename.ChangeType.move;
      if (!isMove && !File(change.filePath).existsSync()) continue;
      final String relative = change.filePath.startsWith(rootPrefix)
          ? change.filePath.substring(rootPrefix.length)
          : change.filePath;
      if (!paths.contains(relative)) paths.add(relative);
    }
    return paths;
  }

  /// 표시 이름을 쓸 키 · 변수(JSON `appName` · xcconfig `DISPLAY_NAME` · 영어
  /// ARB `appTitle`)가 없으면 그 사유를 돌려준다 — 모두 있으면 null.
  ///
  /// 쓰기 전에 세 곳을 모두 보므로 일부 파일만 바뀐 상태를 남기지 않는다.
  String? _findMissingDisplayNameTarget(WizardContext context) {
    final FlavorPaths paths = context.paths;
    final String jsonPath = context.resolve(paths.json);
    final String xcconfigPath = context.resolve(paths.xcconfig);
    if (!File(jsonPath).existsSync() ||
        readJsonString(jsonPath, 'appName') == null) {
      return '${paths.json} 에 appName 문자열 값이 없습니다';
    }
    final String? invalidJson = findInvalidJson(jsonPath, paths.json);
    if (invalidJson != null) return invalidJson;
    if (!File(xcconfigPath).existsSync() ||
        readXcconfigValue(xcconfigPath, 'DISPLAY_NAME') == null) {
      return '${paths.xcconfig} 에 DISPLAY_NAME 이 없습니다';
    }
    return _findMissingArbTitle(context);
  }

  /// 영어 ARB `appTitle` 이 [baseName] 과 다르면 두 값을 적은 사유를 돌려준다 —
  /// 같으면 null.
  ///
  /// ARB 파일이나 `appTitle` 문자열 값이 없으면 그 사실을 사유로 돌려준다.
  static String? _findArbTitleMismatch(WizardContext context, String baseName) {
    final String? missingTitle = _findMissingArbTitle(context);
    if (missingTitle != null) return missingTitle;
    final String? arbTitle = readJsonString(
      context.resolve(arbPath),
      'appTitle',
    );
    if (arbTitle == baseName) return null;
    return '$arbPath 의 appTitle("$arbTitle")이 표시 이름의 '
        '기본 이름("$baseName")과 다릅니다';
  }

  /// 영어 ARB 에 `appTitle` 문자열 값이 없거나 ARB 가 올바른 JSON 이 아니면 그
  /// 사유를 돌려준다 — 쓸 수 있으면 null.
  static String? _findMissingArbTitle(WizardContext context) {
    final String path = context.resolve(arbPath);
    if (!File(path).existsSync()) return '$arbPath 이 없습니다';
    if (readJsonString(path, 'appTitle') == null) {
      return '$arbPath 에 appTitle 문자열 값이 없습니다';
    }
    return findInvalidJson(path, arbPath);
  }

  /// 다른 flavor 사용자 파일에 이미 정해진 표시 이름의 기본 이름을 모은다.
  ///
  /// flavor 마다 JSON `appName`(Android 원본) · xcconfig `DISPLAY_NAME`(iOS
  /// 원본)을 본다. 파일이 없거나 값이 킷 기본값(`appName` 이 킷 이름으로 시작 ·
  /// `DISPLAY_NAME` 이 example 값)이면 아직 정하지 않은 것으로 보고 건너뛴다 —
  /// 처음 dev → stg → prod 순서로 실행할 때 막히지 않게 하기 위함이다. flavor
  /// 접미사를 떼면 빈 값도 건너뛴다.
  static List<({String source, String baseName})> _collectOtherFlavorBaseNames(
    WizardContext context,
  ) {
    final entries = <({String source, String baseName})>[];
    for (final Flavor other in Flavor.values) {
      if (other == context.flavor) continue;
      final paths = FlavorPaths(other);
      final String? appName = _readJsonAppName(context.resolve(paths.json));
      if (appName != null && !_isKitAppName(appName)) {
        entries.add((
          source: '${paths.json} 의 appName("$appName")',
          baseName: stripFlavorSuffix(appName, other.displayNameSuffix),
        ));
      }
      final String? displayName = _readXcconfigDisplayName(
        context.resolve(paths.xcconfig),
      );
      final String? exampleDisplayName = _readXcconfigDisplayName(
        context.resolve(paths.xcconfigExample),
      );
      if (displayName != null && displayName != exampleDisplayName) {
        entries.add((
          source: '${paths.xcconfig} 의 DISPLAY_NAME("$displayName")',
          baseName: stripFlavorSuffix(displayName, other.displayNameSuffix),
        ));
      }
    }
    return <({String source, String baseName})>[
      for (final entry in entries)
        if (entry.baseName.trim().isNotEmpty) entry,
    ];
  }

  /// [path] xcconfig 의 `DISPLAY_NAME` 을 읽는다 — 파일이나 변수가 없으면 null.
  static String? _readXcconfigDisplayName(String path) =>
      File(path).existsSync() ? readXcconfigValue(path, 'DISPLAY_NAME') : null;

  /// [path] JSON 의 `appName` 문자열 값을 읽는다 — 파일이나 값이 없으면 null.
  static String? _readJsonAppName(String path) =>
      File(path).existsSync() ? readJsonString(path, 'appName') : null;

  /// [appName] 이 킷 기본값(킷 이름으로 시작)인지 본다.
  static bool _isKitAppName(String appName) =>
      appName.startsWith(rename.currentAppName);

  /// 다른 flavor 사용자 파일에 이미 정해진 첫 기본 이름 — 없으면 null.
  static String? _findOtherFlavorBaseName(WizardContext context) {
    final List<({String source, String baseName})> entries =
        _collectOtherFlavorBaseNames(context);
    return entries.isEmpty ? null : entries.first.baseName;
  }

  /// [baseName] 이 다른 flavor 사용자 파일의 기본 이름과 다르면 두 값을 적은
  /// 사유를 돌려준다 — 모두 같거나 대조할 값이 없으면 null.
  static String? _findBaseNameConflict(WizardContext context, String baseName) {
    for (final entry in _collectOtherFlavorBaseNames(context)) {
      if (entry.baseName != baseName) {
        return '${entry.source}의 기본 이름 "${entry.baseName}" 과 이번 기본 이름 '
            '"$baseName" 이 다릅니다 — $baseNameConflictGuidance';
      }
    }
    return null;
  }

  /// 다른 flavor 사용자 파일들끼리 기본 이름이 다르면 처음 어긋난 두 파일과
  /// 값을 적은 사유를 돌려준다 — 모두 같거나 대조할 값이 하나 이하면 null.
  static String? _findOtherFlavorsDisagreement(WizardContext context) {
    final List<({String source, String baseName})> entries =
        _collectOtherFlavorBaseNames(context);
    if (entries.isEmpty) return null;
    final first = entries.first;
    for (final entry in entries.skip(1)) {
      if (entry.baseName != first.baseName) {
        return '${first.source}의 기본 이름 "${first.baseName}" 과 '
            '${entry.source}의 기본 이름 "${entry.baseName}" 이 다릅니다';
      }
    }
    return null;
  }

  /// 표시 이름 [displayName] 의 기본 이름이 다른 flavor 와 다르면 고칠 방법까지
  /// 적은 사유를 돌려준다 — 같으면 null.
  ///
  /// 다른 flavor 들끼리도 기본 이름이 다르면 어느 표시 이름을 넣어도 한쪽과
  /// 어긋나므로, 그 두 파일을 적고 세 flavor 파일을 먼저 맞추라고 안내한다.
  static String? _findDisplayNameConflict(
    WizardContext context,
    String displayName,
  ) {
    final String? conflict = _findBaseNameConflict(
      context,
      stripFlavorSuffix(displayName, context.flavor.displayNameSuffix),
    );
    if (conflict == null) return null;
    final String? disagreement = _findOtherFlavorsDisagreement(context);
    if (disagreement != null) {
      return '$disagreement — $baseNameConflictGuidance — '
          '$alignFlavorsGuidance';
    }
    return '$conflict. 같은 기본 이름의 표시 이름으로 다시 실행하세요';
  }

  /// 표시 이름을 고른 flavor 의 사용자 JSON `appName` · xcconfig
  /// `DISPLAY_NAME` 에 쓰고, 영어 ARB `appTitle` 에 그 flavor 접미사를 뗀
  /// 기본 이름을 쓴다.
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
    _writeArbTitle(
      context,
      stripFlavorSuffix(displayName, context.flavor.displayNameSuffix),
    );
  }

  /// 영어 ARB `appTitle` 값을 [baseName] 으로 바꾼다 — 설명 객체 · 다른 키의
  /// 바이트는 그대로다.
  ///
  /// 바꾸기 직전 영어 값과 글자 그대로 같은 `appTitle` 을 가진 다른 언어 ARB 도
  /// 먼저 [baseName] 으로 바꾼다 — 영어 값을 따르던 이름이라 함께 따라가야 하고,
  /// 다른 값(그 언어로 따로 정한 이름)은 그대로 둔다. 다른 언어 ARB 를 쓸 수
  /// 있는지는 [_findUnwritableLocalizedArb] 가 미리 본다.
  static void _writeArbTitle(WizardContext context, String baseName) {
    final String englishPath = context.resolve(arbPath);
    final String? oldTitle = readJsonString(englishPath, 'appTitle');
    if (oldTitle != null) {
      for (final arb in listLocalizedArbs(context.projectRoot)) {
        if (readArbTitle(arb.absolutePath) == oldTitle) {
          replaceJsonString(arb.absolutePath, 'appTitle', baseName);
        }
      }
    }
    replaceJsonString(englishPath, 'appTitle', baseName);
  }

  /// 영어 ARB 의 지금 `appTitle` 과 같은 값을 가진 다른 언어 ARB 의 저장소 상대
  /// 경로를 파일 이름 순으로 모은다.
  ///
  /// 검사 판정 · 사유를 바꾸지 않도록 어떤 트리에서도 던지지 않는다 — 영어 ARB 나
  /// 그 `appTitle` 이 없거나 읽히지 않거나, `l10n.yaml` 로 다른 언어 ARB 를 찾지
  /// 못하면 빈 목록이다. 찾지 못한 이유는 쓰기 직전 검사가 사유로 보인다.
  static List<String> _collectArbCopyPaths(WizardContext context) {
    final String englishPath = context.resolve(arbPath);
    try {
      if (!File(englishPath).existsSync()) return const <String>[];
      final String? englishTitle = readJsonString(englishPath, 'appTitle');
      if (englishTitle == null) return const <String>[];
      return <String>[
        for (final arb in listLocalizedArbs(context.projectRoot))
          if (readArbTitle(arb.absolutePath) == englishTitle) arb.relativePath,
      ];
    } on GeneratorException {
      return const <String>[];
    } on FileSystemException {
      return const <String>[];
    } on FormatException {
      return const <String>[];
    }
  }

  /// 다른 언어 ARB 가운데 `appTitle` 을 바꿀 수 없는 첫 파일의 사유를 돌려준다
  /// — 모두 쓸 수 있으면 null.
  ///
  /// 세 실행 경로가 어떤 파일도 쓰기 전에만 부른다. 검사(check) 판정에는 끼지
  /// 않으므로 끝난 정체성은 다른 언어 ARB 가 깨져 있어도 끝난 것으로 본다.
  /// 사유 문구는 영어 ARB 검사와 같은 함수의 것이다.
  static String? _findUnwritableLocalizedArb(WizardContext context) {
    try {
      for (final arb in listLocalizedArbs(context.projectRoot)) {
        final String? invalid = findInvalidArbTitle(
          arb.absolutePath,
          arb.relativePath,
        );
        if (invalid != null) return invalid;
      }
      return null;
    } on GeneratorException catch (e) {
      return '언어별 ARB 목록을 읽지 못했습니다 — ${e.message}';
    }
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
    const String scriptPath = ConfigureStep.scriptPath;
    final script = File(context.resolve(scriptPath));
    if (!script.existsSync()) return '$scriptPath 이 없습니다';
    final String content = script.readAsStringSync();
    final int nameStart = applicationId.lastIndexOf('.');
    // 점이 없는 앱 ID 는 org 가 없다 — 그때는 앱 ID 를 그대로 기대한다.
    final String org = nameStart < 0
        ? ''
        : applicationId.substring(0, nameStart);
    final String name = applicationId.substring(nameStart + 1);
    final expectedIos = nameStart < 0
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
  /// 늘 등록하므로 버린다(표시 이름은 [_describeDefaultDisplayName] 가 따로 본다).
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
    final Set<String> configPaths = _resolveUserConfigPaths(context);
    final xcconfigPaths = <String>{
      for (final String fileName in rename.userXcconfigFileNames)
        context.resolve('ios/Flutter/$fileName'),
    };
    final String ownXcconfigPath = context.resolve(context.paths.xcconfig);
    final isDevFlavor = context.flavor == Flavor.dev;
    final tracked = <rename.FileChange>[];
    final userXcconfig = <rename.FileChange>[];
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

  /// rename 이 `appName` 을 바꾸는 사용자 config 파일(`config/{dev,stg,prod}.json`)
  /// 의 절대 경로 집합을 만든다.
  ///
  /// 사용자 config `appName` 은 표시 이름이라 이 단계가 고른 flavor 것만 직접
  /// 쓴다 — rename 변경 목록에서 이 경로의 변경은 검사 · 적용 모두 뺀다.
  static Set<String> _resolveUserConfigPaths(WizardContext context) => <String>{
    for (final String fileName in rename.userConfigFileNames)
      context.resolve('config/$fileName'),
  };

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

  /// 고른 flavor 의 표시 이름 가운데 킷 기본값(`appName` 이 킷 이름으로 시작 ·
  /// `DISPLAY_NAME` 이 example 값)이거나 없는 곳을 적은 사유를 돌려준다 — 둘 다
  /// 정해졌으면 null.
  ///
  /// 사유에는 실제로 기본값이거나 없는 파일만 저장소 상대 경로로 적는다.
  String? _describeDefaultDisplayName(WizardContext context) {
    final FlavorPaths paths = context.paths;
    final String? appName = _readJsonAppName(context.resolve(paths.json));
    final String? displayName = _readXcconfigDisplayName(
      context.resolve(paths.xcconfig),
    );
    final String? exampleDisplayName = _readXcconfigDisplayName(
      context.resolve(paths.xcconfigExample),
    );
    final jsonTarget = '${paths.json} 의 appName';
    final xcconfigTarget = '${paths.xcconfig} 의 DISPLAY_NAME';
    final missing = <String>[
      if (appName == null) jsonTarget,
      if (displayName == null) xcconfigTarget,
    ];
    final kitDefault = <String>[
      if (appName != null && _isKitAppName(appName)) jsonTarget,
      if (displayName != null && displayName == exampleDisplayName)
        xcconfigTarget,
    ];
    final parts = <String>[
      if (kitDefault.isNotEmpty) '${kitDefault.join(' · ')} 이 킷 기본값입니다',
      if (missing.isNotEmpty) '${missing.join(' · ')} 이 없습니다',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 직전 검사의 판정.
enum _IdentityMode {
  /// 앱 ID 가 킷 기본값 — org · name 부터 진행.
  full,

  /// 앱 ID 는 바뀌었고 표시 이름이 기본값이거나 JSON `appName` 과 xcconfig
  /// `DISPLAY_NAME` 이 다름 — 표시 이름을 다시 묻고, 사용자 xcconfig 의 킷 번들
  /// ID 가 남았으면 함께 맞춘다.
  displayNameOnly,

  /// 앱 ID · 표시 이름은 바뀌었고 사용자 xcconfig 의 번들 ID 만 킷 값.
  bundleIdOnly,

  /// 앱 ID · 표시 이름은 정해졌고 영어 ARB `appTitle` 만 표시 이름의 기본 이름과
  /// 다름 — 묻지 않고 ARB 를 맞추고, 사용자 xcconfig 의 킷 번들 ID 가 남았으면
  /// 함께 맞춘다.
  titleOnly,

  /// Gradle 파일에서 앱 ID 를 읽지 못함.
  unreadable,

  /// Gradle 앱 ID 와 configure 스크립트 상수 · 추적 파일이 다름 — 이름 바꾸기가
  /// 중간에 끊김.
  inconsistent,

  /// 영어 ARB `appTitle` 을 이 flavor 의 기본 이름으로 맞춰야 하는데 다른 flavor
  /// 사용자 파일의 기본 이름과 다름 — 맞추면 그 flavor 빌드가 멈추므로 실패.
  nameConflict,

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
