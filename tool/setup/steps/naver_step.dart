import 'dart:io';
import 'dart:math';

import '../config_files.dart';
import '../confirm.dart';
import '../firebase_app_files.dart';
import '../flavor.dart';
import '../providers/key_formats.dart';
import '../providers/keyed_provider_step.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../wizard.dart';
import 'identity_step.dart';

/// Naver 로그인 단계 — Client ID · Client Secret · URL Scheme 을 한 번 입력받아
/// config · xcconfig · Secret Manager 에 쓴다.
///
/// Client ID 와 URL Scheme 은 보이는 입력, Client Secret 은 숨김 입력으로 받는다.
/// URL Scheme 은 앱 이름으로 만든 제안값을 Enter 기본값으로 둔다. 쓰기 전에 토큰
/// 폐기 API 에 존재하지 않는 임의 토큰을 보내 **상태 코드만**으로 Client ID ·
/// Client Secret 짝을 확인한다 — 응답 본문(HTML)은 판정 · 화면 · 실패 문장에
/// 쓰지 않는다. URL Scheme 은 웹 경로의 콜백 scheme 도 겸하므로 Callback URL 은
/// 따로 묻지 않는다.
final class NaverStep extends KeyedProviderStep {
  /// Naver 로그인 단계를 만든다.
  NaverStep();

  /// 단계 제목.
  static const String stepTitle = 'Naver 로그인';

  /// 로그인 수단 표의 토큰.
  static const String token = 'naver';

  /// Client ID — config · xcconfig · Secret Manager 세 자리에 같은 값이 들어간다.
  static const KeyField clientIdField = KeyField(
    label: 'Naver Client ID',
    format: naverClientId,
    configKey: 'naverClientId',
    xcconfigVar: 'NAVER_CLIENT_ID',
    secretNames: <String>['NAVER_CLIENT_ID'],
  );

  /// Client Secret — 숨김 입력으로 받아 세 자리에 같은 값을 쓴다.
  static const KeyField clientSecretField = KeyField(
    label: 'Naver Client Secret',
    format: naverClientSecret,
    configKey: 'naverClientSecret',
    xcconfigVar: 'NAVER_CLIENT_SECRET',
    secretNames: <String>['NAVER_CLIENT_SECRET'],
    isHidden: true,
  );

  /// URL Scheme — config · xcconfig 에만 들어간다(Secret Manager 이름 없음).
  static const KeyField urlSchemeField = KeyField(
    label: 'Naver URL Scheme',
    format: naverUrlScheme,
    configKey: 'naverUrlScheme',
    xcconfigVar: 'NAVER_URL_SCHEME',
  );

  /// 짝 확인에 쓰는 토큰 폐기 주소 — 존재하지 않는 토큰이면 부작용이 없다.
  static const String pairCheckUrl = 'https://nid.naver.com/oauth2.0/revoke';

  /// 짝 확인에 보내는 임의 토큰의 길이.
  static const int probeTokenLength = 32;

  /// Client ID · Client Secret 짝이 틀렸을 때 보이는 문장.
  static const String pairMismatchMessage =
      'Client ID · Client Secret 짝이 맞지 않습니다';

  /// 값 표의 URL Scheme 행 라벨 — config 에 형식에 맞는 값이 있을 때.
  static const String urlSchemeRowLabel = 'iOS URL Scheme';

  /// 값 표의 URL Scheme 행 라벨 — config 값이 없어 제안값을 보일 때.
  static const String suggestedUrlSchemeRowLabel = 'iOS URL Scheme (제안)';

  /// Facebook 값 표가 쓰는 Android 클래스 이름 행 라벨.
  static const String classNameRowLabel = 'Android 클래스 이름';

  /// Facebook 값 표가 쓰는 Android 클래스 이름의 Activity 이름 — Gradle
  /// namespace 뒤에 붙는다.
  static const String mainActivityName = 'MainActivity';

