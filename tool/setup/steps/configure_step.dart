import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../firebase_app_files.dart';
import '../flavor.dart';
import '../git_tree.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'identity_step.dart';

/// 앱 등록 · 설정 파일 단계 — Firebase 에 고른 flavor 의 iOS · Android 앱을
/// 등록하고 그 flavor 의 설정 파일 3개를 만든다.
///
/// 실행은 저장소의 configure 스크립트에 flavor 이름을 넘겨 그대로 부르고, 종료
/// 코드 0 과 표준 출력의 마지막 줄([buildCompleteLine])로만 성공을 판정한다. 검사는 설정 파일 3개가 지금
/// 프로젝트 · 앱 정체성과 맞고 두 앱 ID 가 프로젝트 앱 목록에 있는지다. 파일의
/// 키 · 앱 ID 값은 화면 · 기록에 쓰지 않는다.
///
/// 스크립트가 함께 건드리는 [pbxprojPath] · [firebaseJsonPath] 는 실행 전에
/// 미커밋 변경을 본다. `firebase.json` 변경이나 앞 단계(앱 정체성)가 남긴 번들 ID
/// 줄 밖의 pbxproj 변경이 있으면 멈추고, 실행 뒤에는 두 파일이 실행 직전 바이트와
/// 같은지 본다. 위저드는 두 파일을 직접 고치거나 되돌리지 않는다.
///
/// [requiresGoogleClient] 면(Google 로그인을 켠 flavor) iOS 설정 파일에 Google
/// 로그인 정보(`CLIENT_ID`)가 있어야 끝난 것으로 본다 — Google 을 켜기 전에 받은
/// 파일이면 스크립트를 다시 실행해 새로 받고, 다시 받아도 없으면 실패로 끝낸다
/// (같은 실행을 스스로 되풀이하지 않는다).
final class ConfigureStep implements Step {
  /// 앱 등록 · 설정 파일 단계를 만든다.
  ///
  /// [requiresGoogleClient] 면 Google 단계에 의존하고 iOS 설정 파일의 `CLIENT_ID`
  /// 를 검사 술어에 더한다.
  ConfigureStep({this.requiresGoogleClient = false});

  /// Google 로그인을 켠 flavor 면 true — iOS 설정 파일에 `CLIENT_ID` 가 있어야 한다.
  final bool requiresGoogleClient;

  /// Google 로그인을 켠 뒤의 설정 파일이 아닐 때의 검사 사유.
  static const String missingGoogleClientReason =
      'Google 로그인을 켠 뒤의 iOS 설정 파일이 아닙니다 — 다시 받습니다';

  /// 단계 제목.
  static const String stepTitle = '앱 등록 · 설정 파일';

  /// 실행하는 configure 스크립트(저장소 상대 경로).
  static const String scriptPath = 'scripts/firebase-configure.sh';

  /// dev 실행에서 스크립트 성공 시 표준 출력의 마지막 줄.
  static final String completeLine = buildCompleteLine(Flavor.dev);

  /// [flavor] 실행에서 스크립트 성공 시 표준 출력의 마지막 줄.
  static String buildCompleteLine(Flavor flavor) =>
      '✓ Firebase configure complete for ${flavor.name}';

  /// 스크립트가 함께 바꿨다가 되돌리는 Xcode 프로젝트 파일.
  static const String pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

  /// 스크립트가 함께 바꿨다가 되돌리는 Firebase 설정 파일.
  static const String firebaseJsonPath = 'firebase.json';

  /// 앞 단계가 고칠 수 있는 pbxproj 줄 — group 1 = 번들 ID.
  static final RegExp bundleIdLinePattern = RegExp(
    r'^\s*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);$',
  );

  /// [projectId] 의 Firebase 앱 목록을 읽는 명령 — 출력에 앱 ID 가 실린다.
  static Command buildAppsListCommand(String projectId) => Command(
    'firebase',
    <String>['apps:list', '--json', '--project', projectId],
    isOutputSensitive: true,
  );

  /// 저장소 루트 [workingDirectory] 에서 [flavor] 의 configure 스크립트를
  /// 실행하는 명령.
  static Command buildConfigureCommand({
    Flavor flavor = Flavor.dev,
    String? workingDirectory,
  }) => Command('bash', <String>[
    scriptPath,
    flavor.name,
  ], workingDirectory: workingDirectory);

