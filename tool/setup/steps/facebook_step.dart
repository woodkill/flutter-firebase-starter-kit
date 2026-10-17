import 'dart:convert';

import '../confirm.dart';
import '../firebase_app_files.dart';
import '../providers/fingerprints.dart';
import '../providers/idp_config.dart';
import '../providers/key_formats.dart';
import '../providers/keyed_provider_step.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'kakao_step.dart';
import 'naver_step.dart';

/// Facebook 로그인 단계 — App ID · Client Token · App Secret 을 한 번 입력받아
/// config · xcconfig · Secret Manager 와 Firebase 의 Facebook 로그인 설정에 쓴다.
///
/// App ID · Client Token 은 보이는 입력, App Secret 은 숨김 입력으로 받는다. 쓰기
/// 전에 Graph API 의 앱 토큰 요청으로 App ID · App Secret 짝을 확인한다 — 비밀
/// 값은 form 본문에만 싣고 응답(앱 토큰)은 민감 응답이다. Firebase 설정은 단계
/// 끝에 읽어 다르면 같은 값으로 고치고(없으면 새로 만든다), 검사도 그 설정의
/// 켜짐 · App ID · App Secret 을 함께 본다.
final class FacebookStep extends KeyedProviderStep {
  /// Facebook 로그인 단계를 만든다.
  FacebookStep();

  /// 단계 제목.
  static const String stepTitle = 'Facebook 로그인';

  /// 로그인 수단 표의 토큰.
  static const String token = 'facebook';

  /// Firebase 로그인 수단 설정의 IdP ID.
  static const String idpId = 'facebook.com';

  /// 키를 발급받는 Meta 개발자 콘솔 주소.
  static const String consoleUrl = 'https://developers.facebook.com/apps';

  /// App ID — config · xcconfig · Secret Manager 세 자리에 같은 값이 들어간다.
  static const KeyField appIdField = KeyField(
    label: 'Facebook App ID',
    format: facebookAppId,
    configKey: 'facebookAppId',
    xcconfigVar: 'FACEBOOK_APP_ID',
    secretNames: <String>['FACEBOOK_APP_ID'],
  );

  /// Client Token — config · xcconfig 에만 들어간다(Secret Manager 이름 없음).
  static const KeyField clientTokenField = KeyField(
    label: 'Facebook Client Token',
    format: facebookClientToken,
    configKey: 'facebookClientToken',
    xcconfigVar: 'FACEBOOK_CLIENT_TOKEN',
  );

  /// App Secret — 서버 전용 secret 이라 Secret Manager 와 Firebase 설정에만 들어간다.
  static const KeyField appSecretField = KeyField(
    label: 'Facebook App Secret',
    format: facebookAppSecret,
    secretNames: <String>['FACEBOOK_APP_SECRET'],
    isHidden: true,
  );

  /// 짝 확인에 쓰는 앱 토큰 요청 주소.
  static const String pairCheckUrl =
      'https://graph.facebook.com/oauth/access_token';

  /// 짝 확인 응답에서 App ID 가 틀렸다는 오류 코드.
  static const int invalidClientIdCode = 101;

  /// App ID 가 틀렸을 때 보이는 문장.
  static const String appIdMismatchMessage = 'App ID 가 맞지 않습니다';

  /// App ID 를 가리키지 않는 400 일 때 보이는 문장.
  static const String appSecretMismatchMessage =
      'App Secret 이 App ID 와 맞지 않습니다';

  /// 검사 · 실행 화면에 보이는 원격 자리 이름.
  static const String remotePlaceName = 'Firebase Facebook 로그인 설정';

  /// Firebase 설정 PATCH 가 바꾸는 필드.
  static const String idpUpdateMask = 'enabled,clientId,clientSecret';

  /// 쓰기 계획 끝에 덧붙이는 Firebase 설정 줄(값 없음).
  static const String _remoteWriteLine =
      '($remotePlaceName 이 다르면 같은 App ID · App Secret 으로 씁니다 — 값은 '
      '화면에 보이지 않습니다)';

  /// 값 표의 OAuth redirect URI 행 라벨.
  static const String redirectUriRowLabel = 'OAuth redirect URI';

  /// 읽지 못한 값 자리.
  static const String unreadableValue = '(읽지 못했습니다)';

  /// [projectId] 의 Firebase 인증 핸들러 주소(OAuth redirect URI)를 만든다.
  static String buildRedirectUri(String projectId) =>
      'https://$projectId.firebaseapp.com/__/auth/handler';

