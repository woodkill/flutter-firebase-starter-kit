import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../providers/icon_specs.dart';
import '../providers/idp_config.dart';
import '../providers/key_formats.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../terminal.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'login_step.dart';
import 'sign_in_step.dart';

/// Google 로그인 단계 — Firebase 의 Google 로그인을 켜고 Web client ID 를 config
/// 에 쓴다.
///
/// 검사는 Identity Toolkit 의 `google.com` 로그인 수단 설정 GET 이다(응답에 OAuth
/// client secret 이 평문으로 실리므로 [readIdpConfig] 로만 읽는다). 꺼져 있거나
/// 없으면 동의 화면 값 표(앱 이름 · 지원 이메일)를 보이고 고르게 한 뒤, 저장소
/// 밖에 두는 임시 설정 파일([authConfigPath])로 Firebase CLI 의 auth 배포를 실행해
/// 켠다. 임시 파일은 성공 · 실패와 관계없이 실행 뒤 지우고, 추적 파일
/// `firebase.json` 은 건드리지 않는다. 켠 뒤 다시 읽은 `clientId` 를 config 의
/// `googleServerClientId` 에 쓴다.
///
/// 동의 화면 값 표에는 로고 파일 경로 행과 요구 정도 노트도 함께 보인다 — 동의
/// 화면 로고는 출시 전 선택이고, 올리면 브랜드 인증 뒤에 보인다.
///
/// 지원 이메일 제안값은 gcloud 의 지금 계정이다. 제안값을 읽지 못하면 값 표에
/// [unreadEmailValue] 를 보이고, `이대로 진행` 을 골라도 이메일을 먼저 묻는다.
/// 지원 이메일 · 앱 이름은 임시 파일에만 잠깐 실리고 저장소 · config 에 남지 않는다.
final class GoogleStep implements Step {
  /// Google 로그인 단계를 만든다.
  GoogleStep();

  /// 단계 제목.
  static const String stepTitle = 'Google 로그인';

  /// 로그인 수단 표의 토큰.
  static const String token = 'google';

  /// Firebase 로그인 수단 설정의 IdP ID.
  static const String idpId = 'google.com';

  /// 켜기에 쓰는 임시 설정 파일(저장소 루트 기준 · 추적하지 않는 디렉터리).
  static const String authConfigPath = '.setup/auth-google.json';

  /// Web client ID 를 쓰는 config 키.
  static const String clientIdConfigKey = 'googleServerClientId';

  /// 앱 이름을 읽는 config 키.
  static const String appNameConfigKey = 'appName';

  /// 동의 화면 값 표 제목.
  static const String summaryTitle = 'Google 로그인 — 동의 화면';

  /// 값 표의 앱 이름 행 라벨.
  static const String appNameRowLabel = '앱 이름';

  /// 값 표의 지원 이메일 행 라벨.
  static const String supportEmailRowLabel = '지원 이메일';

  /// 지원 이메일 제안값을 읽지 못했을 때 값 표에 보이는 값.
  static const String unreadEmailValue = '(읽지 못했습니다)';

  /// 이미 동의 화면이 있는 프로젝트를 위한 안내.
  static const String existingBrandNote = '이미 동의 화면이 있으면 그 이름 · 이메일을 넣으세요';

  /// 값 표 뒤 고르기 질문.
  static const String choiceQuestion = '이 값으로 Google 로그인을 켤까요?';

  /// 고르기 — 진행.
  static const String proceedOption = '이대로 진행';

  /// 고르기 — 지원 이메일 고치기.
  static const String editEmailOption = '지원 이메일 고치기';

  /// 지원 이메일 질문.
  static const String emailQuestion = '지원 이메일 (예: support@example.com)';

  /// 지원 이메일 형식 오류.
  static const String invalidEmailMessage =
      '  이메일 형식이 아닙니다 — 이름@도메인 꼴로 공백 없이 입력하세요';

  /// 같은 질문을 다시 묻는 최대 횟수.
  static const int maxInputAttempts = 3;

  /// 상위 리소스 종류 가운데 조직 안에 있는 것 — 폴더는 조직 아래에만 있다.
  static const Set<String> organizationParentTypes = <String>{
    'organization',
    'folder',
  };

  /// 프로젝트가 조직 아래에 있을 때 값 표에 보이는 경고.
  static final String organizationWarning =
      '조직 밖 사용자가 Google 로그인을 하려면 동의 화면을 외부로 바꿔야 합니다 — '
      '${formatManualReference(providersManualHeading)}';

