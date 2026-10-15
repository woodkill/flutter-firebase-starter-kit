import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'user_files_step.dart';

/// 로그인 수단 단계 — 이메일/비밀번호 로그인과 익명 로그인을 함께 켠다.
///
/// 검사는 Identity Toolkit 관리 API 의 로그인 설정 GET 이고, 켜기는 같은 주소의
/// PATCH 다(`updateMask` 로 세 필드만). 저장소의 `firebase.json` 은 건드리지 않는다.
/// 새 프로젝트는 로그인 설정이 아직 없어 GET 이 404 `CONFIGURATION_NOT_FOUND` 를
/// 내므로, 그때는 저장소 밖에 두는 임시 설정 파일([authConfigPath])로 Firebase
/// CLI 의 auth 배포를 실행해 초기화한 뒤 다시 읽는다. 임시 파일은 성공 · 실패와
/// 관계없이 실행 뒤 지운다. Identity Platform 업그레이드 API 는 부르지 않는다.
final class SignInStep implements Step {
  /// 로그인 수단 단계를 만든다.
  SignInStep();

  /// 단계 제목.
  static const String stepTitle = '로그인 수단 (이메일 · 익명)';

  /// 로그인 설정 관리 API 주소의 앞부분 — 뒤에 `<프로젝트 ID>/config` 가 붙는다.
  static const String configUrlPrefix =
      'https://identitytoolkit.googleapis.com/admin/v2/projects/';

  /// PATCH 가 바꾸는 필드 — 이 밖의 필드는 그대로 둔다.
  static const String updateMask =
      'signIn.email.enabled,signIn.email.passwordRequired,'
      'signIn.anonymous.enabled';

  /// PATCH 본문 — 이메일/비밀번호(비밀번호 필수)와 익명을 켠다.
  static const String enableBody =
      '{"signIn":{"email":{"enabled":true,"passwordRequired":true},'
      '"anonymous":{"enabled":true}}}';

  /// 로그인 설정이 아직 없을 때 응답 본문에 실리는 표시.
  static const String notInitializedMarker = 'CONFIGURATION_NOT_FOUND';

  /// 초기화에 쓰는 임시 설정 파일(저장소 루트 기준 · 추적하지 않는 디렉터리).
  static const String authConfigPath = '.setup/auth-config.json';

  /// 임시 설정 파일 내용 — 이메일/비밀번호와 익명 로그인을 켠다.
  static const String authConfigContent =
      '{"auth":{"providers":{"emailPassword":true,"anonymous":true}}}';

  /// 초기화 전에 알리는 부수효과.
  static const String defaultWebAppNotice =
      '프로젝트에 Web 앱이 없으면 Firebase CLI 가 「Default Web App」 을 하나 만듭니다.';

  /// [projectId] 의 로그인 설정 주소를 만든다.
  static Uri buildConfigUrl(String projectId) =>
      Uri.parse('$configUrlPrefix$projectId/config');

  /// [projectId] 의 로그인 설정을 읽는 요청을 만든다.
  ///
  /// 응답에 프로젝트 API 키 같은 설정 값이 함께 실리므로 민감 응답으로 둔다.
  static RestRequest buildGetRequest(String projectId) => RestRequest(
    method: 'GET',
    url: buildConfigUrl(projectId),
    quotaProject: projectId,
    isResponseSensitive: true,
  );

  /// [projectId] 의 이메일/비밀번호 · 익명 로그인을 켜는 요청을 만든다.
  static RestRequest buildPatchRequest(String projectId) => RestRequest(
    method: 'PATCH',
    url: Uri.parse('$configUrlPrefix$projectId/config?updateMask=$updateMask'),
    quotaProject: projectId,
    body: enableBody,
    isResponseSensitive: true,
  );

  /// [projectId] 의 로그인 설정을 임시 설정 파일로 초기화하는 명령을 만든다.
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

  _SignInMode _mode = _SignInMode.unreadable;
  String _reason = '';
  String _projectId = '';
  CommandResult? _failedResult;

