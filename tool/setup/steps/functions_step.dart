import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../secret_names.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'firestore_step.dart';
import 'user_files_step.dart';

/// Cloud Functions 단계 — 의존성을 설치하고, 코드가 선언한 secret 가운데 없는
/// 것만 자리표시 값으로 만든 뒤 저장소의 배포 스크립트로 함수를 배포한다.
///
/// 검사는 의존성 설치 표시 파일([modulesMarkerPath]) · 선언된 secret 전부 존재 ·
/// [manifestPath] 의 공통 함수 전부 배포 순서로 본다. 의존성 · secret 이 빠졌으면
/// 함수 목록을 읽지 않는다. 배포는 [deployScriptPath] 를 프로세스로 실행하고
/// 종료 코드 0 과 표준 출력의 마지막 줄([deployOkPattern])로만 성공을 판정한다 —
/// 배포할 함수 목록은 위저드가 따로 계산하지 않는다.
///
/// secret 값은 인자에 싣지 않고 표준 입력으로만 넘기며, 이미 있는 secret 의 값은
/// 읽거나 바꾸지 않는다. 프로젝트 ID · 리전은 매번 `config/dev.json` 에서 읽는다.
final class FunctionsStep implements Step {
  /// Cloud Functions 단계를 만든다.
  FunctionsStep();

  /// 단계 제목.
  static const String stepTitle = 'Cloud Functions 배포';

  /// 실행하는 배포 스크립트(저장소 상대 경로).
  static const String deployScriptPath = 'scripts/deploy_functions.sh';

  /// 배포 스크립트에 넘기는 flavor.
  static const String flavor = 'dev';

  /// 배포 대상 함수 목록 파일(저장소 상대 경로) — 배포 스크립트도 이 파일을 읽는다.
  static const String manifestPath = 'scripts/functions_manifest.json';

  /// 함수 목록 파일에서 공통 함수 배열의 키.
  static const String manifestCommonKey = 'common';

  /// 의존성 설치가 끝나면 생기는 표시 파일(저장소 상대 경로).
  static const String modulesMarkerPath =
      'functions/node_modules/.modules.yaml';

  /// 없는 secret 을 만들 때 표준 입력으로 넘기는 자리표시 값.
  static const String secretPlaceholder = 'unset';

  /// 배포 스크립트 성공 시 표준 출력의 마지막 줄.
  static final RegExp deployOkPattern = RegExp(
    r'^DEPLOY OK dev functions=[0-9]+ batches=[0-9]+$',
  );

  /// 저장소 루트 [workingDirectory] 에서 Functions 의존성을 설치하는 명령 —
  /// 커밋된 lockfile 그대로 설치한다.
  static Command buildInstallCommand({String? workingDirectory}) => Command(
    'pnpm',
    const <String>['-C', 'functions', 'install', '--frozen-lockfile'],
    workingDirectory: workingDirectory,
  );

  /// [projectId] 의 Secret Manager secret 이름 목록을 읽는 명령.
  ///
  /// 줄마다 전체 자원 이름(`projects/<번호>/secrets/<이름>`)이 나온다 — 값은 읽지
  /// 않는다.
  static Command buildSecretsListCommand(String projectId) => Command(
    'gcloud',
    <String>['secrets', 'list', '--project', projectId, '--format=value(name)'],
  );

  /// [projectId] 에 [name] secret 을 자리표시 값으로 만드는 명령.
  ///
  /// 값은 표준 입력으로만 넘기고, 화면 · 기록에는 매뉴얼과 같은 `printf … |`
  /// 표시형을 보인다. 출력은 민감 출력으로 실행한다.
  static Command buildSecretSetCommand(String name, String projectId) =>
      Command(
        'firebase',
        <String>[
          'functions:secrets:set',
          name,
          '--project',
          projectId,
          '--data-file',
          '-',
        ],
        stdinText: secretPlaceholder,
        display:
            "printf '$secretPlaceholder' | firebase functions:secrets:set "
            '$name --project $projectId --data-file -',
        isOutputSensitive: true,
      );

  /// [projectId] 에 배포된 함수 목록을 JSON 으로 읽는 명령.
  static Command buildFunctionsListCommand(String projectId) => Command(
    'firebase',
    <String>['functions:list', '--json', '--project', projectId],
  );

  /// 저장소 루트 [workingDirectory] 에서 배포 스크립트를 실행 모드로 부르는 명령.
  static Command buildDeployCommand({String? workingDirectory}) => Command(
    'bash',
    const <String>[deployScriptPath, flavor, '--apply'],
    workingDirectory: workingDirectory,
  );