  /// pbxproj 의 원문 줄 diff 를 읽는 명령.
  ///
  /// 사용자 git 설정의 외부 diff 도구 · textconv · binary 속성과 관계없이 바뀐
  /// 줄을 그대로 받는다.
  static Command buildPbxprojDiffCommand({String? workingDirectory}) =>
      Command('git', const <String>[
        'diff',
        '--no-color',
        '--no-ext-diff',
        '--no-textconv',
        '--text',
        '--unified=0',
        '--',
        pbxprojPath,
      ], workingDirectory: workingDirectory);

  /// pbxproj [diff] 가 앞 단계(앱 정체성)가 남긴 번들 ID 변경뿐인지 판정한다.
  ///
  /// 바뀐 줄(첫 `@@` 앞의 `---` · `+++` 머리를 뺀 `+` · `-` 줄)이 1개 이상이고
  /// 그 가운데 `+` 줄이 1개 이상이며, 모든 바뀐 줄이 번들 ID 줄이고 `+` 줄의 값이
  /// 모두 [bundleBase] · `<bundleBase>` + dev 접미사 · `<bundleBase>.RunnerTests`
  /// 가운데 하나일 때만 true 다. 바뀐 줄이 없는 diff(모드만 바뀜 등)는 false 다.
  ///
  /// pbxproj 의 번들 ID 줄은 dev 빌드 설정 · 테스트 대상 · 접미사 없는 값뿐이라
  /// 어느 flavor 실행이든 허용 집합은 같다.
  static bool isIdentityOnlyDiff(String diff, String bundleBase) {
    final allowed = <String>{
      bundleBase,
      '$bundleBase${Flavor.dev.suffix}',
      '$bundleBase.RunnerTests',
    };
    var isInHunk = false;
    var changed = 0;
    var added = 0;
    for (final String line in const LineSplitter().convert(diff)) {
      if (line.startsWith('@@')) {
        isInHunk = true;
        continue;
      }
      if (!isInHunk) continue;
      if (!line.startsWith('+') && !line.startsWith('-')) continue;
      final RegExpMatch? match = bundleIdLinePattern.firstMatch(
        line.substring(1),
      );
      if (match == null) return false;
      changed++;
      if (line.startsWith('+')) {
        if (!allowed.contains(match.group(1)!.trim())) return false;
        added++;
      }
    }
    return changed >= 1 && added >= 1;
  }

  _ConfigureMode _mode = _ConfigureMode.unreadable;
  String _reason = '';
  CommandResult? _failedResult;

  @override
  String get id => 'configure';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => <String>[
    'firebase_project',
    'identity',
    'tools',
    // CLIENT_ID 술어는 Google 을 켠 뒤에만 뜻이 있다 — 켜기 전에 돌면 헛돈다.
    if (requiresGoogleClient) 'google',
  ];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _ConfigureMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    final String? bundleId = readBundleId(context.projectRoot, context.flavor);
    if (bundleId == null) {
      return _mark(
        _ConfigureMode.unreadable,
        '${context.paths.xcconfig} 에서 번들 ID 를 읽지 못했습니다',
      );
    }
    final String? packageName = readAndroidPackage(
      context.projectRoot,
      context.flavor,
    );
    if (packageName == null) {
      return _mark(
        _ConfigureMode.unreadable,
        '${IdentityStep.gradlePath} 에서 applicationId 를 읽지 못했습니다',
      );
    }

    final files = FirebaseAppFiles.read(
      context.projectRoot,
      flavor: context.flavor,
    );
    final String? fileProblem = _findFileProblem(
      files,
      projectId,
      bundleId,
      packageName,
    );
    if (fileProblem != null) return _mark(_ConfigureMode.run, fileProblem);
    if (requiresGoogleClient && files.iosClientId == null) {
      return _mark(_ConfigureMode.run, missingGoogleClientReason);
    }