  /// URL Scheme 제안에서 앱 이름 뒤에 붙는 말.
  static const String urlSchemeProviderPart = 'naver';

  /// 앱 이름이 소문자 영문으로 시작하지 않을 때 제안 앞에 붙이는 말.
  static const String urlSchemeFallbackPrefix = 'app';

  /// 임의 토큰 글자.
  static const String _probeTokenAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// Gradle 의 `namespace = "…"` 줄 — group 1 = namespace.
  static final RegExp _namespacePattern = RegExp(r'namespace\s*=\s*"([^"]+)"');

  /// Client ID · Client Secret 짝을 확인하는 토큰 폐기 요청을 만든다.
  ///
  /// 값은 form 본문에만 싣고 URL 쿼리에 넣지 않는다. 표시형에는 Client Secret
  /// 자리에 [KeyField.valueLabel] 을 넣는다. [probeToken] 은 위저드가 만든 임의
  /// 값이라 비밀 값이 아니다.
  static ExternalRequest buildPairCheckRequest(
    String clientId,
    String clientSecret,
    String probeToken,
  ) => ExternalRequest(
    method: 'POST',
    url: Uri.parse(pairCheckUrl),
    formBody: <String, String>{
      'client_id': clientId,
      'client_secret': clientSecret,
      'token': probeToken,
      'token_type_hint': 'access_token',
    },
    formDisplay:
        'client_id=$clientId'
        '&client_secret=${clientSecretField.valueLabel}'
        '&token=$probeToken'
        '&token_type_hint=access_token',
  );

  /// [random] 으로 짝 확인용 임의 토큰([probeTokenLength] 자 영숫자)을 만든다.
  static String buildProbeToken(Random random) => String.fromCharCodes(
    List<int>.generate(
      probeTokenLength,
      (_) => _probeTokenAlphabet.codeUnitAt(
        random.nextInt(_probeTokenAlphabet.length),
      ),
    ),
  );