  /// [projectRoot] 의 함수 목록 파일에서 공통 함수 이름을 읽는다.
  ///
  /// 파일이 없거나 JSON · 모양이 다르면 null.
  static List<String>? readCommonFunctions(String projectRoot) {
    final File file = File('$projectRoot/$manifestPath');
    if (!file.existsSync()) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? common = decoded[manifestCommonKey];
    if (common is! List<Object?>) return null;
    final List<String> names = <String>[
      for (final Object? name in common)
        if (name is String && name.isNotEmpty) name,
    ];
    return names.length == common.length ? names : null;
  }

  _FunctionsMode _mode = _FunctionsMode.unreadable;
  String _reason = '';
  String _projectId = '';
  bool _isModuleMissing = false;
  List<String> _missingSecrets = const <String>[];
  CommandResult? _failedResult;

  @override
  String get id => 'functions';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>[
    'configure',
    'apis',
    'firestore',
  ];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _FunctionsMode.unreadable,
        '${UserFilesStep.jsonUserPath} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    final String? region = _readRegion(context);
    if (region == null) {
      return _mark(
        _FunctionsMode.unreadable,
        '${UserFilesStep.jsonUserPath} 에서 Functions 리전'
        '(${FirestoreStep.functionsRegionKey})을 읽지 못했습니다',
      );
    }
    final List<String>? common = readCommonFunctions(context.projectRoot);
    if (common == null || common.isEmpty) {
      return _mark(
        _FunctionsMode.unreadable,
        '$manifestPath 에서 공통 함수 목록을 읽지 못했습니다',
      );
    }
    final List<String> declared;
    try {
      declared = extractDeclaredSecretNames(context.projectRoot);
    } on FileSystemException {
      return _mark(
        _FunctionsMode.unreadable,
        '$functionsSourceDirectory 의 secret 선언을 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    _isModuleMissing = !File(context.resolve(modulesMarkerPath)).existsSync();

    final CommandResult listed = await context.runner.capture(
      buildSecretsListCommand(projectId),
    );
    if (!listed.isSuccess) {
      return _mark(
        _FunctionsMode.listFailed,
        '$projectId 의 secret 목록을 읽지 못했습니다',
        result: listed,
      );
    }
    final Set<String> existing = parseSecretNames(listed.stdout);
    _missingSecrets = <String>[
      for (final String name in declared)
        if (!existing.contains(name)) name,
    ];
    if (_isModuleMissing || _missingSecrets.isNotEmpty) {
      return _mark(
        _FunctionsMode.deploy,
        <String>[
          if (_isModuleMissing) 'Functions 의존성이 설치되지 않았습니다',
          if (_missingSecrets.isNotEmpty)
            'secret ${_missingSecrets.length}개가 없습니다 '
                '(${_missingSecrets.join(' · ')})',
        ].join(' · '),
      );
    }

    final CommandResult functions = await context.runner.capture(
      buildFunctionsListCommand(projectId),
    );
    final Map<String, String?>? deployed = parseDeployedFunctions(
      functions,
      region,
    );
    if (deployed == null) {
      return _mark(
        _FunctionsMode.deploy,
        '배포된 함수 목록을 읽지 못했습니다 — ${_describeFirstLine(functions)}',
      );
    }
    final List<String> notDeployed = <String>[
      for (final String name in common)
        if (!deployed.containsKey(name)) name,
    ];
    if (notDeployed.isNotEmpty) {
      return _mark(
        _FunctionsMode.deploy,
        '배포되지 않은 함수가 있습니다 (${notDeployed.join(' · ')})',
      );
    }
    _mode = _FunctionsMode.done;
    return Done(
      '의존성 · secret ${declared.length}개 · 공통 함수 ${common.length}개 배포 확인',
    );
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _FunctionsMode.deploy => <String>[
      if (_isModuleMissing) buildInstallCommand().render(),
      if (_missingSecrets.isNotEmpty)
        '(없는 secret 만 자리표시 값 $secretPlaceholder 으로 만듭니다 — 이미 있는 '
            'secret 의 값은 읽거나 바꾸지 않습니다)',
      for (final String name in _missingSecrets)
        buildSecretSetCommand(name, _projectId).render(),
      buildDeployCommand().render(),
      '(배포 대상은 $manifestPath 의 공통 함수와 ${UserFilesStep.jsonUserPath} 의 '
          'enabledAuthProviders 가 켠 로그인 수단의 함수입니다)',
    ],
    _FunctionsMode.listFailed => <String>['(명령 원문을 보입니다)'],
    _FunctionsMode.unreadable || _FunctionsMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _FunctionsMode.deploy => await _applyDeploy(context),
      _FunctionsMode.listFailed => Failed(_reason, result: _failedResult),
      _FunctionsMode.unreadable => Failed(_reason),
      _FunctionsMode.done => const Applied(),
    };
  }

