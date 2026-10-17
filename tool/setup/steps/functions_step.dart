import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../secret_names.dart';
import '../secret_store.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'firestore_step.dart';
import 'user_files_step.dart';

/// 배포된 함수가 쓰는 secret 하나 — Secret Manager 이름과 배포 때 고정된 버전.
typedef DeployedSecret = ({String secret, String version});

/// Cloud Functions 단계 — 의존성을 설치하고, 코드가 선언한 secret 가운데 없는
/// 것만 자리표시 값으로 만든 뒤 저장소의 배포 스크립트로 함수를 배포하고, 앱이
/// 함수를 부를 수 있게 공개 호출(invoker)까지 확인한다.
///
/// 검사는 의존성 설치 표시 파일([modulesMarkerPath]) · 선언된 secret 전부 존재 ·
/// [manifestPath] 의 공통 함수와 켠 로그인 수단([enabledProviders])의 함수 전부
/// 배포 · 그 함수들의 Cloud Run 서비스 IAM 에
/// [invokerRole] + [invokerMember] 순서로 본다. 의존성 · secret 이 빠졌으면 함수
/// 목록을, 함수가 빠졌으면 IAM 을 읽지 않는다. 켠 로그인 수단의 함수는 공개 호출
/// 전에 배포 때 고정된 secret 버전을 Secret Manager 최신 버전과 비교해, 옛 버전을
/// 쓰는 함수가 있으면 다시 배포한다(배포가 최신 버전을 잡는다) — 최신 버전을 읽지
/// 못하면 끝남으로 보지 않는다. 배포는 [deployScriptPath] 를
/// 프로세스로 실행하고 종료 코드 0 과 표준 출력의 마지막 줄([deployOkPattern])로만
/// 성공을 판정한다 — 배포할 함수 목록은 위저드가 따로 계산하지 않는다.
///
/// 조직 정책이 공개 호출을 막으면([invokerBlockedMarker] · [isOrgPolicyRejection])
/// 원문 뒤에 [orgPolicyGuidance] 를 보이고 IAM 정책을 우회하려 하지 않는다.
///
/// secret 값은 인자에 싣지 않고 표준 입력으로만 넘기며, 이미 있는 secret 의 값은
/// 읽거나 바꾸지 않는다. 프로젝트 ID · 리전은 매번 `config/dev.json` 에서 읽는다.
final class FunctionsStep implements Step {
  /// Cloud Functions 단계를 만든다.
  ///
  /// [enabledProviders] 는 켠 로그인 수단 토큰이고, 그 수단의 함수까지 배포 ·
  /// 공개 호출 확인 대상에 더한다. [providerStepIds] 는 켠 로그인 수단 단계의
  /// id 로, 그 단계가 모두 끝나야 이 단계를 검사한다.
  FunctionsStep({
    Set<String> enabledProviders = const <String>{},
    List<String> providerStepIds = const <String>[],
  }) : _enabledProviders = <String>[
         for (final ProviderEntry entry in providerCatalog)
           if (enabledProviders.contains(entry.token)) entry.token,
       ],
       _providerStepIds = List<String>.unmodifiable(providerStepIds);

  /// 단계 제목.
  static const String stepTitle = 'Cloud Functions 배포';

  /// 실행하는 배포 스크립트(저장소 상대 경로).
  static const String deployScriptPath = 'scripts/deploy_functions.sh';

  /// 배포 스크립트에 넘기는 flavor.
  static const String flavor = 'dev';

  /// 배포 대상 함수 목록 파일(저장소 상대 경로) — 배포 스크립트도 이 파일을 읽는다.
  static const String manifestPath = 'scripts/functions_manifest.json';

  /// 켠 로그인 수단 함수가 옛 secret 버전을 쓸 때의 사유 머리(뒤에 `<n>개`).
  static const String staleSecretReasonPrefix =
      'secret 새 값이 함수에 반영되지 않았습니다 — 함수 ';

