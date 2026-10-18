import 'dart:convert';

import '../command_runner.dart';
import '../firebase_app_files.dart';
import '../providers/apple_key_input.dart';
import '../providers/fingerprints.dart';
import '../providers/key_formats.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'app_check_step.dart';
import 'apple_android_step.dart';
import 'billing_step.dart';

/// App Check DeviceCheck 단계 — Apple 키(`.p8`)와 Team ID 를 Firebase 에 넣어
/// release 빌드의 iOS 증명이 통과하게 한다.
///
/// 검사는 DeviceCheck 설정 GET 의 `privateKeySet` · `keyId` 다 — 키를 넣지 않은
/// 앱도 200 을 돌려주므로 응답 코드만으로 판정하지 않는다. 이번 실행에서 키를
/// 넣었으면 재검사는 등록된 Key ID 가 넣은 값과 같은지까지 본다. 실행은 Apple 키
/// (같은 실행에서 Sign in with Apple 에 쓴 키가 있으면 같은 키를 제안)와 Team ID
/// 를 받아 iOS 앱의 Team ID 를 쓰고 DeviceCheck 설정에 키를 넣는다. 화면 · 기록의
/// 요청 본문에는 `.p8` 내용 대신 [AppleAndroidStep.privateKeyPlaceholder] 를
/// 보인다. 미룰 수 있는 단계다.
final class DeviceCheckStep implements DeferrableStep {
  /// DeviceCheck 단계를 만든다.
  DeviceCheckStep();

  /// 단계 id.
  static const String stepId = 'device_check';

  /// 단계 제목.
  static const String stepTitle = 'App Check — DeviceCheck';

  /// 실행 전 계획 줄의 안내.
  static const String plannedNote =
      '(DeviceCheck 에 쓸 Apple 키(.p8 경로 · Key ID)와 Team ID 를 받아 '
      'Firebase 에 넣습니다 — 같은 실행에서 넣은 키가 있으면 같은 키를 '
      '제안합니다)';

  /// [projectId] 의 iOS 앱 [iosAppId] DeviceCheck 설정 주소.
  static String _buildConfigUrl(String projectId, String iosAppId) =>
      '${AppCheckStep.appCheckApiPrefix}projects/$projectId/apps/$iosAppId/'
      'deviceCheckConfig';

  /// [projectId] 의 iOS 앱 [iosAppId] 관리 주소.
  static String _buildIosAppUrl(String projectId, String iosAppId) =>
      '${firebaseManagementApiPrefix}projects/$projectId/iosApps/$iosAppId';

  /// iOS 앱 [iosAppId] 의 DeviceCheck 설정을 읽는 요청을 만든다.
  static RestRequest buildGetRequest(String projectId, String iosAppId) =>
      RestRequest(
        method: 'GET',
        url: Uri.parse(_buildConfigUrl(projectId, iosAppId)),
        quotaProject: projectId,
      );

  /// iOS 앱 [iosAppId] 의 DeviceCheck 설정에 키를 넣는 요청을 만든다.
  ///
  /// 실제 본문에는 [privateKey](`.p8` 내용)를 싣고, 화면 · 기록에는 그 자리에
  /// [AppleAndroidStep.privateKeyPlaceholder] 를 보인다. 응답은 민감 응답이다.
  static RestRequest buildPatchRequest(
    String projectId,
    String iosAppId, {
    required String keyId,
    required String privateKey,
  }) => RestRequest(
    method: 'PATCH',
    url: Uri.parse(
      '${_buildConfigUrl(projectId, iosAppId)}'
      '?updateMask=key_id,private_key',
    ),
    quotaProject: projectId,
    body: jsonEncode(<String, String>{
      'keyId': keyId,
      'privateKey': privateKey,
    }),
    bodyDisplay: jsonEncode(<String, String>{
      'keyId': keyId,
      'privateKey': AppleAndroidStep.privateKeyPlaceholder,
    }),
    isResponseSensitive: true,
  );

  /// iOS 앱 [iosAppId] 에 Apple Team ID [teamId] 를 쓰는 요청을 만든다.
  ///
  /// DeviceCheck 검증은 앱에 등록된 Team ID 를 쓴다.
  static RestRequest buildTeamIdPatchRequest(
    String projectId,
    String iosAppId,
    String teamId,
  ) => RestRequest(
    method: 'PATCH',
    url: Uri.parse(
      '${_buildIosAppUrl(projectId, iosAppId)}?updateMask=team_id',
    ),
    quotaProject: projectId,
    body: jsonEncode(<String, String>{'teamId': teamId}),
  );

  /// iOS 앱 [iosAppId] 의 등록 정보(Team ID 포함)를 읽는 요청을 만든다.
  static RestRequest buildIosAppGetRequest(String projectId, String iosAppId) =>
      RestRequest(
        method: 'GET',
        url: Uri.parse(_buildIosAppUrl(projectId, iosAppId)),
        quotaProject: projectId,
      );