  /// App ID · App Secret 짝을 확인하는 앱 토큰 요청을 만든다.
  ///
  /// 값은 form 본문에만 싣고 URL 쿼리에 넣지 않는다. 표시형에는 App Secret 자리에
  /// [KeyField.valueLabel] 을 넣는다. 응답(앱 토큰)은 민감 응답이다.
  static ExternalRequest buildPairCheckRequest(
    String appId,
    String appSecret,
  ) => ExternalRequest(
    method: 'POST',
    url: Uri.parse(pairCheckUrl),
    formBody: <String, String>{
      'grant_type': 'client_credentials',
      'client_id': appId,
      'client_secret': appSecret,
    },
    formDisplay:
        'grant_type=client_credentials'
        '&client_id=$appId'
        '&client_secret=${appSecretField.valueLabel}',
  );

  /// Firebase Facebook 설정 본문을 만든다 — 켜짐 · App ID · App Secret.
  static String buildIdpBody(String appId, String appSecret) =>
      jsonEncode(<String, Object?>{
        'enabled': true,
        'clientId': appId,
        'clientSecret': appSecret,
      });

  /// 화면 · 기록에 보일 Firebase Facebook 설정 본문 — App Secret 은 자리 이름.
  static String buildIdpBodyDisplay(String appId) =>
      buildIdpBody(appId, appSecretField.valueLabel);

  @override
  String get id => token;

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>[
    'providers',
    'configure',
    'apis',
  ];

  /// 카탈로그 행에서 콘솔 주소만 Meta 개발자 콘솔([consoleUrl])로 바꾼 행.
  @override
  ProviderEntry get entry {
    final ProviderEntry catalog = findProvider(token)!;
    return ProviderEntry(
      token: catalog.token,
      displayName: catalog.displayName,
      manualSectionPrefix: catalog.manualSectionPrefix,
      consoleUrl: consoleUrl,
    );
  }

  @override
  List<KeyField> get fields => const <KeyField>[
    appIdField,
    clientTokenField,
    appSecretField,
  ];

  /// 번들 ID · 패키지명 · 클래스 이름 · 이번 실행에서 계산한 Android 키 해시 ·
  /// OAuth redirect URI 행을 만든다.
  ///
  /// 키 해시 행은 세션에 담긴 지문만 읽는다(keytool 을 부르지 않는다) — 계산했으면
  /// 키 해시, 계산할 수 없었으면 [KakaoStep.keyHashUnavailableValue], 아직 계산
  /// 전이면 행을 넣지 않는다. redirect URI 는 이 flavor config 의 프로젝트 ID 로
  /// 만든다.
  @override
  List<SummaryRow> buildValueRows(WizardContext context) {
    final String? projectId = readConfiguredProjectId(context);
    return <SummaryRow>[
      SummaryRow(
        'iOS 번들 ID',
        readBundleId(context.projectRoot, context.flavor) ?? unreadableValue,
      ),
      SummaryRow(
        'Android 패키지명',
        readAndroidPackage(context.projectRoot, context.flavor) ??
            unreadableValue,
      ),
      SummaryRow(
        NaverStep.classNameRowLabel,
        NaverStep.readMainActivityClass(context.projectRoot) ?? unreadableValue,
      ),
      ...?switch (context.session.debugFingerprints) {
        FingerprintsAvailable(:final String keyHash) => <SummaryRow>[
          SummaryRow(KakaoStep.keyHashRowLabel, keyHash),
        ],
        FingerprintsUnavailable() => const <SummaryRow>[
          SummaryRow(
            KakaoStep.keyHashRowLabel,
            KakaoStep.keyHashUnavailableValue,
          ),
        ],
        null => null,
      },
      SummaryRow(
        redirectUriRowLabel,
        projectId == null ? unreadableValue : buildRedirectUri(projectId),
      ),
    ];
  }

  @override
  List<String> get todoLines => <String>[
    'flavor 마다 앱 만들기 · Facebook 로그인 사용 사례 추가',
    'Android 플랫폼에 패키지명 · 클래스 이름 · 키 해시, iOS 플랫폼에 번들 ID 등록',
    'Facebook 로그인 설정의 OAuth redirect URI 에 위 주소 등록',
    '이메일 권한 받기 — ${formatManualReference(emailManualHeading)}',
    '개발 모드 앱은 앱 역할이 있는 계정만 로그인할 수 있습니다',
  ];

  /// 쓰기 계획 뒤에 Firebase 설정 줄을 덧붙인다 — 값은 넣지 않는다.
  @override
  List<String> plannedCommandLines(WizardContext context) {
    final List<String> lines = super.plannedCommandLines(context);
    if (lines.isEmpty ||
        (lines.length == 1 && lines.single == '(명령 원문을 보입니다)')) {
      return lines;
    }
    return <String>[...lines, _remoteWriteLine];
  }

