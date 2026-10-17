import 'dart:convert';

import '../command_runner.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';

/// Firebase · Google Cloud CLI 로그인 단계 — 두 CLI 가 같은 계정으로 로그인됐는지
/// 검사하고, 빠진 로그인만 브라우저로 이어지는 대화형 명령으로 실행한다.
///
/// 검사 술어는 세 가지다. ① `firebase login:list --json` 에 계정이 1개 이상.
/// ② `gcloud auth print-access-token` 이 성공 — 로그인 계정이 남아 있어도 토큰
/// 갱신(재인증)이 실패할 수 있어 계정 목록이 아니라 토큰 발급으로 판정한다.
/// ③ `gcloud config get-value account` 와 firebase CLI 의 기본 계정(목록의 첫 항목)이
/// 대소문자를 무시하고 같음 — REST 는 gcloud 토큰을, 배포는 firebase CLI 를 쓰므로
/// 계정이 갈리면 권한도 갈린다.
///
/// 계정 이메일이 실리는 명령은 모두 민감 출력으로 실행해 실행 기록에 본문이 남지
/// 않게 하고, 요약 · 사유 문구에도 이메일을 넣지 않는다.
final class LoginStep implements Step {
  /// 로그인 단계를 만든다.
  LoginStep();

  /// 단계 제목.
  static const String stepTitle = 'Firebase · Google Cloud 로그인';

  /// firebase CLI 의 로그인 계정 목록을 읽는 명령 — 출력에 이메일이 실린다.
  static const Command firebaseAccountsCommand = Command('firebase', <String>[
    'login:list',
    '--json',
  ], isOutputSensitive: true);

  /// gcloud 의 지금 계정을 읽는 명령 — 출력에 이메일이 실린다.
  static const Command gcloudAccountCommand = Command('gcloud', <String>[
    'config',
    'get-value',
    'account',
  ], isOutputSensitive: true);

  /// firebase CLI 로그인 — 브라우저를 열고 기다린다.
  static const Command firebaseLoginCommand = Command('firebase', <String>[
    'login',
  ]);

  /// gcloud 로그인 — 브라우저를 열고 기다린다.
  static const Command gcloudLoginCommand = Command('gcloud', <String>[
    'auth',
    'login',
  ]);

  /// firebase CLI 로그인 계정이 없을 때의 사유.
  static const String noFirebaseReason = 'firebase CLI 에 로그인한 계정이 없습니다';

  /// gcloud 액세스 토큰을 받지 못했을 때의 사유.
  static const String noTokenReason = 'gcloud 액세스 토큰을 받지 못했습니다 — 다시 로그인해야 합니다';

  /// 두 CLI 계정이 다를 때의 사유.
  static const String accountMismatchReason =
      'firebase CLI 와 gcloud 가 다른 계정으로 로그인돼 있습니다';

  /// 계정이 다를 때 gcloud 로그인 직전에 보이는 안내.
  static const String sameAccountGuidance =
      'gcloud 로그인 브라우저 창에서 firebase 에 로그인한 계정과 같은 계정을 고르세요.';

  /// 끝났을 때의 요약 — 계정 이메일은 넣지 않는다.
  static const String doneSummary = 'firebase CLI · gcloud 같은 계정 · 액세스 토큰 확인';

  _LoginState _state = const _LoginState(
    hasFirebaseAccount: false,
    hasToken: false,
    isSameAccount: false,
  );

  @override
  String get id => 'login';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['tools'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    _state = await _inspect(context);
    final problems = <String>[
      if (!_state.hasFirebaseAccount) noFirebaseReason,
      if (!_state.hasToken) noTokenReason,
      if (_state.hasFirebaseAccount && _state.hasToken && !_state.isSameAccount)
        accountMismatchReason,
    ];
    if (problems.isEmpty) return const Done(doneSummary);
    return Todo(problems.join(' · '));
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => <String>[
    for (final Command command in _state.loginCommands) command.render(),
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 결과(_state)를 그대로 쓴다.
    for (final Command command in _state.loginCommands) {
      if (identical(command, gcloudLoginCommand) && _state.isMismatch) {
        context.terminal.writeLine('  $sameAccountGuidance');
      }
      final int code = await context.runner.interactive(command);
      if (code != 0) {
        return Failed(
          '${command.render()} 이 실패했습니다 (종료 코드 $code) — 위 출력을 확인하세요',
        );
      }
    }
    return const Applied();
  }

  /// 세 술어를 읽기 전용 명령으로 검사한다.
  ///
  /// 계정 비교는 firebase 계정과 토큰이 모두 있을 때만 한다. 읽은 이메일 · 토큰은
  /// 화면 · 기록에서 가리도록 등록한다.
  Future<_LoginState> _inspect(WizardContext context) async {
    final String? firebaseEmail = await _readFirebaseAccount(context);
    final CommandResult token = await context.runner.capture(
      AccessTokenSource.tokenCommand,
    );
    final String tokenText = token.stdout.trim();
    final bool hasToken = token.isSuccess && tokenText.isNotEmpty;
    if (hasToken) context.redactor.register(tokenText);
    if (firebaseEmail == null || !hasToken) {
      return _LoginState(
        hasFirebaseAccount: firebaseEmail != null,
        hasToken: hasToken,
        isSameAccount: false,
      );
    }
    final CommandResult account = await context.runner.capture(
      gcloudAccountCommand,
    );
    final String gcloudEmail = account.isSuccess ? account.stdout.trim() : '';
    if (gcloudEmail.isNotEmpty) context.redactor.register(gcloudEmail);
    return _LoginState(
      hasFirebaseAccount: true,
      hasToken: true,
      isSameAccount: gcloudEmail.toLowerCase() == firebaseEmail.toLowerCase(),
    );
  }

  /// firebase CLI 의 기본 계정(목록 첫 항목) 이메일을 읽는다 — 없으면 null.
  ///
  /// firebase CLI 는 전역 기본 계정을 목록 맨 앞에 두므로 첫 항목이 CLI 가 실제로
  /// 쓰는 계정이다. 명령 실패 · JSON 이 아님 · 빈 목록은 모두 계정 없음으로 본다.
  Future<String?> _readFirebaseAccount(WizardContext context) async {
    final CommandResult result = await context.runner.capture(
      firebaseAccountsCommand,
    );
    if (!result.isSuccess) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? accounts = decoded['result'];
    if (accounts is! List<Object?> || accounts.isEmpty) return null;
    final Object? first = accounts.first;
    if (first is! Map<String, Object?>) return null;
    final Object? user = first['user'];
    if (user is! Map<String, Object?>) return null;
    final Object? email = user['email'];
    if (email is! String || email.trim().isEmpty) return null;
    final String trimmed = email.trim();
    context.redactor.register(trimmed);
    return trimmed;
  }
}

/// 직전 검사에서 읽은 로그인 상태 — 이메일은 담지 않는다.
final class _LoginState {
  const _LoginState({
    required this.hasFirebaseAccount,
    required this.hasToken,
    required this.isSameAccount,
  });

  final bool hasFirebaseAccount;
  final bool hasToken;
  final bool isSameAccount;

  /// 두 CLI 모두 로그인됐지만 계정이 다르면 true.
  bool get isMismatch => hasFirebaseAccount && hasToken && !isSameAccount;

  /// 실행할 로그인 명령(순서대로) — 계정이 다르면 gcloud 쪽을 다시 로그인한다.
  List<Command> get loginCommands => <Command>[
    if (!hasFirebaseAccount) LoginStep.firebaseLoginCommand,
    if (!hasToken || isMismatch) LoginStep.gcloudLoginCommand,
  ];
}