  _DeviceCheckMode _mode = _DeviceCheckMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _iosAppId = '';
  CommandResult? _failedResult;

  // 이번 실행에서 넣은 Key ID — 재검사가 등록된 값과 비교한다.
  String? _enteredKeyId;

  @override
  String get id => stepId;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['configure', 'apis'];

  @override
  String get proceedLabel => '진행';

  @override
  String get deferLabel => '지금 안 함';

  // 키 · Team ID 는 다시 넣으면 바뀌고 비용이 들지 않는다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _DeviceCheckMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    final String? iosAppId = _readIosAppId(context);
    if (iosAppId == null) {
      return _mark(
        _DeviceCheckMode.unreadable,
        '앱 등록 설정 파일에서 iOS 앱 ID 를 읽지 못했습니다 — '
        '앱 등록 단계를 먼저 끝내야 합니다',
      );
    }
    _projectId = projectId;
    _iosAppId = iosAppId;
    final RestResponse response = await context.rest.send(
      buildGetRequest(projectId, iosAppId),
    );
    final Object? json = response.isOk ? response.decodeJson() : null;
    if (json is! Map<String, Object?>) {
      return _mark(
        _DeviceCheckMode.failed,
        'DeviceCheck 설정을 읽지 못했습니다 — ${describeRestStatus(response)}',
        result: toFailureResult(response, redactor: context.redactor),
      );
    }
    final Object? registeredKeyId = json['keyId'];
    final bool isKeySet =
        json['privateKeySet'] == true &&
        registeredKeyId is String &&
        appleKeyId.matches(registeredKeyId);
    if (!isKeySet) {
      return _mark(
        _DeviceCheckMode.register,
        'DeviceCheck 에 Apple 키가 등록되지 않았습니다',
      );
    }
    final String? entered = _enteredKeyId;
    if (entered != null && registeredKeyId != entered) {
      return _mark(
        _DeviceCheckMode.register,
        '등록된 Key ID($registeredKeyId)가 넣은 Key ID($entered)와 다릅니다',
      );
    }
    _mode = _DeviceCheckMode.done;
    return Done('Key ID $registeredKeyId');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _DeviceCheckMode.register => <String>[
      plannedNote,
      buildTeamIdPatchRequest(_projectId, _iosAppId, '<Team ID>').displayCurl(),
      buildPatchRequest(
        _projectId,
        _iosAppId,
        keyId: '<Key ID>',
        privateKey: '',
      ).displayCurl(),
    ],
    _DeviceCheckMode.failed when _failedResult != null => const <String>[
      '(응답 원문을 보입니다)',
    ],
    _DeviceCheckMode.failed ||
    _DeviceCheckMode.unreadable ||
    _DeviceCheckMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _DeviceCheckMode.unreadable || _DeviceCheckMode.failed:
        return Failed(_reason, result: _failedResult);
      case _DeviceCheckMode.done:
        return const Applied();
      case _DeviceCheckMode.register:
        break;
    }
    final AppleKey? key = await askAppleKey(
      context,
      use: AppleKeyUse.deviceCheck,
    );
    if (key == null) return const Declined();
    context.redactor.register(key.privateKey);
    final String? teamId = await resolveTeamId(context);
    if (teamId == null) return const Declined();

    final RestResponse team = await context.rest.send(
      buildTeamIdPatchRequest(_projectId, _iosAppId, teamId),
    );
    if (!team.isOk) {
      return Failed(
        'iOS 앱에 Team ID 를 쓰지 못했습니다 — ${describeRestStatus(team)}',
        result: toFailureResult(team, redactor: context.redactor),
      );
    }
    final RestResponse response = await context.rest.send(
      buildPatchRequest(
        _projectId,
        _iosAppId,
        keyId: key.keyId,
        privateKey: key.privateKey,
      ),
    );
    if (!response.isOk) {
      return Failed(
        'DeviceCheck 에 Apple 키를 넣지 못했습니다 — ${describeRestStatus(response)}',
        result: toFailureResult(response, redactor: context.redactor),
      );
    }
    _enteredKeyId = key.keyId;
    context.session.hasEnteredDeviceCheckKey = true;
    return const Applied();
  }

  /// 이번 flavor 의 iOS 앱 ID 를 읽고 가림 함수에 등록한다 — 못 읽으면 null.
  static String? _readIosAppId(WizardContext context) {
    final files = FirebaseAppFiles.read(
      context.projectRoot,
      flavor: context.flavor,
    );
    if (files.isOptionsPlaceholder) return null;
    final String? iosAppId = files.iosAppId;
    if (iosAppId == null) return null;
    context.redactor.register(iosAppId);
    return iosAppId;
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(
    _DeviceCheckMode mode,
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
enum _DeviceCheckMode {
  /// 키 · Team ID 를 받아 넣는다.
  register,

  /// 설정 읽기가 실패했다.
  failed,

  /// 프로젝트 ID · 앱 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
