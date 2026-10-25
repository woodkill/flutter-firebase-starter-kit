import 'dart:convert';

import '../command_runner.dart';
import '../confirm.dart';
import '../firebase_app_files.dart';
import '../providers/apple_key_input.dart';
import '../providers/idp_config.dart';
import '../providers/key_formats.dart';
import '../providers/keyed_provider_step.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'apple_step.dart';
import 'billing_step.dart';

/// Apple 로그인 Android 쪽 단계 — Firebase Apple 로그인의 코드 흐름 설정(Services
/// ID · Team ID · Key ID · 개인 키)을 쓴다.
///
/// 미룰 수 있는 단계([DeferrableStep])다 — 지금 안 하면 ✗ 줄과 끝 목록에 남고
/// 다음 단계 · 함수 배포는 그대로 진행한다. 검사는 `apple.com` 설정을
/// [readIdpConfig] 로 읽어(응답의 개인 키는 바로 가림 등록) Services ID ·
/// Key ID · Team ID 가 형식에 맞고 개인 키가 비어 있지 않은지 본다 — 위저드는
/// Services ID 를 저장하지 않으므로 「채워져 있고 형식이 맞음」 으로 판정한다.
///
/// 진행하면 Apple 콘솔에 넣을 값 표 · 할 일 줄을 보이고, 콘솔 작업을 마쳤으면
/// Services ID 를 받은 뒤 Apple 키([askAppleKey]) · Team ID([resolveTeamId])를
/// 받아 [codeFlowUpdateMask] 만 바꾸는 PATCH 로 쓴다. `.p8` 내용은 요청 본문에만
/// 실리고 화면 · 기록에는 [privateKeyPlaceholder] 를 보인다.
final class AppleAndroidStep implements DeferrableStep {
  /// Apple 로그인 Android 쪽 단계를 만든다.
  AppleAndroidStep();

  /// 단계 id.
  static const String stepId = 'apple_android';

  /// 단계 제목.
  static const String stepTitle = 'Apple 로그인 — Android 쪽';

  /// Apple Developer 콘솔 주소.
  static const String consoleUrl = 'https://developer.apple.com/account';

  /// 코드 흐름 설정을 쓸 때 바꾸는 필드 — 번들 ID · 사용 설정은 넣지 않는다.
  static const String codeFlowUpdateMask =
      'clientId,appleSignInConfig.codeFlowConfig';

  /// 할 일 사유의 머리 — 뒤에 빠진 자리 이름이 붙는다.
  static const String reasonPrefix = 'Android 에서 Apple 로그인을 쓰려면 끝내야 합니다';

  /// Services ID 제안값의 접미 — 번들 ID(소문자) 뒤에 붙인다.
  static const String servicesIdSuffix = '.signin';

  /// 화면 · 기록에서 `.p8` 내용 대신 보이는 자리 이름.
  static const String privateKeyPlaceholder = '<.p8 파일 내용>';

  /// 값 표에서 값을 읽지 못한 행의 값.
  static const String unreadValue = '(읽지 못했습니다)';

  /// Services ID 자리 이름.
  static const String servicesIdPlace = 'Services ID';

  /// Key ID 자리 이름.
  static const String keyIdPlace = 'Key ID';

  /// Team ID 자리 이름.
  static const String teamIdPlace = 'Team ID';

  /// 개인 키 자리 이름.
  static const String privateKeyPlace = '개인 키(.p8)';

  /// 실행 전 계획 줄의 안내 — 값 표 · 입력 뒤 코드 흐름 설정을 쓴다.
  static const String plannedFillNote =
      '(값 표 · 할 일을 보인 뒤 Services ID · .p8 파일 경로 · Key ID · Team ID 를 '
      '받아 Firebase Apple 코드 흐름 설정에 씁니다)';

  /// 값 표 뒤의 할 일 줄 — 기능 · 개념 이름만 쓴다(화면 단계는 docs/setup.md 「Apple 로그인 켜기」).
  static const List<String> todoLines = <String>[
    'Sign in with Apple 용 Services ID 만들기 · primary App ID(번들 ID) 연결',
    '그 Services ID 에 도메인 · Return URL 등록(값 표)',
    appleKeyTodoLine,
  ];

  _AndroidMode _mode = _AndroidMode.unreadable;
  String _reason = '';
  CommandResult? _failedResult;
  String _projectId = '';

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>[AppleStep.token];

  @override
  String get proceedLabel => '진행';

  @override
  String get deferLabel => '지금 안 함';