  /// App ID · App Secret 이 둘 다 있을 때만 서버로 확인한다.
  ///
  /// 200 = 맞음 · 400 이고 오류 코드가 [invalidClientIdCode] 면 App ID, 그 밖
  /// 400 은 App Secret 만 다시 묻기 · 그 밖(401 · 500 · 네트워크 실패 포함) =
  /// 실패. 응답 본문은 다시 물을 값을 고르는 데만 쓰고 문장에는 넣지 않는다.
  @override
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String? appId = values[appIdField];
    final String? appSecret = values[appSecretField];
    if (appId == null || appSecret == null) return const PairNotAvailable();
    final RestResponse response = await context.rest.sendExternal(
      buildPairCheckRequest(appId, appSecret),
    );
    final String status = describeRestStatus(response);
    if (response.statusCode == 200) {
      _registerAccessToken(context, response);
      return const PairOk();
    }
    if (response.statusCode == 400) {
      return _readErrorCode(response) == invalidClientIdCode
          ? PairMismatch(appIdField, '$appIdMismatchMessage — $status')
          : PairMismatch(appSecretField, '$appSecretMismatchMessage — $status');
    }
    return PairFailed('App ID · App Secret 을 서버에서 확인하지 못했습니다 — $status');
  }

  /// Firebase Facebook 설정이 켜져 있고 App ID · App Secret 이 [values] 와 같은지
  /// 본다 — 다르거나 읽지 못하면 [remotePlaceName].
  ///
  /// 두 값 중 하나라도 없으면(어차피 입력 뒤 쓴다) 요청 없이 자리 이름을
  /// 돌려준다. App Secret 은 메모리에서만 비교한다.
  @override
  Future<String?> findRemoteProblem(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String? appId = values[appIdField];
    final String? appSecret = values[appSecretField];
    final String? projectId = readConfiguredProjectId(context);
    if (appId == null || appSecret == null || projectId == null) {
      return remotePlaceName;
    }
    final IdpRead read = await readIdpConfig(context, projectId, idpId);
    return switch (read) {
      IdpFound(:final Map<String, Object?> config)
          when _matchesConfig(config, appId, appSecret) =>
        null,
      _ => remotePlaceName,
    };
  }

  /// Firebase Facebook 설정을 [values] 의 App ID · App Secret 으로 맞춘다.
  ///
  /// 읽어서 없으면(404) 새로 만들고, 다르면 [idpUpdateMask] 세 필드만 바꾸고,
  /// 같으면 쓰지 않는다. 읽기 · 쓰기 실패는 가린 원문과 함께 [Failed] 다.
  @override
  Future<Failed?> writeRemote(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String? appId = values[appIdField];
    final String? appSecret = values[appSecretField];
    final String? projectId = readConfiguredProjectId(context);
    if (appId == null || appSecret == null || projectId == null) {
      return const Failed('$remotePlaceName 에 쓸 App ID · App Secret 이 없습니다');
    }
    final IdpRead read = await readIdpConfig(context, projectId, idpId);
    final RestRequest request;
    switch (read) {
      case IdpReadFailed(:final String reason, :final result):
        return Failed(reason, result: result);
      case IdpFound(:final Map<String, Object?> config)
          when _matchesConfig(config, appId, appSecret):
        return null;
      case IdpFound():
        request = buildIdpPatchRequest(
          projectId,
          idpId,
          updateMask: idpUpdateMask,
          body: buildIdpBody(appId, appSecret),
          bodyDisplay: buildIdpBodyDisplay(appId),
        );
      case IdpMissing():
        request = buildIdpCreateRequest(
          projectId,
          idpId,
          body: buildIdpBody(appId, appSecret),
          bodyDisplay: buildIdpBodyDisplay(appId),
        );
    }
    final RestResponse response = await sendIdpRequest(context, request);
    if (!response.isOk) {
      return Failed(
        '$remotePlaceName 을 쓰지 못했습니다 — ${describeRestStatus(response)}',
        result: toFailureResult(response, redactor: context.redactor),
      );
    }
    context.terminal.writeLine(
      '  $remotePlaceName — App ID · App Secret 을 썼습니다',
    );
    return null;
  }

  /// [config] 가 켜져 있고 App ID · App Secret 이 같으면 true.
  static bool _matchesConfig(
    Map<String, Object?> config,
    String appId,
    String appSecret,
  ) =>
      config['enabled'] == true &&
      config['clientId'] == appId &&
      config['clientSecret'] == appSecret;

  /// 짝 확인 오류 응답의 `error.code` — 없거나 정수가 아니면 null.
  static int? _readErrorCode(RestResponse response) {
    final Object? decoded = response.decodeJson();
    if (decoded is! Map<String, Object?>) return null;
    final Object? error = decoded['error'];
    if (error is! Map<String, Object?>) return null;
    final Object? code = error['code'];
    return code is int ? code : null;
  }

  /// 짝 확인 200 응답의 앱 토큰을 가림 함수에 등록한다 — 화면 · 기록에 쓰지 않지만
  /// 다른 경로로 흘러도 가려지게 한다.
  static void _registerAccessToken(
    WizardContext context,
    RestResponse response,
  ) {
    final Object? decoded = response.decodeJson();
    if (decoded is! Map<String, Object?>) return;
    final Object? token = decoded['access_token'];
    if (token is String) context.redactor.register(token);
  }
}