  /// gcloud 의 지금 계정을 읽는 명령 — 출력에 이메일이 실려 민감 출력이다.
  static const Command accountCommand = LoginStep.gcloudAccountCommand;

  /// 지원 이메일 형식 — `@` 하나 · 공백 없음 · 도메인에 점.
  static final RegExp supportEmailPattern = RegExp(
    r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$',
  );

  /// [projectId] 의 상위(조직 · 폴더)를 읽는 명령을 만든다.
  ///
  /// 출력에 조직 ID · 프로젝트 번호가 실려 민감 출력으로 둔다.
  static Command buildProjectDescribeCommand(String projectId) => Command(
    'gcloud',
    <String>['projects', 'describe', projectId, '--format=json'],
    isOutputSensitive: true,
  );

  /// [projectId] 의 Google 로그인을 임시 설정 파일로 켜는 명령을 만든다.
  static Command buildDeployCommand(
    String projectId, {
    String? workingDirectory,
  }) => Command('firebase', <String>[
    'deploy',
    '--only',
    'auth',
    '--config',
    authConfigPath,
    '--project',
    projectId,
    '--non-interactive',
  ], workingDirectory: workingDirectory);

  /// 임시 설정 파일 내용을 만든다 — 동의 화면 이름 · 지원 이메일만 싣는다.
  static String buildAuthConfigContent({
    required String appName,
    required String supportEmail,
  }) => jsonEncode(<String, Object?>{
    'auth': <String, Object?>{
      'providers': <String, Object?>{
        'googleSignIn': <String, Object?>{
          'oAuthBrandDisplayName': appName,
          'supportEmail': supportEmail,
        },
      },
    },
  });

  /// [value] 가 지원 이메일 형식이면 true.
  static bool isValidSupportEmail(String value) =>
      supportEmailPattern.hasMatch(value);

  /// describe 출력 [output] 의 상위가 조직 · 폴더면 true.
  ///
  /// 해석하지 못하거나 상위가 없으면 false 다.
  static bool isUnderOrganization(String output) {
    try {
      final Object? decoded = jsonDecode(output);
      if (decoded is! Map<String, Object?>) return false;
      final Object? parent = decoded['parent'];
      if (parent is! Map<String, Object?>) return false;
      return organizationParentTypes.contains(parent['type']);
    } on FormatException {
      return false;
    }
  }

  _GoogleMode _mode = _GoogleMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _clientId = '';
  CommandResult? _failedResult;

  @override
  String get id => token;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['providers', 'sign_in'];