  /// 옛 secret 버전을 쓰는 함수를 다시 배포할 때의 계획 줄 안내.
  static const String redeployNote = '(배포하면 함수가 secret 최신 값을 씁니다)';

  /// 배포 버전 자리에 번호 대신 올 수 있는 「항상 최신」 표시.
  static const String latestVersionAlias = 'latest';

  /// 함수 목록 파일에서 공통 함수 배열의 키.
  static const String manifestCommonKey = 'common';

  /// 함수 목록 파일에서 로그인 수단별 함수 객체의 키.
  static const String manifestProvidersKey = 'providers';

  /// 의존성 설치가 끝나면 생기는 표시 파일(저장소 상대 경로).
  static const String modulesMarkerPath =
      'functions/node_modules/.modules.yaml';

  /// 없는 secret 을 만들 때 표준 입력으로 넘기는 자리표시 값.
  static const String secretPlaceholder = secretPlaceholderValue;

  /// 배포 스크립트 성공 시 표준 출력의 마지막 줄.
  static final RegExp deployOkPattern = RegExp(
    r'^DEPLOY OK dev functions=[0-9]+ batches=[0-9]+$',
  );

  /// 공개 호출을 허용하는 Cloud Run 역할.
  static const String invokerRole = 'roles/run.invoker';

  /// 공개 호출 주체 — 로그인하지 않은 호출자 전부.
  static const String invokerMember = 'allUsers';

  /// Firebase CLI 가 함수 공개 호출 설정에 실패했을 때 배포 출력에 쓰는 문장.
  static const String invokerBlockedMarker =
      'Unable to set the invoker for the IAM policy';

  /// gcloud 가 조직 정책으로 IAM 정책 변경을 거절할 때의 상태 이름.
  static const String failedPreconditionMarker = 'FAILED_PRECONDITION';

  /// gcloud 가 조직 정책으로 구성원을 거절할 때의 문장 조각.
  static const String permittedCustomerMarker = 'permitted customer';

  /// Firebase CLI 가 비대화형에서 컨테이너 이미지 정리 정책을 정하지 못했을 때
  /// 배포 출력에 쓰는 문장 조각.
  static const String cleanupPolicyMarker = 'could not set up cleanup policy';

  /// 조직 정책이 공개 호출을 막을 때의 안내.
  static const String orgPolicyGuidance =
      '조직 정책이 함수를 공개 호출(allUsers)할 수 없게 막고 있습니다. '
      '조직 관리자에게 이 프로젝트의 예외를 요청하거나, 조직에 속하지 않은 개인 '
      'Google 계정으로 만든 프로젝트를 쓰세요. 예외가 생긴 뒤 같은 명령을 다시 '
      '실행하면 이어집니다.';

  /// 조직 정책(도메인 제한 공유) 공식 문서.
  static const String orgPolicyDocUrl =
      'https://cloud.google.com/organization-policy/restrict-domains';

  /// 정리 정책을 만들고 한 번 더 배포하기 전에 보이는 줄.
  static const String cleanupPolicyNotice =
      '  함수는 배포됐지만 컨테이너 이미지 정리 정책이 없어 배포 명령이 실패로 '
      '끝났습니다 — 정책을 만들고 한 번 더 배포합니다.';

  /// 조직 정책 안내를 실패 요약으로 쓸 때의 문장(문서 링크 포함).
  static const String orgPolicyFailureSummary =
      '$orgPolicyGuidance\n    $orgPolicyDocUrl';

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

  /// [region] 의 Cloud Run 서비스 [service] IAM 정책을 JSON 으로 읽는 명령.
  static Command buildIamPolicyCommand(
    String service,
    String region,
    String projectId,
  ) => Command('gcloud', <String>[
    'run',
    'services',
    'get-iam-policy',
    service,
    '--region',
    region,
    '--project',
    projectId,
    '--format=json',
  ]);

