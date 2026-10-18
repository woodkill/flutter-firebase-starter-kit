import 'dart:convert';

import '../command_runner.dart';
import '../firebase_app_files.dart';
import '../flavor.dart';
import '../providers/fingerprints.dart';
import '../providers/keyed_provider_step.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'apis_step.dart';
import 'app_check_step.dart';
import 'billing_step.dart';

/// App Check Play Integrity 단계 — release 빌드의 Android 증명 판정 기준을
/// flavor 별로 맞춘다.
///
/// dev · stg 는 Play 밖 설치를 허용한다: Play Integrity API 를 켜고, 디버그
/// 서명 키의 SHA-256 을 Firebase Android 앱에 등록하고, 설정을 「인식되지 않은
/// 판 허용 · 기기 무결성」 으로 바꾼다. prod 는 판정 기준을 바꾸지 않는다(기본값
/// = Play 가 인식한 앱만) — API 를 켜고 Play 앱 서명 키의 SHA-256 을 입력받아
/// 등록한다. 지문을 계산할 수 없는 기기에서는 SHA-256 등록만 남았을 때 할 수 없는
/// 줄로 둔다. 미룰 수 있는 단계라 「지금 안 함」 이면 그 실행에서만 건너뛴다.
///
/// API 켜기는 미룰 수 있는 단계라 [ApisStep.requiredServices] 에 넣지 않고
/// 여기서 [ApisStep.buildEnableCommand] 로 켠다.
final class PlayIntegrityStep implements DeferrableStep {
  /// Play Integrity 단계를 만든다.
  PlayIntegrityStep();

  /// 단계 id.
  static const String stepId = 'play_integrity';

  /// 단계 제목.
  static const String stepTitle = 'App Check — Play Integrity';

  /// Play Integrity API 의 서비스 이름.
  static const String serviceName = 'playintegrity.googleapis.com';

  /// dev · stg 의 최소 기기 판정 수준.
  static const String relaxedDeviceRecognitionLevel = 'MEETS_DEVICE_INTEGRITY';

  /// dev · stg 설정 PATCH 가 바꾸는 필드.
  static const String patchUpdateMask = 'app_integrity,device_integrity';

  /// 지문을 계산할 수 없어 SHA-256 등록만 남았을 때의 사유.
  static const String fingerprintDeferredReason =
      '$unavailableFingerprintGuide — Play Integrity 에는 SHA-256 지문이 '
      '있어야 합니다';

  /// dev · stg 설정을 바꾼 뒤의 안내.
  static const String verdictDelayNotice =
      '설정은 바로 바뀌지만 앱 판정에는 1~2분 걸립니다 — 그 뒤에 release 빌드로 '
      '확인하세요';

  /// prod 의 Play 앱 서명 키 안내.
  static const String prodSigningKeyGuide =
      'Play 에 올린 뒤 Play 앱 서명 키의 SHA-256 을 등록해야 합니다 — 업로드 키가 '
      '아닙니다';

  /// prod 의 Play 앱 서명 키 SHA-256 질문.
  static const String signingKeyQuestion =
      'Play 앱 서명 키 SHA-256 (콜론 포함 가능 · 빈 값 = 지금 안 함)';

  /// prod 실행 전 계획 줄의 안내.
  static const String prodPlannedNote =
      '(Play 앱 서명 키의 SHA-256 을 받아 등록합니다 — prod 판정 기준은 바꾸지 '
      '않습니다)';

  /// prod 설정이 이미 Play 밖 설치를 허용할 때의 사유.
  static const String prodRelaxedReason =
      'prod 의 Play Integrity 설정이 Play 밖 설치를 허용합니다 — 위저드는 prod '
      '설정을 바꾸지 않습니다';

  /// [projectId] 의 Android 앱 [androidAppId] Play Integrity 설정 주소.
  static String _buildConfigUrl(String projectId, String androidAppId) =>
      '${AppCheckStep.appCheckApiPrefix}projects/$projectId/apps/'
      '$androidAppId/playIntegrityConfig';

  /// Android 앱 [androidAppId] 의 Play Integrity 설정을 읽는 요청을 만든다.
  static RestRequest buildGetRequest(String projectId, String androidAppId) =>
      RestRequest(
        method: 'GET',
        url: Uri.parse(_buildConfigUrl(projectId, androidAppId)),
        quotaProject: projectId,
      );

