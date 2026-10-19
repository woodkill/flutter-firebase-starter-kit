import 'dart:convert';

import '../command_runner.dart';
import '../providers/provider_catalog.dart';
import '../providers/sign_in_counts.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'firestore_step.dart';
import 'functions_step.dart';

/// Custom Token 서명 권한 단계 — 켠 Custom Token 수단(Kakao · Naver · LINE)
/// 함수의 런타임 서비스 계정마다 그 계정 자신을 구성원으로 한 조건 없는 Token
/// Creator([tokenCreatorRole])를 확인하고 없으면 붙인다.
///
/// 함수는 로그인 때(Naver · LINE 은 연결 해제 · 회원탈퇴 때도) Firebase Custom
/// Token 을 만들어 서명하므로 런타임 서비스 계정에 이 권한이 있어야 한다 —
/// 빠지면 그 수단의 로그인과 Naver · LINE 의 연결 해제 · 회원탈퇴가 오류로
/// 끝난다. 서비스 이름은 Functions 단계와 같은 함수 목록
/// 해석([FunctionsStep.parseDeployedFunctions])으로 읽고, 런타임 서비스 계정은
/// 서비스 설정에서 읽는다 — 계정을 짐작하지 않는다. 계정이 여럿이면 계정마다
/// 한 번씩 정책을 읽고 빠진 계정에만 붙인다. 이미 있으면 바꾸지 않고, 프로젝트
/// 수준 정책은 읽지도 바꾸지도 않는다. 수단을 꺼도 붙인 바인딩은 회수하지 않는다.
final class TokenCreatorStep implements Step {
  /// 서명 권한 단계를 만든다.
  ///
  /// [enabledProviders] 가운데 Custom Token 수단([identityIndexProviders])만
  /// 표 순서로 보관해 그 수단의 함수를 확인 대상으로 쓴다.
  TokenCreatorStep({required Set<String> enabledProviders})
    : _tokens = <String>[
        for (final ProviderEntry entry in providerCatalog)
          if (enabledProviders.contains(entry.token) &&
              identityIndexProviders.contains(entry.token))
            entry.token,
      ];

  /// [enabledProviders] 에 Custom Token 수단이 하나라도 있으면 true.
  static bool isRequiredFor(Set<String> enabledProviders) =>
      enabledProviders.any(identityIndexProviders.contains);

  /// 단계 id.
  static const String stepId = 'token_creator';

  /// 단계 제목.
  static const String stepTitle = 'Custom Token 서명 권한';

  /// 서비스 계정이 자기 이름으로 토큰에 서명할 수 있게 하는 역할.
  static const String tokenCreatorRole = 'roles/iam.serviceAccountTokenCreator';

  /// Cloud Run 서비스 설정에서 런타임 서비스 계정만 꺼내는 출력 형식.
  static const String serviceAccountFormat =
      'value(spec.template.spec.serviceAccountName)';

  /// 부여가 거절됐을 때 원문 뒤에 보이는 할 일 — 권한 부족 · 조직 정책 두 경우를
  /// 한 문단으로 안내한다.
  static const String grantFailureGuidance =
      '서비스 계정의 IAM 정책을 바꿀 수 있는 계정(예: 프로젝트 소유자)으로 gcloud 에 '
      '로그인했는지 확인하세요. 조직 정책이 막으면 조직 관리자에게 이 프로젝트의 '
      '예외를 요청하세요. 권한이 생긴 뒤 다시 실행하면 이어집니다.';

  /// 부여 뒤 권한 반영을 기다리라는 안내 줄 — [displayNames] 는 켠 Custom Token
  /// 수단의 표시 이름(표 순서)이다.
  static String buildPropagationNotice(List<String> displayNames) =>
      '  Token Creator 를 붙였습니다 — 반영에 몇 분 걸릴 수 있어 그 사이 '
      '${displayNames.join(' · ')} 로그인이 실패할 수 있습니다. 몇 분 뒤 다시 '
      '시도하세요.';

  /// 서비스 계정 [serviceAccount] 를 IAM 구성원 표기로 바꾼다.
  static String buildMember(String serviceAccount) =>
      'serviceAccount:$serviceAccount';

  /// [region] 의 Cloud Run 서비스 [service] 런타임 서비스 계정을 읽는 명령.
  static Command buildServiceAccountCommand(
    String service,
    String region,
    String projectId,
  ) => Command('gcloud', <String>[
    'run',
    'services',
    'describe',
    service,
    '--region',
    region,
    '--project',
    projectId,
    '--format=$serviceAccountFormat',
  ]);

