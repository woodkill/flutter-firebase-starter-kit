import '../command_runner.dart';
import '../firebase_app_files.dart';
import '../providers/fingerprints.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'identity_step.dart';

/// Google 로그인의 Android 쪽 단계 — 디버그 서명 키의 SHA-1 을 Firebase Android
/// 앱의 SHA 인증서 목록에 등록한다.
///
/// 지문을 계산할 수 없으면(JDK · 디버그 서명 키 없음) 이 줄만 미뤄 두고 뒤 단계는
/// 그대로 진행한다 — 위저드는 도구를 설치하거나 키를 만들지 않는다. 계산할 수
/// 있으면 Firebase Management API 의 SHA 목록을 읽어 SHA-1 이 없을 때만 `SHA_1`
/// 종류로 등록한다(소문자 · 콜론 없음).
final class GoogleAndroidStep implements Step {
  /// Google Android 쪽 단계를 만든다.
  GoogleAndroidStep();

  /// 단계 제목.
  static const String stepTitle = 'Google — Android 쪽';

  _GoogleAndroidMode _mode = _GoogleAndroidMode.failed;
  String _reason = '';
  String _projectId = '';
  String _androidAppId = '';
  String _sha1Hex = '';
  CommandResult? _failedResult;

  @override
  String get id => 'google_android';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['google', 'configure'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final DebugFingerprints fingerprints = await readDebugFingerprints(context);
    if (fingerprints is! FingerprintsAvailable) {
      _mode = _GoogleAndroidMode.deferred;
      return const Deferred(unavailableFingerprintGuide);
    }
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark('${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다');
    }
    final String? packageName = readAndroidPackage(
      context.projectRoot,
      context.flavor,
    );
    if (packageName == null) {
      return _mark('${IdentityStep.gradlePath} 에서 applicationId 를 읽지 못했습니다');
    }
    final String? androidAppId = FirebaseAppFiles.read(
      context.projectRoot,
      flavor: context.flavor,
    ).androidAppIdFor(packageName);
    if (androidAppId == null) {
      return _mark(
        '${context.paths.androidJson} 에서 패키지명 $packageName 의 Android 앱을 '
        '찾지 못했습니다 — 앱 등록 단계를 먼저 끝내세요',
      );
    }
    _projectId = projectId;
    _androidAppId = androidAppId;
    _sha1Hex = normalizeShaHash(fingerprints.sha1Hex);

    final RestResponse response = await context.rest.send(
      buildShaListRequest(projectId, androidAppId),
    );
    final Set<String>? hashes = parseShaHashes(response);
    if (hashes == null) {
      return _mark(
        'Firebase Android 앱의 SHA 인증서 목록을 읽지 못했습니다 — '
        '${describeRestStatus(response)}',
        result: toFailureResult(response, redactor: context.redactor),
      );
    }
    if (hashes.contains(_sha1Hex)) {
      _mode = _GoogleAndroidMode.done;
      return Done('디버그 SHA-1 이 Firebase Android 앱($packageName)에 등록돼 있음');
    }
    _mode = _GoogleAndroidMode.register;
    _reason = '디버그 SHA-1 이 Firebase Android 앱($packageName)에 등록돼 있지 않습니다';
    return Todo(_reason);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _GoogleAndroidMode.register => <String>[
      _buildCreateRequest().displayCurl(),
    ],
    _GoogleAndroidMode.failed when _failedResult != null => const <String>[
      '(응답 원문을 보입니다)',
    ],
    _GoogleAndroidMode.failed ||
    _GoogleAndroidMode.deferred ||
    _GoogleAndroidMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _GoogleAndroidMode.failed:
        return Failed(_reason, result: _failedResult);
      case _GoogleAndroidMode.deferred || _GoogleAndroidMode.done:
        return const Applied();
      case _GoogleAndroidMode.register:
        final RestResponse response = await context.rest.send(
          _buildCreateRequest(),
        );
        if (response.isOk) return const Applied();
        return Failed(
          '디버그 SHA-1 을 등록하지 못했습니다 — ${describeRestStatus(response)}',
          result: toFailureResult(response, redactor: context.redactor),
        );
    }
  }

  /// 직전 검사의 SHA-1 을 등록하는 요청을 만든다.
  RestRequest _buildCreateRequest() => buildShaCreateRequest(
    _projectId,
    _androidAppId,
    shaHash: _sha1Hex,
    certType: shaCertTypeSha1,
  );

  /// 실패 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(String reason, {CommandResult? result}) {
    _mode = _GoogleAndroidMode.failed;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _GoogleAndroidMode {
  /// SHA-1 이 목록에 없다 — 등록한다.
  register,

  /// 값을 읽지 못했다 — 실행하면 실패로 끝난다.
  failed,

  /// 지문을 계산할 수 없다 — 이 줄만 미룬다.
  deferred,

  /// 끝남.
  done,
}