  /// [region] 의 Cloud Run 서비스 [service] 에 공개 호출을 붙이는 명령.
  static Command buildInvokerBindingCommand(
    String service,
    String region,
    String projectId,
  ) => Command('gcloud', <String>[
    'run',
    'services',
    'add-iam-policy-binding',
    service,
    '--region',
    region,
    '--member=$invokerMember',
    '--role=$invokerRole',
    '--project',
    projectId,
  ]);

  /// [region] 의 함수 컨테이너 이미지 저장소에 정리 정책을 만드는 명령.
  ///
  /// 보관 기간은 Firebase CLI 기본값(대화형 배포가 Enter 기본값으로 묻는 값)을
  /// 쓴다. 비대화형이라 확인 질문은 기본값(진행)으로 넘어간다.
  static Command buildCleanupPolicyCommand(
    String projectId,
    String region, {
    String? workingDirectory,
  }) => Command('firebase', <String>[
    'functions:artifacts:setpolicy',
    '--project',
    projectId,
    '--location',
    region,
    '--non-interactive',
  ], workingDirectory: workingDirectory);

  /// [projectRoot] 의 함수 목록 파일에서 공통 함수 이름을 읽는다.
  ///
  /// 파일이 없거나 JSON · 모양이 다르면 null.
  static List<String>? readCommonFunctions(String projectRoot) {
    final Map<String, Object?>? manifest = _readManifest(projectRoot);
    if (manifest == null) return null;
    return _readNames(manifest[manifestCommonKey]);
  }

  /// [projectRoot] 의 함수 목록 파일에서 로그인 수단 [token] 의 함수 이름을 읽는다.
  ///
  /// 파일이 없거나 JSON · 모양이 다르거나 그 토큰이 없으면 null. 함수가 없는
  /// 로그인 수단은 빈 목록이다.
  static List<String>? readProviderFunctions(String projectRoot, String token) {
    final Map<String, Object?>? manifest = _readManifest(projectRoot);
    if (manifest == null) return null;
    final Object? providers = manifest[manifestProvidersKey];
    if (providers is! Map<String, Object?>) return null;
    return _readNames(providers[token]);
  }

  /// 함수 목록 파일을 JSON 객체로 읽는다 — 없거나 모양이 다르면 null.
  static Map<String, Object?>? _readManifest(String projectRoot) {
    final file = File('$projectRoot/$manifestPath');
    if (!file.existsSync()) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
    return decoded is Map<String, Object?> ? decoded : null;
  }

  /// [value] 가 빈 문자열 없는 문자열 배열이면 그 목록, 아니면 null.
  static List<String>? _readNames(Object? value) {
    if (value is! List<Object?>) return null;
    final names = <String>[
      for (final Object? name in value)
        if (name is String && name.isNotEmpty) name,
    ];
    return names.length == value.length ? names : null;
  }

  /// IAM 정책 결과에 [invokerRole] + [invokerMember] 바인딩이 있는지 판정한다.
  ///
  /// 바인딩이 없는 정책(`{}` · etag 만)은 false. 명령 실패 · JSON 아님은 null.
  static bool? hasPublicInvoker(CommandResult result) {
    if (!result.isSuccess) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? bindings = decoded['bindings'];
    if (bindings is! List<Object?>) return false;
    for (final Object? binding in bindings) {
      if (binding is! Map<String, Object?>) continue;
      if (binding['role'] != invokerRole) continue;
      final Object? members = binding['members'];
      if (members is List<Object?> && members.contains(invokerMember)) {
        return true;
      }
    }
    return false;
  }

  /// 공개 호출 추가 결과가 조직 정책 거절인지 판정한다.
  static bool isOrgPolicyRejection(CommandResult result) {
    final output = '${result.stdout}\n${result.stderr}';
    return output.contains(failedPreconditionMarker) &&
        output.contains(permittedCustomerMarker);
  }