  // 코드 흐름 설정은 다시 쓰면 바뀌고 비용이 들지 않는다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _AndroidMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final IdpRead read = await readIdpConfig(
      context,
      projectId,
      AppleStep.idpId,
    );
    switch (read) {
      case IdpReadFailed(:final String reason, :final CommandResult? result):
        return _mark(
          _AndroidMode.requestFailed,
          '$reasonPrefix — $reason',
          result: result,
        );
      case IdpMissing():
        return _mark(
          _AndroidMode.fill,
          '$reasonPrefix — ${_allPlaces.join(' · ')}',
        );
      case IdpFound(:final Map<String, Object?> config):
        final flow = _CodeFlow.read(config);
        final List<String> missing = flow.findMissingPlaces();
        if (missing.isNotEmpty) {
          return _mark(
            _AndroidMode.fill,
            '$reasonPrefix — ${missing.join(' · ')}',
          );
        }
        _mode = _AndroidMode.done;
        return Done(
          '$servicesIdPlace ${flow.servicesId} · $keyIdPlace ${flow.keyId} · '
          '$teamIdPlace ${flow.teamId}',
        );
    }
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _AndroidMode.fill => <String>[
      plannedFillNote,
      _buildPatchRequest(
        servicesId: '<$servicesIdPlace>',
        teamId: '<$teamIdPlace>',
        keyId: '<$keyIdPlace>',
        privateKey: privateKeyPlaceholder,
      ).displayCurl(),
    ],
    _AndroidMode.requestFailed when _failedResult != null => const <String>[
      '(응답 원문을 보입니다)',
    ],
    _AndroidMode.requestFailed ||
    _AndroidMode.unreadable ||
    _AndroidMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _AndroidMode.fill => await _applyFill(context),
      _AndroidMode.requestFailed => Failed(_reason, result: _failedResult),
      _AndroidMode.unreadable => Failed(_reason),
      _AndroidMode.done => const Applied(),
    };
  }

  /// 번들 ID [bundleId] 로 Services ID 제안값을 만든다 — 만들 수 없으면 null.
  ///
  /// 번들 ID 를 소문자로 바꾼 뒤 [servicesIdSuffix] 를 붙이고, Services ID 형식이
  /// 아니면 제안하지 않는다.
  static String? suggestServicesId(String? bundleId) {
    if (bundleId == null) return null;
    final candidate = '${bundleId.toLowerCase()}$servicesIdSuffix';
    return appleServicesId.matches(candidate) ? candidate : null;
  }

  /// 값 표 → 콘솔 질문 → Services ID · Apple 키 · Team ID → 코드 흐름 PATCH.
  ///
  /// 콘솔 질문에서 미루면 [DeferredByUser] 로 다음 단계로 간다. 입력이 끝나거나
  /// 형식 검사 횟수를 넘기면 [Declined] 다.
  Future<StepOutcome> _applyFill(WizardContext context) async {
    final String? bundleId = readBundleId(context.projectRoot, context.flavor);
    final String? suggestion = suggestServicesId(bundleId);
    final host = '$_projectId.firebaseapp.com';
    writeSummary(
      context.terminal,
      title: 'Apple 콘솔에 넣을 값 — ${context.flavor.name}',
      rows: <SummaryRow>[
        SummaryRow('$servicesIdPlace (제안)', suggestion ?? unreadValue),
        SummaryRow('Return URL', 'https://$host/__/auth/handler'),
        SummaryRow('도메인', host),
        SummaryRow('primary App ID (번들 ID)', bundleId ?? unreadValue),
      ],
      notes: <String>[
        '콘솔: $consoleUrl',
        ...todoLines,
        '자세한 절차: ${formatDocReference(appleDocRef)}',
      ],
    );
    final int? choice = context.terminal.choose(consoleReadyQuestion, <String>[
      consoleReadyOption,
      deferLabel,
    ], defaultIndex: null);
    if (choice == null) return const Declined();
    if (choice == 1) return DeferredByUser(deferLabel);
    final String? servicesId = _askServicesId(context, suggestion);
    if (servicesId == null) return const Declined();
    final AppleKey? key = await askAppleKey(
      context,
      use: AppleKeyUse.signInWithApple,
    );
    if (key == null) return const Declined();
    final String? teamId = await resolveTeamId(context);
    if (teamId == null) return const Declined();
    final RestResponse response = await sendIdpRequest(
      context,
      _buildPatchRequest(
        servicesId: servicesId,
        teamId: teamId,
        keyId: key.keyId,
        privateKey: key.privateKey,
      ),
    );
    if (response.isOk) return const Applied();
    return Failed(
      'Firebase Apple 코드 흐름 설정을 쓰지 못했습니다 — '
      '${describeRestStatus(response)}',
      result: toFailureResult(response, redactor: context.redactor),
    );
  }

  /// Services ID 를 묻는다 — [suggestion] 은 Enter 기본값, 형식이 틀리면
  /// [maxKeyAttempts] 회까지 다시 묻는다.
  String? _askServicesId(WizardContext context, String? suggestion) {
    for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
      final String? answer = context.terminal.ask(
        servicesIdPlace,
        defaultValue: suggestion,
      );
      if (answer == null) return null;
      final String value = answer.trim();
      if (appleServicesId.matches(value)) return value;
      context.terminal.writeLine(
        '  ${appleServicesId.label} 형식이 맞지 않습니다 — ${value.length}자 · '
        '규칙: ${appleServicesId.description}',
      );
    }
    return null;
  }

  /// 코드 흐름 설정 PATCH 를 만든다 — 화면 · 기록에는 개인 키 대신
  /// [privateKeyPlaceholder] 를 보인다.
  RestRequest _buildPatchRequest({
    required String servicesId,
    required String teamId,
    required String keyId,
    required String privateKey,
  }) => buildIdpPatchRequest(
    _projectId,
    AppleStep.idpId,
    updateMask: codeFlowUpdateMask,
    body: _encodeBody(servicesId, teamId, keyId, privateKey),
    bodyDisplay: _encodeBody(servicesId, teamId, keyId, privateKeyPlaceholder),
  );

  /// 코드 흐름 설정 본문을 만든다.
  static String _encodeBody(
    String servicesId,
    String teamId,
    String keyId,
    String privateKey,
  ) => jsonEncode(<String, Object?>{
    'clientId': servicesId,
    'appleSignInConfig': <String, Object?>{
      'codeFlowConfig': <String, Object?>{
        'teamId': teamId,
        'keyId': keyId,
        'privateKey': privateKey,
      },
    },
  });

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_AndroidMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }

  /// 빠진 자리 이름을 고정 순서로 모은 목록(설정이 없을 때).
  static const List<String> _allPlaces = <String>[
    servicesIdPlace,
    keyIdPlace,
    teamIdPlace,
    privateKeyPlace,
  ];
}