  /// Android 앱 [androidAppId] 를 dev · stg 판정 기준(Play 밖 설치 허용 · 기기
  /// 무결성)으로 바꾸는 요청을 만든다.
  static RestRequest buildPatchRequest(String projectId, String androidAppId) =>
      RestRequest(
        method: 'PATCH',
        url: Uri.parse(
          '${_buildConfigUrl(projectId, androidAppId)}'
          '?updateMask=$patchUpdateMask',
        ),
        quotaProject: projectId,
        body: jsonEncode(<String, Object?>{
          'appIntegrity': <String, Object?>{'allowUnrecognizedVersion': true},
          'deviceIntegrity': <String, Object?>{
            'minDeviceRecognitionLevel': relaxedDeviceRecognitionLevel,
          },
        }),
      );

  /// SHA-256 입력을 Firebase 가 받는 형식(소문자 hex 64자)으로 바꾼다.
  ///
  /// 앞뒤 공백 · 콜론을 떼고 소문자로 바꾼 값이 64자 hex 가 아니면 null.
  static String? normalizeSha256(String input) {
    final String value = normalizeShaHash(input);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(value) ? value : null;
  }

  _PlayMode _mode = _PlayMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _androidAppId = '';
  String _debugSha256 = '';
  bool _isApiMissing = false;
  bool _isPatchMissing = false;
  bool _isShaMissing = false;
  CommandResult? _failedResult;

  // 직전 SHA 목록 읽기 실패의 판정.
  CheckResult _lastFailure = const Todo('');

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

