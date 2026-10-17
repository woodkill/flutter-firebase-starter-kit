import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../step.dart';
import '../terminal.dart';
import '../wizard.dart';
import 'firebase_project_step.dart';

/// 고른 flavor 의 사용자 config(`config/<flavor>.json`) `firebaseProjectId` 를
/// 읽는다 — 파일 · 키가 없거나 자리표시(빈 값 · 그 flavor 의 example 값)면 null.
///
/// 프로젝트 ID 의 진실원은 이 값 하나라 프로젝트 뒤 단계는 매번 여기서 읽는다.
String? readConfiguredProjectId(WizardContext context) {
  final String path = context.resolve(context.paths.json);
  if (!File(path).existsSync()) return null;
  final String? value = readJsonString(
    path,
    FirebaseProjectStep.projectIdKey,
  )?.trim();
  if (value == null ||
      value.isEmpty ||
      value == context.flavor.placeholderProjectId) {
    return null;
  }
  return value;
}

/// 결제 단계 — 프로젝트에 열린 결제 계정을 연결해 Blaze(종량제) 요금제로 바꾼다.
///
/// 검사는 프로젝트의 결제 정보(`billingEnabled`)다. 새 프로젝트 · 기존 프로젝트
/// 모두 같은 검사를 거친다. 연결되지 않았으면 열린 결제 계정 목록을 보여 고르게
/// 하고(1개면 그 계정이 기본값), 없으면 결제 계정 만들기 링크를 보인 뒤 Enter 로
/// 목록을 다시 읽는다. 연결은 값 확인 표 뒤에만 실행한다. 결제 계정 · 결제 정보를
/// 읽는 명령은 민감 출력으로 실행해 CLI 원문 JSON 이 실행 기록에 남지 않는다.
final class BillingStep implements Step {
  /// 결제 단계를 만든다.
  BillingStep();

  /// 단계 제목.
  static const String stepTitle = '결제 계정 (Blaze 요금제)';

  /// 열린 결제 계정 목록을 읽는 명령 — 결제 계정 이름 · ID 가 실린다.
  static const Command openAccountsCommand = Command('gcloud', <String>[
    'billing',
    'accounts',
    'list',
    '--filter=open=true',
    '--format=json',
  ], isOutputSensitive: true);

  /// [projectId] 의 결제 정보를 읽는 명령을 만든다 — 결제 계정 ID 가 실린다.
  static Command billingInfoCommand(String projectId) => Command(
    'gcloud',
    <String>['billing', 'projects', 'describe', projectId, '--format=json'],
    isOutputSensitive: true,
  );

  /// [projectId] 에 결제 계정 [accountId] 를 연결하는 명령을 만든다.
  static Command buildLinkCommand(String projectId, String accountId) =>
      Command('gcloud', <String>[
        'billing',
        'projects',
        'link',
        projectId,
        '--billing-account=$accountId',
      ]);

  /// 결제 계정 만들기 페이지.
  static const String createAccountUrl =
      'https://console.cloud.google.com/billing/create';

  /// 결제 계정당 프로젝트 한도 안내 페이지.
  static const String quotaHelpUrl =
      'https://support.google.com/cloud/answer/6330231';

  /// 결제 계정 고르기 질문.
  static const String accountChoiceQuestion = '연결할 결제 계정을 고르세요';

  /// 확인 표 제목.
  static const String confirmTitle = '결제 계정 연결 — 확인';

  /// 확인 표 경고.
  static const List<String> costWarnings = <String>[
    '결제 계정을 연결하면 프로젝트가 Blaze(종량제) 요금제로 바뀝니다.',
    '무료 사용량을 넘는 사용분은 이 결제 계정으로 청구됩니다.',
  ];

  /// 열린 결제 계정이 없을 때의 안내.
  static const String noOpenAccountGuidance =
      '  열린 결제 계정이 없습니다 — 브라우저에서 결제 계정을 만든 뒤 Enter 를 누르면 '
      '목록을 다시 읽습니다';

  /// 결제 계정 리소스 이름의 접두.
  static const String accountNamePrefix = 'billingAccounts/';

  _BillingMode _mode = _BillingMode.unreadable;
  String _reason = '';
  String _projectId = '';
  CommandResult? _failedResult;

  @override
  String get id => 'billing';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['firebase_project'];