  // 동의 화면(brand)은 만든 뒤 지울 수 없다 — 값 표와 고르기가 그 확인이다.
  @override
  bool get isCostlyOrIrreversible => _mode == _GoogleMode.enable;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _GoogleMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final IdpRead read = await readIdpConfig(context, projectId, idpId);
    switch (read) {
      case IdpReadFailed(:final String reason, :final CommandResult? result):
        return _mark(_GoogleMode.requestFailed, reason, result: result);
      case IdpMissing():
        return _mark(_GoogleMode.enable, 'Firebase 에서 Google 로그인이 꺼져 있습니다');
      case IdpFound(:final Map<String, Object?> config):
        if (config['enabled'] != true) {
          return _mark(_GoogleMode.enable, 'Firebase 에서 Google 로그인이 꺼져 있습니다');
        }
        final String? clientId = _readClientId(config);
        if (clientId == null) {
          return _mark(
            _GoogleMode.requestFailed,
            'Firebase Google 로그인 설정의 Web client ID 가 형식에 맞지 않습니다',
          );
        }
        _clientId = clientId;
        final String? configured = readJsonString(
          context.resolve(context.paths.json),
          clientIdConfigKey,
        );
        if (configured == clientId) {
          _mode = _GoogleMode.done;
          return const Done('Firebase Google 로그인 켜짐 · Web client ID 기록됨');
        }
        return _mark(
          _GoogleMode.writeClientId,
          'config 의 $clientIdConfigKey 가 Firebase Google 설정과 다릅니다',
        );
    }
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    final target = '${context.paths.json} 의 $clientIdConfigKey';
    return switch (_mode) {
      _GoogleMode.enable => <String>[
        '(실행하면 동의 화면 값 표(앱 이름 · 지원 이메일)를 보이고 고르게 합니다)',
        '(${SignInStep.defaultWebAppNotice})',
        '(임시 설정 파일 $authConfigPath 을 만들어 아래 명령에 넘기고, 실행 뒤 지웁니다)',
        buildDeployCommand(_projectId).render(),
        '(끝나면 Google 로그인 설정을 다시 읽어 Web client ID 를 $target 에 씁니다)',
      ],
      _GoogleMode.writeClientId => <String>[
        '(Firebase Google 로그인 설정의 Web client ID 를 $target 에 씁니다)',
      ],
      _GoogleMode.requestFailed when _failedResult != null => const <String>[
        '(응답 원문을 보입니다)',
      ],
      _GoogleMode.requestFailed ||
      _GoogleMode.unreadable ||
      _GoogleMode.done => const <String>[],
    };
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _GoogleMode.enable => await _applyEnable(context),
      _GoogleMode.writeClientId => _writeClientId(context, _clientId),
      _GoogleMode.requestFailed => Failed(_reason, result: _failedResult),
      _GoogleMode.unreadable => Failed(_reason),
      _GoogleMode.done => const Applied(),
    };
  }

  /// 값 표 확인 뒤 임시 설정 파일로 Google 로그인을 켜고 Web client ID 를 쓴다.
  Future<StepOutcome> _applyEnable(WizardContext context) async {
    final String configPath = context.resolve(context.paths.json);
    final String appName = _readAppName(configPath);
    if (appName.isEmpty) {
      return Failed('${context.paths.json} 에서 $appNameConfigKey 를 읽지 못했습니다');
    }
    final String? suggested = await _readSuggestedEmail(context);
    final bool isOrganization = await _isUnderOrganization(context);
    final IconSpec spec = findIconSpec(token)!;
    final String? supportEmail = _chooseSupportEmail(
      context.terminal,
      appName: appName,
      suggested: suggested,
      isOrganization: isOrganization,
      logoRow: buildIconRow(context, spec),
      logoNote: buildIconNote(spec),
    );
    if (supportEmail == null) return const Declined();
    if (supportEmail.isEmpty) {
      return const Failed('지원 이메일 형식이 맞지 않아 진행하지 않았습니다');
    }

    final file = File(context.resolve(authConfigPath));
    try {
      file.parent.createSync(recursive: true);
      writeFileAtomically(
        file.path,
        buildAuthConfigContent(appName: appName, supportEmail: supportEmail),
      );
      final CommandResult result = await context.runner.stream(
        buildDeployCommand(_projectId, workingDirectory: context.projectRoot),
      );
      if (!result.isSuccess) {
        return Failed('Google 로그인을 켜지 못했습니다', result: result);
      }
    } on FileSystemException catch (e) {
      return Failed('임시 설정 파일을 만들지 못했습니다 — $e');
    } finally {
      _deleteTemporary(context, file);
    }

    final IdpRead read = await readIdpConfig(context, _projectId, idpId);
    switch (read) {
      case IdpReadFailed(:final String reason, :final CommandResult? result):
        return Failed('켠 뒤 $reason', result: result);
      case IdpMissing():
        return const Failed('켠 뒤에도 Firebase Google 로그인 설정이 없습니다');
      case IdpFound(:final Map<String, Object?> config):
        final String? clientId = config['enabled'] == true
            ? _readClientId(config)
            : null;
        if (clientId == null) {
          return const Failed(
            '켠 뒤에도 Firebase Google 로그인이 꺼져 있거나 Web client ID 가 형식에 맞지 '
            '않습니다',
          );
        }
        return _writeClientId(context, clientId);
    }
  }

  /// 값 표를 보이고 지원 이메일을 정한다.
  ///
  /// 표를 다시 보일 때마다 로고 행 [logoRow] 와 노트 [logoNote] 를 함께 보인다.
  /// 입력 끝이면 null, 형식에 맞는 값을 끝내 받지 못하면 빈 문자열을 돌려준다.
  String? _chooseSupportEmail(
    Terminal terminal, {
    required String appName,
    required String? suggested,
    required bool isOrganization,
    required SummaryRow logoRow,
    required String? logoNote,
  }) {
    var email = suggested;
    while (true) {
      _writeValueTable(
        terminal,
        appName: appName,
        email: email,
        isOrganization: isOrganization,
        logoRow: logoRow,
        logoNote: logoNote,
      );
      final int? choice = terminal.choose(choiceQuestion, const <String>[
        proceedOption,
        editEmailOption,
      ]);
      if (choice == null) return null;
      if (choice == 0 && email != null) return email;
      final String? edited = _askValidEmail(terminal, defaultValue: email);
      if (edited == null || edited.isEmpty) return edited;
      email = edited;
    }
  }

  /// 동의 화면 값 표를 보인다 — 조직 아래 프로젝트면 경고 한 줄을 붙인다.
  ///
  /// 셋째 행은 로고 경로 [logoRow], 셋째 노트는 (있으면) 로고 요구 정도
  /// [logoNote] 다.
  static void _writeValueTable(
    Terminal terminal, {
    required String appName,
    required String? email,
    required bool isOrganization,
    required SummaryRow logoRow,
    required String? logoNote,
  }) {
    writeSummary(
      terminal,
      title: summaryTitle,
      rows: <SummaryRow>[
        SummaryRow(appNameRowLabel, appName),
        SummaryRow(supportEmailRowLabel, email ?? unreadEmailValue),
        logoRow,
      ],
      notes: <String>[
        existingBrandNote,
        SignInStep.defaultWebAppNotice,
        ?logoNote,
      ],
    );
    if (isOrganization) terminal.writeLine('  ! $organizationWarning');
  }

  /// 지원 이메일을 형식에 맞을 때까지 [maxInputAttempts] 번까지 묻는다.
  ///
  /// 입력 끝이면 null, 끝까지 틀리면 빈 문자열을 돌려준다.
  static String? _askValidEmail(Terminal terminal, {String? defaultValue}) {
    for (var attempt = 0; attempt < maxInputAttempts; attempt++) {
      final String? answer = terminal.ask(
        emailQuestion,
        defaultValue: defaultValue,
      );
      if (answer == null) return null;
      final String trimmed = answer.trim();
      if (isValidSupportEmail(trimmed)) return trimmed;
      terminal.writeLine(invalidEmailMessage);
    }
    return '';
  }

  /// gcloud 의 지금 계정을 지원 이메일 제안값으로 읽는다 — 없으면 null.
  static Future<String?> _readSuggestedEmail(WizardContext context) async {
    final CommandResult result = await context.runner.capture(accountCommand);
    if (!result.isSuccess) return null;
    final String value = result.stdout.trim();
    return isValidSupportEmail(value) ? value : null;
  }

  /// 프로젝트 상위가 조직 · 폴더인지 읽는다 — 읽지 못하면 false.
  Future<bool> _isUnderOrganization(WizardContext context) async {
    final CommandResult result = await context.runner.capture(
      buildProjectDescribeCommand(_projectId),
    );
    return result.isSuccess && isUnderOrganization(result.stdout);
  }

  /// config 의 [clientIdConfigKey] 에 [clientId] 를 쓴다.
  static StepOutcome _writeClientId(WizardContext context, String clientId) {
    try {
      replaceJsonString(
        context.resolve(context.paths.json),
        clientIdConfigKey,
        clientId,
      );
      return const Applied();
    } on ConfigEditException catch (e) {
      return Failed('Web client ID 를 쓰지 못했습니다 — ${e.message}');
    } on FormatException catch (e) {
      return Failed('Web client ID 를 쓰지 못했습니다 — ${e.message}');
    } on FileSystemException catch (e) {
      return Failed('Web client ID 를 쓰지 못했습니다 — $e');
    }
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_GoogleMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }

  /// 설정의 `clientId` 가 Web client ID 형식이면 돌려준다 — 아니면 null.
  static String? _readClientId(Map<String, Object?> config) {
    final Object? value = config['clientId'];
    return value is String && googleWebClientId.matches(value) ? value : null;
  }

  /// config 의 앱 이름을 읽는다 — 없거나 비면 빈 문자열.
  static String _readAppName(String configPath) {
    try {
      return readJsonString(configPath, appNameConfigKey)?.trim() ?? '';
    } on FileSystemException {
      return '';
    }
  }

  /// 임시 설정 파일이 있으면 지운다 — 지우지 못하면 경로와 함께 직접 지우라고 알린다.
  static void _deleteTemporary(WizardContext context, File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException catch (e) {
      context.terminal.writeLine(
        '  임시 설정 파일을 지우지 못했습니다 — $authConfigPath 를 직접 지우세요 ($e)',
      );
    }
  }
}

/// 직전 검사의 판정.
enum _GoogleMode {
  /// Google 로그인이 꺼져 있거나 없다 — 값 표 확인 뒤 켠다.
  enable,

  /// 켜져 있지만 config 의 Web client ID 가 다르다 — config 만 쓴다.
  writeClientId,

  /// 설정을 읽지 못했다.
  requestFailed,

  /// 프로젝트 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
