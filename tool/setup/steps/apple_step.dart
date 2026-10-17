import 'dart:convert';

import '../command_runner.dart';
import '../firebase_app_files.dart';
import '../providers/idp_config.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';

/// Apple 로그인 iOS 쪽 단계 — Firebase 의 Apple 로그인을 켜고 그 flavor 의 번들
/// ID 를 넣는다.
///
/// 검사는 Identity Toolkit 의 `apple.com` 로그인 수단 설정 GET 이다(응답에 개인
/// 키가 평문으로 실릴 수 있어 [readIdpConfig] 로만 읽는다). 설정이 없으면 만들고,
/// 꺼져 있거나 번들 ID 가 없으면 [bundleIdsUpdateMask] 만 바꾸는 PATCH 로 켜고
/// 기존 번들 ID 뒤에 지금 번들 ID 를 더한다 — Android 쪽 코드 흐름 설정
/// (`clientId` · `codeFlowConfig`)은 건드리지 않는다. App ID 의 capability 는
/// 자동 서명이면 Xcode 가 켜므로 안내([capabilityNotice])만 한다.
final class AppleStep implements Step {
  /// Apple 로그인 iOS 쪽 단계를 만든다.
  AppleStep();

  /// 로그인 수단 표의 토큰 — 단계 id 로도 쓴다.
  static const String token = 'apple';

  /// Firebase 로그인 수단 설정의 IdP ID.
  static const String idpId = 'apple.com';

  /// 단계 제목.
  static const String stepTitle = 'Apple 로그인 — iOS 쪽';

  /// 매뉴얼에서 iOS 서명 capability 를 다루는 절의 머리.
  static const String iosSigningManualHeading =
      '### iOS 서명 — Apple 을 꺼도 필요한 capability';

  /// App ID capability 안내 — 계획 줄 · ✓ 요약에 보인다.
  static final String capabilityNotice =
      'App ID 의 Sign in with Apple capability 는 자동 서명이면 Xcode 가 켭니다 — '
      '${formatManualReference(iosSigningManualHeading)}';

  /// 이미 있는 설정에서 바꾸는 필드 — 코드 흐름 설정은 넣지 않는다.
  static const String bundleIdsUpdateMask =
      'enabled,appleSignInConfig.bundleIds';

  _AppleMode _mode = _AppleMode.unreadable;
  String _reason = '';
  CommandResult? _failedResult;
  String _projectId = '';
  String _bundleId = '';
  List<String> _bundleIds = const <String>[];

  @override
  String get id => token;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['providers', 'configure'];

  // 설정을 켜고 번들 ID 를 더하는 일은 되돌릴 수 있고 값 표가 없다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _AppleMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    final String? bundleId = readBundleId(context.projectRoot, context.flavor);
    if (bundleId == null) {
      return _mark(
        _AppleMode.unreadable,
        '${context.paths.xcconfig} 에서 번들 ID(PRODUCT_BUNDLE_IDENTIFIER)를 '
        '읽지 못했습니다',
      );
    }
    _projectId = projectId;
    _bundleId = bundleId;
    final IdpRead read = await readIdpConfig(context, projectId, idpId);
    switch (read) {
      case IdpReadFailed(:final String reason, :final CommandResult? result):
        return _mark(_AppleMode.requestFailed, reason, result: result);
      case IdpMissing():
        _bundleIds = const <String>[];
        return _mark(_AppleMode.create, 'Firebase 에 Apple 로그인 설정이 없습니다');
      case IdpFound(:final Map<String, Object?> config):
        _bundleIds = readBundleIds(config);
        final isEnabled = config['enabled'] == true;
        final bool hasBundle = _bundleIds.contains(bundleId);
        if (isEnabled && hasBundle) {
          _mode = _AppleMode.done;
          return Done(
            'Firebase Apple 로그인 켜짐 · 번들 ID $bundleId · $capabilityNotice',
          );
        }
        final String reason = switch ((isEnabled, hasBundle)) {
          (false, false) =>
            'Firebase 에서 Apple 로그인이 꺼져 있고 번들 ID $bundleId 가 없습니다',
          (false, _) => 'Firebase 에서 Apple 로그인이 꺼져 있습니다',
          _ => 'Firebase Apple 로그인 설정에 번들 ID $bundleId 가 없습니다',
        };
        return _mark(_AppleMode.patch, reason);
    }
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _AppleMode.create || _AppleMode.patch => <String>[
      _buildWriteRequest().displayCurl(),
      '($capabilityNotice)',
    ],
    _AppleMode.requestFailed when _failedResult != null => const <String>[
      '(응답 원문을 보입니다)',
    ],
    _AppleMode.requestFailed ||
    _AppleMode.unreadable ||
    _AppleMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _AppleMode.create || _AppleMode.patch => await _write(context),
      _AppleMode.requestFailed => Failed(_reason, result: _failedResult),
      _AppleMode.unreadable => Failed(_reason),
      _AppleMode.done => const Applied(),
    };
  }

  /// 설정 [config] 의 `appleSignInConfig.bundleIds` 에서 문자열만 순서대로 꺼낸다.
  ///
  /// 자리가 없거나 목록이 아니면 빈 목록.
  static List<String> readBundleIds(Map<String, Object?> config) {
    final Object? appleConfig = config['appleSignInConfig'];
    if (appleConfig is! Map<String, Object?>) return const <String>[];
    final Object? bundleIds = appleConfig['bundleIds'];
    if (bundleIds is! List<Object?>) return const <String>[];
    return <String>[
      for (final Object? value in bundleIds)
        if (value is String) value,
    ];
  }

  /// 판정에 맞는 쓰기 요청(생성 · PATCH)을 보내고 결과를 돌려준다.
  Future<StepOutcome> _write(WizardContext context) async {
    final RestResponse response = await sendIdpRequest(
      context,
      _buildWriteRequest(),
    );
    if (response.isOk) return const Applied();
    return Failed(
      'Firebase Apple 로그인 설정을 쓰지 못했습니다 — ${describeRestStatus(response)}',
      result: toFailureResult(response, redactor: context.redactor),
    );
  }

  /// 지금 판정의 쓰기 요청을 만든다 — 본문에 비밀 값이 없어 표시형도 같다.
  RestRequest _buildWriteRequest() {
    final merged = <String>[
      ..._bundleIds,
      if (!_bundleIds.contains(_bundleId)) _bundleId,
    ];
    final String body = jsonEncode(<String, Object?>{
      'enabled': true,
      'appleSignInConfig': <String, Object?>{'bundleIds': merged},
    });
    return _mode == _AppleMode.create
        ? buildIdpCreateRequest(
            _projectId,
            idpId,
            body: body,
            bodyDisplay: body,
          )
        : buildIdpPatchRequest(
            _projectId,
            idpId,
            updateMask: bundleIdsUpdateMask,
            body: body,
            bodyDisplay: body,
          );
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_AppleMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// iOS 쪽 단계의 직전 검사 판정.
enum _AppleMode {
  /// 설정이 없어 만든다.
  create,

  /// 꺼져 있거나 번들 ID 가 없어 PATCH 한다.
  patch,

  /// 설정을 읽지 못했다 — 실행하면 실패.
  requestFailed,

  /// 프로젝트 ID · 번들 ID 를 읽지 못했다 — 실행하면 실패.
  unreadable,

  /// 이미 켜져 있고 번들 ID 가 있다.
  done,
}