    final CommandResult result = await context.runner.capture(
      buildAppsListCommand(projectId),
    );
    final Set<String>? appIds = _parseAppIds(result);
    if (appIds == null) {
      // 민감 출력 명령이라 표준 출력(앱 ID 목록)은 떼고 오류 원문만 보인다.
      return _mark(
        _ConfigureMode.listFailed,
        '$projectId 의 Firebase 앱 목록을 읽지 못했습니다',
        result: result.withoutStdout(),
      );
    }
    if (!appIds.contains(files.iosAppId) ||
        !appIds.contains(files.androidAppIdFor(packageName))) {
      return _mark(_ConfigureMode.run, '설정 파일의 앱이 프로젝트에 등록돼 있지 않습니다');
    }
    _mode = _ConfigureMode.done;
    return const Done('iOS · Android 앱 등록 · 설정 파일 3개 확인');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _ConfigureMode.run => <String>[
      '(실행 전에 $pbxprojPath · $firebaseJsonPath 의 커밋하지 않은 변경을 봅니다 — 앱 정체성 단계가 바꾼 번들 ID 줄만 있으면 그대로 진행합니다)',
      buildConfigureCommand(flavor: context.flavor).render(),
      '(FlutterFire CLI 가 Firebase 에 iOS · Android 앱을 등록하고 설정 파일 3개를 만듭니다 — 생성 파일은 skip-worktree 로 커밋 대상에서 빠집니다)',
    ],
    _ConfigureMode.listFailed => <String>['(명령의 오류 원문을 보입니다)'],
    _ConfigureMode.unreadable || _ConfigureMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    try {
      return switch (_mode) {
        _ConfigureMode.run => await _applyConfigure(context),
        _ConfigureMode.listFailed => Failed(_reason, result: _failedResult),
        _ConfigureMode.unreadable => Failed(_reason),
        _ConfigureMode.done => const Applied(),
      };
    } on GitTreeException catch (e) {
      return Failed(e.message, result: e.result);
    } on FileSystemException catch (e) {
      return Failed('파일을 읽지 못했습니다 — $e');
    }
  }

  /// 깨끗함 검사 → 스크립트 실행 → 마지막 줄 계약 → 내용 같음 검사를 한다.
  Future<StepOutcome> _applyConfigure(WizardContext context) async {
    final List<String> dirty = await findDirtyTrackedFiles(context, <String>[
      pbxprojPath,
      firebaseJsonPath,
    ]);
    if (dirty.contains(firebaseJsonPath)) {
      return _failDirty(dirty);
    }
    if (dirty.contains(pbxprojPath)) {
      final StepOutcome? blocked = await _checkPbxprojDiff(context, dirty);
      if (blocked != null) return blocked;
    }

    final Map<String, List<int>?> before = _readBytes(context);
    final CommandResult result = await context.runner.stream(
      buildConfigureCommand(
        flavor: context.flavor,
        workingDirectory: context.projectRoot,
      ),
    );
    final Map<String, List<int>?> after = _readBytes(context);

    final notRestored = <String>[
      for (final String path in before.keys)
        if (!_isSameBytes(before[path], after[path])) path,
    ];
    if (notRestored.isNotEmpty) {
      return Failed(
        <String>[
          for (final String path in notRestored)
            'configure 스크립트가 $path 을 실행 전 내용으로 되돌리지 못했습니다.',
          for (final String path in notRestored)
            '    바뀐 내용 확인: git diff -- $path',
        ].join('\n'),
        result: result,
      );
    }
    if (!result.isSuccess) {
      return Failed(
        'configure 스크립트가 실패했습니다 (종료 코드 ${result.exitCode})',
        result: result,
      );
    }
    final String completeLine = buildCompleteLine(context.flavor);
    if (findLastOutputLine(result.stdout) != completeLine) {
      return Failed(
        'configure 스크립트의 마지막 줄이 완료 줄($completeLine)이 아닙니다',
        result: result,
      );
    }
    if (requiresGoogleClient &&
        FirebaseAppFiles.read(
              context.projectRoot,
              flavor: context.flavor,
            ).iosClientId ==
            null) {
      return Failed(
        '다시 받은 iOS 설정 파일에도 Google 로그인 정보(CLIENT_ID)가 없습니다 — '
        '${formatManualReference(providersManualHeading)}',
      );
    }
    return const Applied();
  }

  /// pbxproj 변경이 앞 단계 모양인지 본다 — 아니면 실패 결과, 맞으면 null.
  ///
  /// 기준 값([isIdentityOnlyDiff] 의 `bundleBase`)은 이번 flavor 의 번들 ID 에서
  /// 그 flavor 접미사를 뗀 값이다(prod 는 접미사가 없어 그대로).
  Future<StepOutcome?> _checkPbxprojDiff(
    WizardContext context,
    List<String> dirty,
  ) async {
    final CommandResult diff = await context.runner.capture(
      buildPbxprojDiffCommand(workingDirectory: context.projectRoot),
    );
    if (!diff.isSuccess) {
      return Failed('$pbxprojPath 의 변경을 읽지 못했습니다', result: diff);
    }
    final String? bundleId = readBundleId(context.projectRoot, context.flavor);
    if (bundleId == null) {
      return Failed('${context.paths.xcconfig} 에서 번들 ID 를 읽지 못했습니다');
    }
    final String suffix = context.flavor.suffix;
    final String bundleBase = suffix.isNotEmpty && bundleId.endsWith(suffix)
        ? bundleId.substring(0, bundleId.length - suffix.length)
        : bundleId;
    if (isIdentityOnlyDiff(diff.stdout, bundleBase)) return null;
    return _failDirty(dirty);
  }

  /// 고칠 파일의 미커밋 변경을 이름과 함께 알리는 실패 결과.
  static Failed _failDirty(List<String> dirty) => Failed(
    '앱 등록이 고칠 파일에 커밋하지 않은 변경이 있습니다 — '
    '${IdentityStep.dirtyTreeGuidance}\n'
    '${dirty.map((String path) => '    $path').join('\n')}',
  );

  /// 설정 파일 3개가 지금 프로젝트 · 앱 정체성과 맞지 않는 첫 이유를 찾는다.
  ///
  /// 모두 맞으면 null. 이유에는 파일의 값을 넣지 않는다.
  static String? _findFileProblem(
    FirebaseAppFiles files,
    String projectId,
    String bundleId,
    String packageName,
  ) {
    if (files.isOptionsPlaceholder) {
      return 'Dart 설정 파일이 저장소 자리표시입니다 — 앱이 아직 등록되지 않았습니다';
    }
    if (files.optionsProjectId != projectId) {
      return 'Dart 설정 파일의 프로젝트가 config 와 다릅니다 — 다른 프로젝트의 파일입니다';
    }
    final String? iosProjectId = files.iosProjectId;
    if (iosProjectId == null) return 'iOS 설정 파일이 없거나 읽지 못했습니다';
    if (iosProjectId != projectId) {
      return 'iOS 설정 파일의 프로젝트가 config 와 다릅니다 — 다른 프로젝트의 파일입니다';
    }
    if (files.iosBundleId != bundleId) {
      return 'iOS 설정 파일의 번들 ID 가 앱 정체성과 다릅니다';
    }
    if (files.iosAppId == null) return 'iOS 설정 파일에서 앱 ID 를 읽지 못했습니다';
    final String? androidProjectId = files.androidProjectId;
    if (androidProjectId == null) {
      return 'Android 설정 파일이 없거나 읽지 못했습니다';
    }
    if (androidProjectId != projectId) {
      return 'Android 설정 파일의 프로젝트가 config 와 다릅니다 — 다른 프로젝트의 파일입니다';
    }
    if (files.androidAppIdFor(packageName) == null) {
      return 'Android 설정 파일에 앱 정체성의 패키지가 없습니다';
    }
    return null;
  }

  /// `firebase apps:list --json` 결과의 앱 ID 를 모은다 — 실패 · 모양이 다르면 null.
  static Set<String>? _parseAppIds(CommandResult result) {
    if (!result.isSuccess) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? items = decoded['result'];
    if (items is! List<Object?>) return null;
    return <String>{
      for (final Object? item in items)
        if (item is Map<String, Object?> && item['appId'] is String)
          item['appId']! as String,
    };
  }

  /// 스크립트가 함께 건드리는 두 파일의 바이트를 읽는다 — 없으면 null.
  static Map<String, List<int>?> _readBytes(WizardContext context) =>
      <String, List<int>?>{
        for (final String path in <String>[pbxprojPath, firebaseJsonPath])
          path: File(context.resolve(path)).existsSync()
              ? File(context.resolve(path)).readAsBytesSync()
              : null,
      };

  /// 두 바이트 목록이 같으면 true(둘 다 없음 포함).
  static bool _isSameBytes(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(
    _ConfigureMode mode,
    String reason, {
    CommandResult? result,
  }) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _ConfigureMode {
  /// 앱 등록 · 설정 파일 만들기가 필요하다 — configure 스크립트를 실행한다.
  run,

  /// 앱 목록을 읽지 못했다.
  listFailed,

  /// 프로젝트 ID · 앱 정체성을 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
