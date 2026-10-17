import '../confirm.dart';
import '../firebase_app_files.dart';
import '../providers/key_formats.dart';
import '../providers/keyed_provider_step.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../wizard.dart';

/// Kakao 로그인 단계 — 네이티브 앱 키 · 어드민 키를 한 번 입력받아 config ·
/// xcconfig · Secret Manager 에 쓴다.
///
/// 네이티브 앱 키는 보이는 입력으로 받아 형식만 검사한다(서버 확인 수단이 없다).
/// 어드민 키는 숨김 입력으로 받아, 쓰기 전에 사용자 목록 조회 API 를 한 건만
/// 불러 서버가 받아들이는지 확인한다 — 키는 헤더에만 싣고 화면에는 자리 이름만
/// 보인다.
final class KakaoStep extends KeyedProviderStep {
  /// Kakao 로그인 단계를 만든다.
  KakaoStep();

  /// 단계 제목.
  static const String stepTitle = 'Kakao 로그인';

  /// 로그인 수단 표의 토큰.
  static const String token = 'kakao';

  /// 네이티브 앱 키 — config · xcconfig · Secret Manager 세 자리에 같은 값이 들어간다.
  static const KeyField nativeAppKeyField = KeyField(
    label: 'Kakao 네이티브 앱 키',
    format: kakaoNativeAppKey,
    configKey: 'kakaoNativeAppKey',
    xcconfigVar: 'KAKAO_NATIVE_APP_KEY',
    secretNames: <String>['KAKAO_NATIVE_APP_KEY'],
  );

  /// 어드민 키 — 서버 전용 secret 이라 Secret Manager 에만 들어간다.
  static const KeyField adminKeyField = KeyField(
    label: 'Kakao 어드민 키',
    format: kakaoAdminKey,
    secretNames: <String>['KAKAO_ADMIN_KEY'],
    isHidden: true,
  );

  /// 어드민 키를 확인하는 사용자 목록 조회 주소 — 한 건만 읽는다.
  static const String adminKeyCheckUrl =
      'https://kapi.kakao.com/v1/user/ids?limit=1';

  /// 어드민 키가 틀렸을 때 보이는 문장.
  static const String adminKeyMismatchMessage = '어드민 키가 맞지 않습니다';

  /// [adminKey] 를 서버가 받아들이는지 확인하는 요청을 만든다.
  ///
  /// 키는 `Authorization: KakaoAK <키>` 헤더에만 싣고, 표시형에는
  /// [KeyField.valueLabel] 을 넣는다. 응답(회원번호 목록)은 민감 응답이다.
  static ExternalRequest buildAdminKeyCheckRequest(String adminKey) =>
      ExternalRequest(
        method: 'GET',
        url: Uri.parse(adminKeyCheckUrl),
        headers: <String, String>{'Authorization': 'KakaoAK $adminKey'},
        headerDisplay: <String, String>{
          'Authorization': 'KakaoAK ${adminKeyField.valueLabel}',
        },
      );

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
    nativeAppKeyField,
    adminKeyField,
  ];

  @override
  List<SummaryRow> buildValueRows(WizardContext context) => <SummaryRow>[
    SummaryRow(
      'Android 패키지명',
      readAndroidPackage(context.projectRoot, context.flavor) ?? '(읽지 못했습니다)',
    ),
    SummaryRow(
      'iOS 번들 ID',
      readBundleId(context.projectRoot, context.flavor) ?? '(읽지 못했습니다)',
    ),
  ];

  @override
  List<String> get todoLines => <String>[
    'flavor 마다 애플리케이션을 새로 만들기',
    'Android 플랫폼에 패키지명 · 키 해시 등록 · iOS 플랫폼에 번들 ID 등록',
    '카카오 로그인 · OpenID Connect 켜기',
    '동의 항목에서 이메일을 받도록 설정 — ${formatManualReference(emailManualHeading)}',
  ];

  /// 어드민 키를 입력받았을 때만 서버로 확인한다.
  ///
  /// 200 = 맞음 · 401 = 어드민 키만 다시 묻기 · 그 밖(네트워크 실패 포함) = 실패.
  @override
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String? adminKey = values[adminKeyField];
    if (adminKey == null) return const PairNotAvailable();
    final RestResponse response = await context.rest.sendExternal(
      buildAdminKeyCheckRequest(adminKey),
    );
    if (response.statusCode == 200) return const PairOk();
    if (response.statusCode == 401) {
      return PairMismatch(
        adminKeyField,
        '$adminKeyMismatchMessage — ${describeRestStatus(response)}',
      );
    }
    return PairFailed(
      '어드민 키를 서버에서 확인하지 못했습니다 — ${describeRestStatus(response)}',
    );
  }
}