  /// 앱 이름 [appName] 과 [flavor] 로 URL Scheme 제안값을 만든다.
  ///
  /// 이름 끝의 flavor 표시 접미사([Flavor.displayNameSuffix])를 떼고 소문자로
  /// 바꾼 뒤 영문 · 숫자만 남기고 `naver` + flavor 이름을 붙인다. 앞이 소문자
  /// 영문이 아니면(숫자로 시작 · 빈 이름) 앞에 `app` 을 붙여, 결과는 언제나
  /// [naverUrlScheme] 형식에 맞는다.
  static String buildSuggestedUrlScheme(String appName, Flavor flavor) {
    var base = appName.trim();
    final String suffix = flavor.displayNameSuffix;
    if (suffix.isNotEmpty && base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    final String cleaned = base.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    final head = cleaned.startsWith(RegExp('[a-z]'))
        ? cleaned
        : '$urlSchemeFallbackPrefix$cleaned';
    return '$head$urlSchemeProviderPart${flavor.name}';
  }

  /// [projectRoot] 의 Gradle namespace 로 Facebook 값 표가 쓰는 Android 클래스
  /// 이름을 만든다 — 파일이 없거나 namespace 줄이 없으면 null.
  ///
  /// flavor 접미사는 붙이지 않는다(Activity 클래스는 flavor 와 무관하다).
  static String? readMainActivityClass(String projectRoot) {
    final file = File('$projectRoot/${IdentityStep.gradlePath}');
    try {
      if (!file.existsSync()) return null;
      final String? namespace = _namespacePattern
          .firstMatch(file.readAsStringSync())
          ?.group(1);
      return namespace == null ? null : '$namespace.$mainActivityName';
    } on FileSystemException {
      return null;
    }
  }

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

  @override
  ProviderEntry get entry => findProvider(token)!;

  @override
  List<KeyField> get fields => const <KeyField>[
    clientIdField,
    clientSecretField,
    urlSchemeField,
  ];

  /// Naver 콘솔의 iOS · Android 환경 칸(URL Scheme · 패키지명) 행을 만든다 —
  /// 콘솔에 번들 ID · 클래스 이름 · 키 해시 칸이 없다.
  ///
  /// URL Scheme 은 config 값이 형식에 맞으면 그 값, 아니면 제안값이다.
  @override
  List<SummaryRow> buildValueRows(WizardContext context) {
    final String? configScheme = _readConfigString(
      context,
      urlSchemeField.configKey!,
    );
    final bool hasConfigScheme =
        configScheme != null && naverUrlScheme.matches(configScheme);
    return <SummaryRow>[
      if (hasConfigScheme)
        SummaryRow(urlSchemeRowLabel, configScheme)
      else
        SummaryRow(suggestedUrlSchemeRowLabel, _buildSuggestion(context)),
      SummaryRow(
        'Android 패키지명',
        readAndroidPackage(context.projectRoot, context.flavor) ?? '(읽지 못했습니다)',
      ),
    ];
  }

  @override
  List<String> get todoLines => <String>[
    '애플리케이션 등록 · 네이버 로그인 API 사용 · 로고 이미지 올리기(필수 — 없으면 저장되지 않습니다)',
    'iOS 환경에 다운로드 URL · URL Scheme · Android 환경에 다운로드 URL · 패키지명 등록',
    '다운로드 URL 은 스토어에 올리기 전이면 임의 주소(예: 개발사 홈페이지)를 넣고 출시 뒤 바꿉니다',
    '제공 정보에서 이메일 주소 받기 — ${formatManualReference(emailManualHeading)}',
    '개발 중인 애플리케이션은 멤버관리에 등록한 관리자 · 테스터 ID 만 로그인할 수 있습니다',
  ];

  /// URL Scheme 입력의 Enter 기본값은 제안값이다 — 다른 값은 제안이 없다.
  @override
  String? suggestValue(WizardContext context, KeyField field) =>
      identical(field, urlSchemeField) ? _buildSuggestion(context) : null;

  /// Client ID · Client Secret 이 둘 다 있을 때만 서버로 확인한다.
  ///
  /// 상태 코드만 본다: 200 = 맞음 · 401 = Client ID · Client Secret 을 함께 다시
  /// 묻기 · 그 밖(400 · 네트워크 실패 포함) = 실패. URL Scheme 은 넘기지 않는다.
  @override
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String? clientId = values[clientIdField];
    final String? clientSecret = values[clientSecretField];
    if (clientId == null || clientSecret == null) {
      return const PairNotAvailable();
    }
    final RestResponse response = await context.rest.sendExternal(
      buildPairCheckRequest(
        clientId,
        clientSecret,
        buildProbeToken(context.random),
      ),
    );
    if (response.statusCode == 200) return const PairOk();
    if (response.statusCode == 401) {
      return PairMismatch(
        clientIdField,
        '$pairMismatchMessage — ${describeRestStatus(response)}',
        alsoFields: const <KeyField>[clientSecretField],
      );
    }
    return PairFailed(
      'Client ID · Client Secret 을 서버에서 확인하지 못했습니다 — '
      '${describeRestStatus(response)}',
    );
  }

  /// 이 flavor config 의 앱 이름으로 URL Scheme 제안값을 만든다.
  static String _buildSuggestion(WizardContext context) =>
      buildSuggestedUrlScheme(
        _readConfigString(context, 'appName') ?? '',
        context.flavor,
      );

  /// 이 flavor config 의 [key] 문자열 값 — 파일이 없거나 읽지 못하면 null.
  static String? _readConfigString(WizardContext context, String key) {
    final String path = context.resolve(context.paths.json);
    try {
      if (!File(path).existsSync()) return null;
      return readJsonString(path, key)?.trim();
    } on FileSystemException {
      return null;
    }
  }
}