  // 판정 기준 · 지문 등록은 다시 바꿀 수 있고 비용이 들지 않는다.
  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _markUnreadable('${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다');
    }
    final String? androidAppId = _readAndroidAppId(context);
    if (androidAppId == null) {
      return _markUnreadable(
        '앱 등록 설정 파일에서 Android 앱 ID 를 읽지 못했습니다 — '
        '앱 등록 단계를 먼저 끝내야 합니다',
      );
    }
    _projectId = projectId;
    _androidAppId = androidAppId;

    final CommandResult list = await context.runner.capture(
      ApisStep.buildEnabledListCommand(projectId),
    );
    if (!list.isSuccess) {
      return _markFailed('$projectId 에서 켜진 API 목록을 읽지 못했습니다', list);
    }
    _isApiMissing = !list.stdout
        .split('\n')
        .any((String line) => line.trim() == serviceName);

    final RestResponse config = await context.rest.send(
      buildGetRequest(projectId, androidAppId),
    );
    final Map<String, Object?>? json = _decodeObject(config);
    if (json == null) {
      return _markFailed(
        'Play Integrity 설정을 읽지 못했습니다 — ${describeRestStatus(config)}',
        toFailureResult(config, redactor: context.redactor),
      );
    }
    final DebugFingerprints fingerprints = await readDebugFingerprints(context);
    _debugSha256 = fingerprints is FingerprintsAvailable
        ? normalizeShaHash(fingerprints.sha256Hex)
        : '';
    return context.flavor == Flavor.prod
        ? await _checkProd(context, json)
        : await _checkRelaxed(context, json);
  }

  /// dev · stg 판정 — API · 완화 설정 · 디버그 SHA-256 을 본다.
  Future<CheckResult> _checkRelaxed(
    WizardContext context,
    Map<String, Object?> config,
  ) async {
    _isPatchMissing = !_isRelaxed(config);
    _isShaMissing = false;
    if (_debugSha256.isNotEmpty) {
      final Set<String>? hashes = await _readShaHashes(context);
      if (hashes == null) return _lastFailure;
      _isShaMissing = !hashes.contains(_debugSha256);
    }
    if (_isApiMissing || _isPatchMissing || _isShaMissing) {
      return _markTodo(<String>[
        if (_isApiMissing) '$serviceName 켜기',
        if (_isShaMissing) '디버그 SHA-256 등록',
        if (_isPatchMissing) 'Play 밖 설치 허용 설정',
      ]);
    }
    if (_debugSha256.isEmpty) {
      _mode = _PlayMode.deferred;
      return const Deferred(fingerprintDeferredReason);
    }
    _mode = _PlayMode.done;
    return const Done('Play 밖 설치 허용 · 기기 무결성 · 디버그 SHA-256 등록됨');
  }

  /// prod 판정 — API · 기본 설정 · Play 앱 서명 키 SHA-256 을 본다.
  Future<CheckResult> _checkProd(
    WizardContext context,
    Map<String, Object?> config,
  ) async {
    if (_isUnrecognizedAllowed(config)) {
      _mode = _PlayMode.deferred;
      return const Deferred(prodRelaxedReason);
    }
    final Set<String>? hashes = await _readShaHashes(context);
    if (hashes == null) return _lastFailure;
    _isPatchMissing = false;
    _isShaMissing = !hashes.any(
      (String hash) => hash.length == 64 && hash != _debugSha256,
    );
    if (_isApiMissing || _isShaMissing) {
      return _markTodo(<String>[
        if (_isApiMissing) '$serviceName 켜기',
        if (_isShaMissing) 'Play 앱 서명 키 SHA-256 등록',
      ]);
    }
    _mode = _PlayMode.done;
    return const Done('Play 가 인식한 앱만 · Play 앱 서명 키 SHA-256 등록됨');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _PlayMode.apply => <String>[
      if (_isApiMissing)
        ApisStep.buildEnableCommand(_projectId, <String>[serviceName]).render(),
      if (_isShaMissing && context.flavor == Flavor.prod) ...<String>[
        prodPlannedNote,
        RestRequest(
          method: 'POST',
          url: buildShaUrl(_projectId, _androidAppId),
          quotaProject: _projectId,
          body: jsonEncode(<String, String>{
            'shaHash': '<Play 앱 서명 키 SHA-256>',
            'certType': shaCertTypeSha256,
          }),
        ).displayCurl(),
      ],
      if (_isShaMissing && context.flavor != Flavor.prod)
        _buildShaCreateRequest(_debugSha256).displayCurl(),
      if (_isPatchMissing)
        buildPatchRequest(_projectId, _androidAppId).displayCurl(),
      if (_isPatchMissing && _debugSha256.isEmpty)
        '(지문을 계산할 수 없어 SHA-256 등록은 남습니다)',
    ],
    _PlayMode.failed when _failedResult != null => const <String>[
      '(응답 원문을 보입니다)',
    ],
    _PlayMode.failed ||
    _PlayMode.unreadable ||
    _PlayMode.deferred ||
    _PlayMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _PlayMode.unreadable || _PlayMode.failed:
        return Failed(_reason, result: _failedResult);
      case _PlayMode.deferred || _PlayMode.done:
        return const Applied();
      case _PlayMode.apply:
        break;
    }
    if (_isApiMissing) {
      final CommandResult result = await context.runner.stream(
        ApisStep.buildEnableCommand(_projectId, <String>[serviceName]),
      );
      if (!result.isSuccess) {
        return Failed('$serviceName 을 켜지 못했습니다', result: result);
      }
    }
    if (context.flavor == Flavor.prod) {
      return _isShaMissing ? await _applyProdSha(context) : const Applied();
    }
    if (_isShaMissing) {
      final StepOutcome? failure = await _createSha(context, _debugSha256);
      if (failure != null) return failure;
    }
    if (_isPatchMissing) {
      final RestResponse response = await context.rest.send(
        buildPatchRequest(_projectId, _androidAppId),
      );
      if (!response.isOk) {
        return Failed(
          'Play Integrity 설정을 바꾸지 못했습니다 — ${describeRestStatus(response)}',
          result: toFailureResult(response, redactor: context.redactor),
        );
      }
      context.terminal.writeLine('  $verdictDelayNotice');
    }
    return const Applied();
  }

  /// prod 의 Play 앱 서명 키 SHA-256 을 안내 뒤 받아 등록한다.
  ///
  /// 빈 값은 미루기, 입력 끝 · [maxKeyAttempts] 회 형식 틀림은 거절이다.
  Future<StepOutcome> _applyProdSha(WizardContext context) async {
    context.terminal.writeLine('  $prodSigningKeyGuide');
    for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
      final String? answer = context.terminal.ask(signingKeyQuestion);
      if (answer == null) return const Declined();
      final String trimmed = answer.trim();
      if (trimmed.isEmpty) return DeferredByUser(deferLabel);
      final String? sha256 = normalizeSha256(trimmed);
      if (sha256 == null) {
        context.terminal.writeLine(
          '  SHA-256 형식이 맞지 않습니다 — 16진수 64자(콜론 포함 가능)',
        );
        continue;
      }
      return await _createSha(context, sha256) ?? const Applied();
    }
    return const Declined();
  }

  /// [sha256] 을 SHA_256 종류로 등록한다 — 실패면 실패 결과, 성공이면 null.
  Future<StepOutcome?> _createSha(WizardContext context, String sha256) async {
    final RestResponse response = await context.rest.send(
      _buildShaCreateRequest(sha256),
    );
    if (response.isOk) return null;
    return Failed(
      'SHA-256 을 등록하지 못했습니다 — ${describeRestStatus(response)}',
      result: toFailureResult(response, redactor: context.redactor),
    );
  }

  /// [sha256] 을 등록하는 요청을 만든다.
  RestRequest _buildShaCreateRequest(String sha256) => buildShaCreateRequest(
    _projectId,
    _androidAppId,
    shaHash: sha256,
    certType: shaCertTypeSha256,
  );

  /// SHA 인증서 목록을 읽는다 — 읽지 못하면 실패 판정을 두고 null.
  Future<Set<String>?> _readShaHashes(WizardContext context) async {
    final RestResponse response = await context.rest.send(
      buildShaListRequest(_projectId, _androidAppId),
    );
    final Set<String>? hashes = parseShaHashes(response);
    if (hashes == null) {
      _lastFailure = _markFailed(
        'Firebase Android 앱의 SHA 인증서 목록을 읽지 못했습니다 — '
        '${describeRestStatus(response)}',
        toFailureResult(response, redactor: context.redactor),
      );
    }
    return hashes;
  }

  /// 이번 flavor 의 Android 앱 ID 를 읽고 가림 함수에 등록한다 — 못 읽으면 null.
  static String? _readAndroidAppId(WizardContext context) {
    final String? packageName = readAndroidPackage(
      context.projectRoot,
      context.flavor,
    );
    if (packageName == null) return null;
    final files = FirebaseAppFiles.read(
      context.projectRoot,
      flavor: context.flavor,
    );
    if (files.isOptionsPlaceholder) return null;
    final String? androidAppId = files.androidAppIdFor(packageName);
    if (androidAppId == null) return null;
    context.redactor.register(androidAppId);
    return androidAppId;
  }

  /// 설정이 dev · stg 판정 기준(Play 밖 설치 허용 · 기기 무결성)이면 true.
  static bool _isRelaxed(Map<String, Object?> config) =>
      _isUnrecognizedAllowed(config) &&
      switch (config['deviceIntegrity']) {
        {'minDeviceRecognitionLevel': relaxedDeviceRecognitionLevel} => true,
        _ => false,
      };

  /// 설정이 Play 가 인식하지 않은 판을 허용하면 true.
  static bool _isUnrecognizedAllowed(Map<String, Object?> config) =>
      switch (config['appIntegrity']) {
        {'allowUnrecognizedVersion': true} => true,
        _ => false,
      };

  /// 성공 응답의 JSON 객체 — 실패 · 모양이 다르면 null.
  static Map<String, Object?>? _decodeObject(RestResponse response) {
    if (!response.isOk) return null;
    final Object? json = response.decodeJson();
    return json is Map<String, Object?> ? json : null;
  }

  /// 남은 일 [parts] 로 할 일 판정을 만든다.
  CheckResult _markTodo(List<String> parts) {
    _mode = _PlayMode.apply;
    _reason = '할 일: ${parts.join(' · ')}';
    _failedResult = null;
    return Todo(_reason);
  }

  /// 읽지 못한 판정을 만든다.
  CheckResult _markUnreadable(String reason) {
    _mode = _PlayMode.unreadable;
    _reason = reason;
    _failedResult = null;
    return Todo(reason);
  }

  /// 요청 실패 판정을 만든다.
  CheckResult _markFailed(String reason, CommandResult? result) {
    _mode = _PlayMode.failed;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _PlayMode {
  /// 남은 일(API 켜기 · SHA-256 등록 · 설정)을 한다.
  apply,

  /// 목록 · 설정 읽기가 실패했다.
  failed,

  /// 프로젝트 ID · 앱 ID 를 읽지 못했다.
  unreadable,

  /// 할 수 없다(지문 없음 · prod 완화 설정).
  deferred,

  /// 끝남.
  done,
}