  /// 의존성 설치 → 없는 secret 만들기 → 배포 스크립트 실행 → 마지막 줄 판정.
  Future<StepOutcome> _applyDeploy(WizardContext context) async {
    if (_isModuleMissing) {
      final CommandResult installed = await context.runner.stream(
        buildInstallCommand(workingDirectory: context.projectRoot),
      );
      if (!installed.isSuccess) {
        return Failed(
          'Functions 의존성을 설치하지 못했습니다 (종료 코드 ${installed.exitCode})',
          result: installed,
        );
      }
    }
    for (final String name in _missingSecrets) {
      final Command command = buildSecretSetCommand(name, _projectId);
      context.terminal.writeCommand(command.render());
      final CommandResult created = await context.runner.capture(command);
      if (!created.isSuccess) {
        // 민감 출력이라 표준 출력은 버리고 오류 원문만 보인다.
        return Failed(
          'secret $name 을 만들지 못했습니다 (종료 코드 ${created.exitCode})',
          result: CommandResult(created.exitCode, '', created.stderr),
        );
      }
    }
    final CommandResult deployed = await context.runner.stream(
      buildDeployCommand(workingDirectory: context.projectRoot),
    );
    return judgeDeployResult(deployed);
  }

  /// 배포 스크립트 결과를 종료 코드와 마지막 줄 계약으로 판정한다.
  static StepOutcome judgeDeployResult(CommandResult result) {
    if (!result.isSuccess) {
      return Failed(
        'Functions 배포 스크립트가 실패했습니다 (종료 코드 ${result.exitCode})',
        result: result,
      );
    }
    final String? lastLine = _findLastLine(result.stdout);
    if (lastLine == null || !deployOkPattern.hasMatch(lastLine)) {
      return Failed(
        '배포 스크립트의 마지막 줄이 배포 완료 줄'
        '(DEPLOY OK dev functions=<개수> batches=<묶음 수>)이 아닙니다',
        result: result,
      );
    }
    return const Applied();
  }

  /// `gcloud secrets list --format=value(name)` 출력에서 secret 이름을 모은다.
  ///
  /// 줄마다 마지막 `/` 뒤를 이름으로 쓴다(짧은 이름 줄도 그대로 받는다).
  static Set<String> parseSecretNames(String stdout) => <String>{
    for (final String line in const LineSplitter().convert(stdout))
      if (line.trim().isNotEmpty) line.trim().split('/').last,
  };

  /// `firebase functions:list --json` 결과에서 [region] 의 함수를 모은다.
  ///
  /// 함수 이름 → Cloud Run 서비스 이름(`runServiceId`, 없으면 null). 실패 · 모양이
  /// 다르면 null.
  static Map<String, String?>? parseDeployedFunctions(
    CommandResult result,
    String region,
  ) {
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
    return <String, String?>{
      for (final Object? item in items)
        if (item is Map<String, Object?> &&
            item['id'] is String &&
            item['region'] == region)
          item['id']! as String: item['runServiceId'] is String
              ? item['runServiceId']! as String
              : null,
    };
  }

  /// config 의 Functions 리전을 읽는다 — 없거나 빈 값이면 null.
  static String? _readRegion(WizardContext context) {
    final String path = context.resolve(UserFilesStep.jsonUserPath);
    if (!File(path).existsSync()) return null;
    final String? value = readJsonString(
      path,
      FirestoreStep.functionsRegionKey,
    )?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// 표준 출력의 마지막 빈 줄 아닌 줄(앞뒤 공백 제외)을 찾는다 — 없으면 null.
  static String? _findLastLine(String stdout) {
    final List<String> lines = const LineSplitter()
        .convert(stdout)
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    return lines.isEmpty ? null : lines.last.trim();
  }

  /// 명령 결과의 첫 빈 줄 아닌 줄(오류 출력 먼저)을 찾는다 — 없으면 종료 코드.
  static String _describeFirstLine(CommandResult result) {
    for (final String text in <String>[result.stderr, result.stdout]) {
      for (final String line in const LineSplitter().convert(text)) {
        if (line.trim().isNotEmpty) return line.trim();
      }
    }
    return '종료 코드 ${result.exitCode}';
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(
    _FunctionsMode mode,
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
enum _FunctionsMode {
  /// 의존성 설치 · secret 만들기 · 배포가 필요하다.
  deploy,

  /// secret 목록을 읽지 못했다.
  listFailed,

  /// 프로젝트 ID · 리전 · 함수 목록 파일 · secret 선언을 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