  /// 서비스 계정 [serviceAccount] 의 IAM 정책을 JSON 으로 읽는 명령.
  static Command buildPolicyCommand(String serviceAccount, String projectId) =>
      Command('gcloud', <String>[
        'iam',
        'service-accounts',
        'get-iam-policy',
        serviceAccount,
        '--project',
        projectId,
        '--format=json',
      ]);

  /// 서비스 계정 [serviceAccount] 에 그 계정 자신을 구성원으로 한 조건 없는
  /// Token Creator 를 붙이는 명령.
  static Command buildGrantCommand(String serviceAccount, String projectId) =>
      Command('gcloud', <String>[
        'iam',
        'service-accounts',
        'add-iam-policy-binding',
        serviceAccount,
        '--member=${buildMember(serviceAccount)}',
        '--role=$tokenCreatorRole',
        '--condition=None',
        '--project',
        projectId,
      ]);

  /// 서비스 설정 읽기 결과에서 런타임 서비스 계정을 꺼낸다.
  ///
  /// 성공이면 첫 빈 줄 아닌 줄을 앞뒤 공백 없이, 실패 · 빈 출력이면 null.
  static String? parseServiceAccount(CommandResult result) {
    if (!result.isSuccess) return null;
    for (final String line in const LineSplitter().convert(result.stdout)) {
      final String trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// 서비스 계정 IAM 정책 결과에 [serviceAccount] 자신을 구성원으로 한 조건 없는
  /// [tokenCreatorRole] 바인딩이 있는지 판정한다.
  ///
  /// 역할이 다르거나 · 구성원에 그 계정이 없거나 · 조건이 붙은 바인딩은 세지
  /// 않는다. 바인딩이 없는 정책은 false, 명령 실패 · JSON 객체 아님은 null.
  static bool? hasSelfTokenCreator(
    CommandResult result,
    String serviceAccount,
  ) {
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
    final String member = buildMember(serviceAccount);
    for (final Object? binding in bindings) {
      if (binding is! Map<String, Object?>) continue;
      if (binding['role'] != tokenCreatorRole) continue;
      if (binding['condition'] != null) continue;
      final Object? members = binding['members'];
      if (members is List<Object?> && members.contains(member)) return true;
    }
    return false;
  }

  final List<String> _tokens;
  _TokenCreatorMode _mode = _TokenCreatorMode.unreadable;
  String _reason = '';
  String _projectId = '';
  List<String> _missingAccounts = const <String>[];
  CommandResult? _failedResult;

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['functions'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _TokenCreatorMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    final String? region = FunctionsStep.readRegion(context);
    if (region == null) {
      return _mark(
        _TokenCreatorMode.unreadable,
        '${context.paths.json} 에서 Functions 리전(${FirestoreStep.functionsRegionKey})을 읽지 못했습니다',
      );
    }
    final targets = <String>[];
    for (final String token in _tokens) {
      final List<String>? names = FunctionsStep.readProviderFunctions(
        context.projectRoot,
        token,
      );
      if (names == null) {
        return _mark(
          _TokenCreatorMode.unreadable,
          '${FunctionsStep.manifestPath} 에서 로그인 수단 $token 의 함수 목록을 읽지 못했습니다',
        );
      }
      targets.addAll(names);
    }
    if (targets.isEmpty) {
      return _mark(
        _TokenCreatorMode.unreadable,
        '${FunctionsStep.manifestPath} 에 켠 Custom Token 수단의 함수가 없습니다',
      );
    }

    final CommandResult listed = await context.runner.capture(
      FunctionsStep.buildFunctionsListCommand(projectId),
    );
    final Map<String, String?>? deployed = FunctionsStep.parseDeployedFunctions(
      listed,
      region,
    );
    if (deployed == null) {
      return _mark(
        _TokenCreatorMode.listFailed,
        '배포된 함수 목록을 읽지 못했습니다',
        result: listed,
      );
    }
    final services = <String>[];
    for (final name in targets) {
      if (!deployed.containsKey(name)) {
        return _mark(
          _TokenCreatorMode.listFailed,
          '배포된 함수 목록에 $name 함수가 없습니다',
          result: listed,
        );
      }
      final String? service = deployed[name];
      if (service == null || service.isEmpty) {
        return _mark(
          _TokenCreatorMode.listFailed,
          '$name 의 Cloud Run 서비스 이름을 읽지 못했습니다',
          result: listed,
        );
      }
      services.add(service);
    }

    final accounts = <String>[];
    for (final service in services) {
      final CommandResult described = await context.runner.capture(
        buildServiceAccountCommand(service, region, projectId),
      );
      final String? account = parseServiceAccount(described);
      if (account == null) {
        return _mark(
          _TokenCreatorMode.listFailed,
          '$service 서비스의 런타임 서비스 계정을 읽지 못했습니다',
          result: described,
        );
      }
      if (!accounts.contains(account)) accounts.add(account);
    }

    final missing = <String>[];
    for (final account in accounts) {
      final CommandResult policy = await context.runner.capture(
        buildPolicyCommand(account, projectId),
      );
      final bool? hasBinding = hasSelfTokenCreator(policy, account);
      if (hasBinding == null) {
        return _mark(
          _TokenCreatorMode.listFailed,
          '서비스 계정 $account 의 IAM 정책을 읽지 못했습니다',
          result: policy,
        );
      }
      if (!hasBinding) missing.add(account);
    }
    _projectId = projectId;
    _missingAccounts = missing;
    if (missing.isEmpty) {
      _mode = _TokenCreatorMode.done;
      return Done('함수 런타임 서비스 계정 ${accounts.length}개 · Token Creator 있음');
    }
    return _mark(
      _TokenCreatorMode.grant,
      'Custom Token 서명 권한(Token Creator)이 없는 함수 런타임 서비스 계정이 있습니다 '
      '(${missing.length}개)',
    );
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _TokenCreatorMode.grant => <String>[
      _buildGrantNote(),
      for (final String account in _missingAccounts)
        buildGrantCommand(account, _projectId).render(),
    ],
    _TokenCreatorMode.listFailed => <String>['(명령 원문을 보입니다)'],
    _TokenCreatorMode.unreadable || _TokenCreatorMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _TokenCreatorMode.grant => await _applyGrants(context),
      _TokenCreatorMode.listFailed => Failed(_reason, result: _failedResult),
      _TokenCreatorMode.unreadable => Failed(_reason),
      _TokenCreatorMode.done => const Applied(),
    };
  }

  /// 빠진 계정마다 부여 명령을 흘려 실행하고, 모두 성공하면 반영 대기 안내를
  /// 한 번 보인다.
  ///
  /// 실패하면 그 자리에서 할 일([grantFailureGuidance])로 끝내고 남은 계정에
  /// 같은 명령을 더 하지 않는다 — 거절 종류를 출력 문자열로 가르지 않고 다른
  /// 방법으로 우회하지 않는다.
  Future<StepOutcome> _applyGrants(WizardContext context) async {
    for (final String account in _missingAccounts) {
      final CommandResult result = await context.runner.stream(
        buildGrantCommand(account, _projectId),
      );
      if (result.isSuccess) continue;
      return Failed(
        '함수 런타임 서비스 계정에 Token Creator 를 붙이지 못했습니다 '
        '(종료 코드 ${result.exitCode}) — $grantFailureGuidance '
        '(${formatManualReference(providersManualHeading)} 「켜기」 ⑦)',
        result: result,
      );
    }
    context.terminal.writeLine(buildPropagationNotice(_buildDisplayNames()));
    return const Applied();
  }

  /// 부여 계획 줄 앞에 보이는 안내 줄을 만든다.
  String _buildGrantNote() =>
      '(${_describeProviders()} 함수가 로그인 토큰에 서명할 수 있게, 런타임 서비스 '
      '계정에 그 계정 자신을 구성원으로 한 Token Creator 를 조건 없이 붙입니다 — '
      '프로젝트 수준 역할은 바꾸지 않습니다)';

  /// 켠 Custom Token 수단의 표시 이름을 표 순서로 ` · ` 로 잇는다.
  String _describeProviders() => _buildDisplayNames().join(' · ');

  /// 켠 Custom Token 수단의 표시 이름 목록(표 순서)을 만든다.
  List<String> _buildDisplayNames() => <String>[
    for (final String token in _tokens)
      findProvider(token)?.displayName ?? token,
  ];

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(
    _TokenCreatorMode mode,
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
enum _TokenCreatorMode {
  /// Token Creator 가 빠진 런타임 서비스 계정이 있어 붙여야 한다.
  grant,

  /// 함수 목록 · 서비스 계정 · IAM 정책을 읽지 못했다.
  listFailed,

  /// 프로젝트 ID · 리전 · 함수 목록 파일을 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