/// `apple.com` 설정에서 읽은 Android 쪽 값 — 형식에 맞지 않는 값은 null.
final class _CodeFlow {
  const _CodeFlow({
    required this.servicesId,
    required this.keyId,
    required this.teamId,
    required this.hasPrivateKey,
  });

  /// 설정 [config] 의 최상위 `clientId` 와 `appleSignInConfig.codeFlowConfig` 를
  /// 읽는다.
  factory _CodeFlow.read(Map<String, Object?> config) {
    final Object? appleConfig = config['appleSignInConfig'];
    final Object? codeFlow = appleConfig is Map<String, Object?>
        ? appleConfig['codeFlowConfig']
        : null;
    final Map<String, Object?> flow = codeFlow is Map<String, Object?>
        ? codeFlow
        : const <String, Object?>{};
    final Object? privateKey = flow['privateKey'];
    return _CodeFlow(
      servicesId: _readMatching(config['clientId'], appleServicesId),
      keyId: _readMatching(flow['keyId'], appleKeyId),
      teamId: _readMatching(flow['teamId'], appleTeamId),
      hasPrivateKey: privateKey is String && privateKey.trim().isNotEmpty,
    );
  }

  final String? servicesId;
  final String? keyId;
  final String? teamId;
  final bool hasPrivateKey;

  /// 빠지거나 형식이 아닌 자리 이름을 고정 순서로 모은다.
  List<String> findMissingPlaces() => <String>[
    if (servicesId == null) AppleAndroidStep.servicesIdPlace,
    if (keyId == null) AppleAndroidStep.keyIdPlace,
    if (teamId == null) AppleAndroidStep.teamIdPlace,
    if (!hasPrivateKey) AppleAndroidStep.privateKeyPlace,
  ];

  /// [value] 가 [format] 에 맞는 문자열이면 돌려준다 — 아니면 null.
  static String? _readMatching(Object? value, KeyFormat format) =>
      value is String && format.matches(value) ? value : null;
}

/// Android 쪽 단계의 직전 검사 판정.
enum _AndroidMode {
  /// 자리가 빠져 값 표 · 입력 뒤 PATCH 한다.
  fill,

  /// 설정을 읽지 못했다 — 실행하면 실패.
  requestFailed,

  /// 프로젝트 ID 를 읽지 못했다 — 실행하면 실패.
  unreadable,

  /// 네 자리가 모두 있다.
  done,
}