  final List<String> _enabledProviders;
  final List<String> _providerStepIds;
  _FunctionsMode _mode = _FunctionsMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _region = '';
  // 배포 · 공개 호출 확인 대상 — 공통 함수 뒤에 켠 로그인 수단의 함수.
  List<String> _targets = const <String>[];
  bool _isModuleMissing = false;
  List<String> _missingSecrets = const <String>[];
  List<String> _lackingServices = const <String>[];
  CommandResult? _failedResult;

  @override
  String get id => 'functions';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => <String>[
    'configure',
    'apis',
    'firestore',
    ..._providerStepIds,
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
        '${UserFilesStep.jsonUserPath} 에서 Functions 리전(${FirestoreStep.functionsRegionKey})을 읽지 못했습니다',
      );
    }
    final List<String>? common = readCommonFunctions(context.projectRoot);
    if (common == null || common.isEmpty) {
      return _mark(
        _FunctionsMode.unreadable,
        '$manifestPath 에서 공통 함수 목록을 읽지 못했습니다',
      );
    }
    final providerFunctions = <String>[];
    for (final String token in _enabledProviders) {
      final List<String>? names = readProviderFunctions(
        context.projectRoot,
        token,
      );
      if (names == null) {
        return _mark(
          _FunctionsMode.unreadable,
          '$manifestPath 에서 로그인 수단 $token 의 함수 목록을 읽지 못했습니다',
        );
      }
      providerFunctions.addAll(names);
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
    _region = region;
    _targets = <String>[...common, ...providerFunctions];
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
            'secret ${_missingSecrets.length}개가 없습니다 (${_missingSecrets.join(' · ')})',
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
    final notDeployed = <String>[
      for (final String name in _targets)
        if (!deployed.containsKey(name)) name,
    ];
    if (notDeployed.isNotEmpty) {
      return _mark(
        _FunctionsMode.deploy,
        '배포되지 않은 함수가 있습니다 (${notDeployed.join(' · ')})',
      );
    }

    final CheckResult? staleProblem = await _inspectSecretVersions(
      context,
      functions,
      providerFunctions,
    );
    if (staleProblem != null) return staleProblem;

    final CheckResult? invokerProblem = await _inspectInvokers(
      context,
      deployed,
    );
    if (invokerProblem != null) return invokerProblem;
    _mode = _FunctionsMode.done;
    if (providerFunctions.isEmpty) {
      return Done(
        '의존성 · secret ${declared.length}개 · 공통 함수 ${common.length}개 배포 · '
        '공개 호출 확인',
      );
    }
    return Done(
      '의존성 · secret ${declared.length}개 · 공통 함수 ${common.length}개 · '
      '로그인 수단 함수 ${providerFunctions.length}개 배포 · 공개 호출 확인',
    );
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _FunctionsMode.deploy => <String>[
      if (_isModuleMissing) buildInstallCommand().render(),
      if (_missingSecrets.isNotEmpty)
        '(없는 secret 만 자리표시 값 $secretPlaceholder 으로 만듭니다 — 이미 있는 secret 의 값은 읽거나 바꾸지 않습니다)',
      for (final String name in _missingSecrets)
        buildSecretSetCommand(name, _projectId).render(),
      buildDeployCommand().render(),
      '(배포 대상은 $manifestPath 의 공통 함수와 ${UserFilesStep.jsonUserPath} 의 enabledAuthProviders 가 켠 로그인 수단의 함수입니다)',
      '(함수는 배포됐는데 컨테이너 이미지 정리 정책이 없어 배포 명령이 실패로 끝나면 정책을 만들고(보관 기간은 Firebase CLI 기본값) 한 번 더 배포합니다)',
      '(배포 뒤 공개 호출($invokerMember · $invokerRole)이 빠진 공통 함수가 있으면 붙입니다 — 조직 정책이 막으면 안내합니다)',
    ],
    _FunctionsMode.redeploy => <String>[
      buildDeployCommand().render(),
      redeployNote,
    ],
    _FunctionsMode.bind => <String>[
      '(앱이 함수를 부를 수 있게 공개 호출($invokerMember · $invokerRole)을 붙입니다 — 로그인 · App Check 는 함수 안에서 따로 검사합니다)',
      for (final String service in _lackingServices)
        buildInvokerBindingCommand(service, _region, _projectId).render(),
    ],
    _FunctionsMode.listFailed => <String>['(명령 원문을 보입니다)'],
    _FunctionsMode.unverifiable ||
    _FunctionsMode.unreadable ||
    _FunctionsMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _FunctionsMode.deploy ||
      _FunctionsMode.redeploy => await _applyDeploy(context),
      _FunctionsMode.bind => await _applyBindings(context),
      _FunctionsMode.listFailed => Failed(_reason, result: _failedResult),
      _FunctionsMode.unverifiable ||
      _FunctionsMode.unreadable => Failed(_reason),
      _FunctionsMode.done => const Applied(),
    };
  }

  /// 의존성 설치 → 없는 secret 만들기 → 배포 → 공개 호출 확인.
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
          result: created.withoutStdout(),
        );
      }
    }
    final StepOutcome deployed = await _runDeploy(
      context,
      isCleanupRetryAllowed: true,
    );
    if (deployed is! Applied) return deployed;
    return _bindAfterDeploy(context);
  }

  /// 배포 스크립트를 실행하고 결과를 분류한다.
  ///
  /// 출력에 공개 호출 설정 실패([invokerBlockedMarker])가 있으면 조직 정책 안내로
  /// 끝낸다 — 원문은 실행 중에 이미 화면에 흘렀으므로 안내만 뒤에 보인다. 그 밖에
  /// 정리 정책 실패([cleanupPolicyMarker])면 [isCleanupRetryAllowed] 일 때 한 번만
  /// 정책을 만들고 다시 배포한다.
  Future<StepOutcome> _runDeploy(
    WizardContext context, {
    required bool isCleanupRetryAllowed,
  }) async {
    final CommandResult result = await context.runner.stream(
      buildDeployCommand(workingDirectory: context.projectRoot),
    );
    final StepOutcome judged = judgeDeployResult(result);
    if (judged is! Failed) return judged;
    final output = '${result.stdout}\n${result.stderr}';
    if (output.contains(invokerBlockedMarker)) {
      return const Failed(orgPolicyFailureSummary);
    }
    if (isCleanupRetryAllowed && output.contains(cleanupPolicyMarker)) {
      context.terminal.writeLine(cleanupPolicyNotice);
      final CommandResult policy = await context.runner.stream(
        buildCleanupPolicyCommand(
          _projectId,
          _region,
          workingDirectory: context.projectRoot,
        ),
      );
      if (!policy.isSuccess) {
        return Failed(
          '컨테이너 이미지 정리 정책을 만들지 못했습니다 (종료 코드 ${policy.exitCode})',
          result: policy,
        );
      }
      return _runDeploy(context, isCleanupRetryAllowed: false);
    }
    return judged;
  }

  /// 배포 뒤 대상 함수의 공개 호출을 다시 읽어 빠진 서비스에만 붙인다.
  ///
  /// 목록 · 정책을 읽지 못하면 그대로 끝내고 실행 뒤 재검사가 사유를 보인다.
  Future<StepOutcome> _bindAfterDeploy(WizardContext context) async {
    final CommandResult functions = await context.runner.capture(
      buildFunctionsListCommand(_projectId),
    );
    final Map<String, String?>? deployed = parseDeployedFunctions(
      functions,
      _region,
    );
    if (deployed == null || !_targets.every(deployed.containsKey)) {
      return const Applied();
    }
    await _inspectInvokers(context, deployed);
    if (_mode != _FunctionsMode.bind) return const Applied();
    return _applyBindings(context);
  }

  /// 공개 호출이 빠진 서비스마다 바인딩을 더한다.
  ///
  /// 조직 정책 거절이면 안내로 끝내고 남은 서비스에 같은 명령을 더 시도하지
  /// 않는다.
  Future<StepOutcome> _applyBindings(WizardContext context) async {
    for (final String service in _lackingServices) {
      final CommandResult result = await context.runner.stream(
        buildInvokerBindingCommand(service, _region, _projectId),
      );
      if (result.isSuccess) continue;
      if (isOrgPolicyRejection(result)) {
        return const Failed(orgPolicyFailureSummary);
      }
      return Failed(
        '$service 서비스에 공개 호출을 붙이지 못했습니다 (종료 코드 ${result.exitCode})',
        result: result,
      );
    }
    return const Applied();
  }

  /// 켠 로그인 수단 함수 [providerFunctions] 의 배포 secret 버전을 최신 버전과
  /// 비교한다.
  ///
  /// [functions] (`functions:list --json` 결과)에 `secretEnvironmentVariables` 가
  /// 있는 함수만 보고, secret 마다 최신 버전을 한 번만 읽는다. 모두 최신이면
  /// null, 옛 버전을 쓰는 함수가 있으면 다시 배포할 할 일, 최신 버전을 읽지
  /// 못하면 상태를 사유에 넣은 할 일(실행은 응답 원문을 보이는 실패)이다.
  Future<CheckResult?> _inspectSecretVersions(
    WizardContext context,
    CommandResult functions,
    List<String> providerFunctions,
  ) async {
    if (providerFunctions.isEmpty) return null;
    final Map<String, List<DeployedSecret>> deployedSecrets =
        parseDeployedSecrets(functions, _region) ??
        const <String, List<DeployedSecret>>{};
    final latestVersions = <String, int>{};
    var staleCount = 0;
    for (final name in providerFunctions) {
      var isStale = false;
      for (final DeployedSecret used
          in deployedSecrets[name] ?? const <DeployedSecret>[]) {
        int? latest = latestVersions[used.secret];
        if (latest == null) {
          final RestResponse response = await context.rest.send(
            buildLatestVersionRequest(_projectId, used.secret),
          );
          latest = parseVersionNumber(response);
          if (latest == null) {
            return _mark(
              _FunctionsMode.listFailed,
              'secret ${used.secret} 의 최신 버전을 읽지 못했습니다 — '
              '${describeRestStatus(response)}',
              result: toFailureResult(response),
            );
          }
          latestVersions[used.secret] = latest;
        }
        if (isOlderVersion(used.version, latest)) isStale = true;
      }
      if (isStale) staleCount++;
    }
    if (staleCount == 0) return null;
    return _mark(
      _FunctionsMode.redeploy,
      '$staleSecretReasonPrefix$staleCount개',
    );
  }

  /// 배포 때 고정된 [deployed] 버전이 [latest] 보다 옛것이면 true.
  ///
  /// [latestVersionAlias] 는 항상 최신이라 false, 번호가 아닌 그 밖의 값은 다시
  /// 배포하면 번호로 고정되므로 true 다.
  static bool isOlderVersion(String deployed, int latest) {
    if (deployed == latestVersionAlias) return false;
    final int? number = int.tryParse(deployed);
    return number == null || number < latest;
  }

  /// 대상 함수들의 Cloud Run 서비스 IAM 을 읽어 공개 호출이 빠진 것을 찾는다.
  ///
  /// 모두 있으면 null, 아니면 판정을 두고 할 일 결과를 돌려준다. 서비스 이름은
  /// 함수 목록의 `runServiceId` 를 그대로 쓴다.
  Future<CheckResult?> _inspectInvokers(
    WizardContext context,
    Map<String, String?> deployed,
  ) async {
    final lackingNames = <String>[];
    final lackingServices = <String>[];
    for (final String name in _targets) {
      final String? service = deployed[name];
      if (service == null || service.isEmpty) {
        return _mark(
          _FunctionsMode.unverifiable,
          '$name 의 Cloud Run 서비스 이름을 읽지 못해 공개 호출을 확인할 수 없습니다 — '
          '2세대(v2) 함수로 배포됐는지 확인하세요',
        );
      }
      final CommandResult policy = await context.runner.capture(
        buildIamPolicyCommand(service, _region, _projectId),
      );
      final bool? isPublic = hasPublicInvoker(policy);
      if (isPublic == null) {
        return _mark(
          _FunctionsMode.listFailed,
          '$service 서비스의 IAM 정책을 읽지 못했습니다',
          result: policy,
        );
      }
      if (!isPublic) {
        lackingNames.add(name);
        lackingServices.add(service);
      }
    }
    _lackingServices = lackingServices;
    if (lackingServices.isEmpty) return null;
    return _mark(
      _FunctionsMode.bind,
      '공개 호출이 막힌 함수가 있습니다 (${lackingNames.join(' · ')})',
    );
  }

  /// 배포 스크립트 결과를 종료 코드와 마지막 줄 계약으로 판정한다.
  static StepOutcome judgeDeployResult(CommandResult result) {
    if (!result.isSuccess) {
      return Failed(
        'Functions 배포 스크립트가 실패했습니다 (종료 코드 ${result.exitCode})',
        result: result,
      );
    }
    final String? lastLine = findLastOutputLine(result.stdout);
    if (lastLine == null || !deployOkPattern.hasMatch(lastLine)) {
      return Failed(
        '배포 스크립트의 마지막 줄이 배포 완료 줄(DEPLOY OK dev functions=<개수> batches=<묶음 수>)이 아닙니다',
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
    final List<Object?>? items = _decodeFunctionItems(result);
    if (items == null) return null;
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

  /// `firebase functions:list --json` 결과에서 [region] 의 함수마다 쓰는 secret 과
  /// 배포 때 고정된 버전을 모은다.
  ///
  /// 함수 이름 → `secretEnvironmentVariables` 의 `secret` · `version`(숫자만 든
  /// 문자열). 그 필드가 없는 함수는 넣지 않는다. 실패 · 모양이 다르면 null.
  static Map<String, List<DeployedSecret>>? parseDeployedSecrets(
    CommandResult result,
    String region,
  ) {
    final List<Object?>? items = _decodeFunctionItems(result);
    if (items == null) return null;
    final secrets = <String, List<DeployedSecret>>{};
    for (final Object? item in items) {
      if (item is! Map<String, Object?> || item['region'] != region) continue;
      final Object? id = item['id'];
      final Object? variables = item['secretEnvironmentVariables'];
      if (id is! String || variables is! List<Object?>) continue;
      secrets[id] = <DeployedSecret>[
        for (final Object? variable in variables)
          if (variable is Map<String, Object?> &&
              variable['secret'] is String &&
              (variable['version'] is String || variable['version'] is int))
            (
              secret: variable['secret']! as String,
              version: '${variable['version']}',
            ),
      ];
    }
    return secrets;
  }

  /// `firebase functions:list --json` 성공 결과의 `result` 배열 — 실패 · 모양이
  /// 다르면 null.
  static List<Object?>? _decodeFunctionItems(CommandResult result) {
    if (!result.isSuccess) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? items = decoded['result'];
    return items is List<Object?> ? items : null;
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

  /// 명령 결과의 첫 빈 줄 아닌 줄(오류 출력 먼저)을 찾는다 — 없으면 종료 코드.
  static String _describeFirstLine(CommandResult result) {
    for (final text in <String>[result.stderr, result.stdout]) {
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

  /// 켠 로그인 수단 함수가 옛 secret 버전을 써서 다시 배포해야 한다.
  redeploy,

  /// 배포된 공통 함수 가운데 공개 호출이 빠진 서비스가 있다.
  bind,

  /// secret 목록 · IAM 정책을 읽지 못했다.
  listFailed,

  /// 함수의 Cloud Run 서비스 이름이 없어 공개 호출을 확인할 수 없다.
  unverifiable,

  /// 프로젝트 ID · 리전 · 함수 목록 파일 · secret 선언을 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