  // 확인 표는 결제 계정 연결에서만 보인다 — 실패 전용 모드에는 안내가 붙지 않는다.
  @override
  bool get isCostlyOrIrreversible => _mode == _BillingMode.link;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      _mode = _BillingMode.unreadable;
      _reason = '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다';
      return Todo(_reason);
    }
    _projectId = projectId;
    final CommandResult result = await context.runner.capture(
      billingInfoCommand(projectId),
    );
    final bool? isEnabled = _parseBillingEnabled(result);
    if (isEnabled == null) {
      _mode = _BillingMode.infoFailed;
      _reason = '$projectId 의 결제 정보를 읽지 못했습니다';
      _failedResult = result.withoutStdout();
      return Todo(_reason);
    }
    if (isEnabled) {
      _mode = _BillingMode.done;
      return Done('$projectId — Blaze(종량제) · 결제 계정 연결됨');
    }
    _mode = _BillingMode.link;
    _reason = '$projectId 에 결제 계정이 연결되지 않았습니다 — Spark(무료) 요금제';
    return Todo(_reason);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _BillingMode.link => <String>[
      openAccountsCommand.render(),
      '(열린 결제 계정을 고르고 확인 표 뒤에 아래 명령을 실행합니다)',
      'gcloud billing projects link $_projectId --billing-account=<결제 계정 ID>',
    ],
    _BillingMode.infoFailed => <String>[
      '(${billingInfoCommand(_projectId).render()} 의 오류를 보입니다)',
    ],
    _BillingMode.unreadable || _BillingMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _BillingMode.link => await _applyLink(context),
      _BillingMode.infoFailed => Failed(_reason, result: _failedResult),
      _BillingMode.unreadable => Failed(_reason),
      _BillingMode.done => const Applied(),
    };
  }

  /// 결제 계정을 고르게 하고 확인 표 뒤에 연결한다.
  Future<StepOutcome> _applyLink(WizardContext context) async {
    final Terminal terminal = context.terminal;
    List<_BillingAccount> accounts;
    while (true) {
      final CommandResult result = await context.runner.capture(
        openAccountsCommand,
      );
      final List<_BillingAccount>? parsed = _parseAccounts(result);
      if (parsed == null) {
        return Failed('결제 계정 목록을 읽지 못했습니다', result: result.withoutStdout());
      }
      if (parsed.isNotEmpty) {
        accounts = parsed;
        break;
      }
      terminal.writeLine(noOpenAccountGuidance);
      terminal.writeLine('  $createAccountUrl');
      if (!terminal.waitForEnter(waitForEnterMessage)) return const Declined();
    }

    final int? index = terminal.choose(accountChoiceQuestion, <String>[
      for (final _BillingAccount account in accounts) account.label,
    ]);
    if (index == null) return const Declined();
    final _BillingAccount account = accounts[index];
    if (!confirmSummary(
      terminal,
      title: confirmTitle,
      rows: <SummaryRow>[
        SummaryRow('프로젝트 ID', _projectId),
        SummaryRow('결제 계정', account.label),
        const SummaryRow('요금제', 'Spark(무료) → Blaze(종량제)'),
      ],
      warnings: costWarnings,
    )) {
      return const Declined();
    }

    final CommandResult linked = await context.runner.stream(
      buildLinkCommand(_projectId, account.accountId),
    );
    if (linked.isSuccess) return const Applied();
    final String output = '${linked.stdout}\n${linked.stderr}'.toLowerCase();
    final String summary = output.contains('quota')
        ? '결제 계정을 연결하지 못했습니다 — 결제 계정당 연결할 수 있는 프로젝트 수 한도일 수 '
              '있습니다. 한도 · 증액 요청: $quotaHelpUrl'
        : '결제 계정을 연결하지 못했습니다';
    return Failed(summary, result: linked);
  }

  /// 결제 정보 JSON 의 `billingEnabled` 를 읽는다 — 실패 · 모양이 다르면 null.
  static bool? _parseBillingEnabled(CommandResult result) {
    if (!result.isSuccess) return null;
    final Object? decoded = _tryDecode(result.stdout);
    if (decoded is! Map<String, Object?>) return null;
    final Object? isEnabled = decoded['billingEnabled'];
    // 결제가 없으면 필드가 빠질 수 있다 — 참일 때만 연결된 것으로 본다.
    return isEnabled == true;
  }

  /// 결제 계정 목록 JSON 을 읽는다 — 실패 · 모양이 다르면 null.
  static List<_BillingAccount>? _parseAccounts(CommandResult result) {
    if (!result.isSuccess) return null;
    final Object? decoded = _tryDecode(result.stdout);
    if (decoded is! List<Object?>) return null;
    final List<_BillingAccount> accounts = <_BillingAccount>[];
    for (final Object? item in decoded) {
      if (item is! Map<String, Object?> || item['open'] == false) continue;
      final Object? name = item['name'];
      final Object? displayName = item['displayName'];
      if (name is String) {
        final String accountId = name.startsWith(accountNamePrefix)
            ? name.substring(accountNamePrefix.length)
            : name;
        if (accountId.isEmpty) continue;
        accounts.add(
          _BillingAccount(accountId, displayName is String ? displayName : ''),
        );
      }
    }
    return accounts;
  }

  /// JSON 으로 읽는다 — JSON 이 아니면 null.
  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// 열린 결제 계정 하나.
final class _BillingAccount {
  const _BillingAccount(this.accountId, this.displayName);

  /// `billingAccounts/` 를 뗀 결제 계정 ID.
  final String accountId;

  final String displayName;

  /// 고르기 · 확인 표 문구.
  String get label =>
      displayName.isEmpty ? accountId : '$displayName ($accountId)';
}

/// 직전 검사의 판정.
enum _BillingMode {
  /// 결제 계정을 골라 연결한다.
  link,

  /// 결제 정보 명령이 실패했다.
  infoFailed,

  /// 프로젝트 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