  @override
  String get id => 'sign_in';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['apis'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _SignInMode.unreadable,
        '${UserFilesStep.jsonUserPath} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final RestResponse response = await context.rest.send(
      buildGetRequest(projectId),
    );
    if (response.isOk) {
      final List<String>? disabled = _listDisabled(response);
      if (disabled == null) {
        return _mark(_SignInMode.requestFailed, '로그인 설정 응답을 해석하지 못했습니다');
      }
      if (disabled.isEmpty) {
        _mode = _SignInMode.done;
        return const Done('이메일/비밀번호 · 익명 로그인 켜짐');
      }
      return _mark(_SignInMode.enable, '꺼진 로그인 수단: ${disabled.join(' · ')}');
    }
    if (response.statusCode == 404 &&
        response.body.contains(notInitializedMarker)) {
      return _mark(
        _SignInMode.initialize,
        '로그인 설정이 초기화되지 않았습니다 — 새 프로젝트는 한 번 초기화합니다',
      );
    }
    return _mark(
      _SignInMode.requestFailed,
      '로그인 설정을 읽지 못했습니다 — ${describeRestStatus(response)}',
      result: toFailureResult(response),
    );
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _SignInMode.enable => <String>[buildPatchRequest(_projectId).displayCurl()],
    _SignInMode.initialize => <String>[
      '($defaultWebAppNotice)',
      '(임시 설정 파일 $authConfigPath 을 만들어 아래 명령에 넘기고, 실행 뒤 지웁니다)',
      buildDeployCommand(_projectId).render(),
      '(끝나면 로그인 설정을 다시 읽고, 꺼진 수단이 남아 있으면 아래 요청으로 켭니다)',
      buildPatchRequest(_projectId).displayCurl(),
    ],
    _SignInMode.requestFailed => <String>['(응답 원문을 보입니다)'],
    _SignInMode.unreadable || _SignInMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _SignInMode.enable => await _sendPatch(context),
      _SignInMode.initialize => await _applyInitialize(context),
      _SignInMode.requestFailed => Failed(_reason, result: _failedResult),
      _SignInMode.unreadable => Failed(_reason),
      _SignInMode.done => const Applied(),
    };
  }

  /// 임시 설정 파일로 로그인 설정을 초기화한 뒤 다시 읽어 꺼진 수단을 켠다.
  Future<StepOutcome> _applyInitialize(WizardContext context) async {
    final File file = File(context.resolve(authConfigPath));
    try {
      file.parent.createSync(recursive: true);
      writeFileAtomically(file.path, authConfigContent);
      final CommandResult result = await context.runner.stream(
        buildDeployCommand(_projectId, workingDirectory: context.projectRoot),
      );
      if (!result.isSuccess) {
        return Failed('로그인 설정을 초기화하지 못했습니다', result: result);
      }
    } on FileSystemException catch (e) {
      return Failed('임시 설정 파일을 만들지 못했습니다 — $e');
    } finally {
      _deleteTemporary(context, file);
    }

    final RestResponse response = await context.rest.send(
      buildGetRequest(_projectId),
    );
    if (!response.isOk) {
      return Failed(
        '초기화 뒤에도 로그인 설정을 읽지 못했습니다 — ${describeRestStatus(response)}',
        result: toFailureResult(response),
      );
    }
    final List<String>? disabled = _listDisabled(response);
    if (disabled == null) return const Failed('로그인 설정 응답을 해석하지 못했습니다');
    if (disabled.isEmpty) return const Applied();
    return _sendPatch(context);
  }

  /// 이메일/비밀번호 · 익명을 켜는 PATCH 를 보낸다.
  Future<StepOutcome> _sendPatch(WizardContext context) async {
    final RestResponse response = await context.rest.send(
      buildPatchRequest(_projectId),
    );
    if (response.isOk) return const Applied();
    return Failed(
      '로그인 수단을 켜지 못했습니다 — ${describeRestStatus(response)}',
      result: toFailureResult(response),
    );
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_SignInMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }

  /// 로그인 설정에서 꺼진 수단 이름을 모은다 — 응답이 객체가 아니면 null.
  ///
  /// 필드가 빠져 있으면 꺼진 것으로 본다.
  static List<String>? _listDisabled(RestResponse response) {
    final Object? decoded = response.decodeJson();
    if (decoded is! Map<String, Object?>) return null;
    final Map<String, Object?> signIn = _readObject(decoded, 'signIn');
    final Map<String, Object?> email = _readObject(signIn, 'email');
    final Map<String, Object?> anonymous = _readObject(signIn, 'anonymous');
    return <String>[
      if (email['enabled'] != true) '이메일/비밀번호',
      if (email['enabled'] == true && email['passwordRequired'] != true)
        '이메일 비밀번호 필수',
      if (anonymous['enabled'] != true) '익명',
    ];
  }

  /// [map] 의 [key] 가 객체면 돌려주고, 아니면 빈 객체를 돌려준다.
  static Map<String, Object?> _readObject(
    Map<String, Object?> map,
    String key,
  ) {
    final Object? value = map[key];
    return value is Map<String, Object?> ? value : const <String, Object?>{};
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
enum _SignInMode {
  /// 꺼진 수단이 있다 — PATCH 로 켠다.
  enable,

  /// 로그인 설정이 없다 — 임시 설정 파일로 초기화한다.
  initialize,

  /// 로그인 설정을 읽지 못했다.
  requestFailed,

  /// 프로젝트 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
