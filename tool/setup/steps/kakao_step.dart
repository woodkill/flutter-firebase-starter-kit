import '../confirm.dart';
import '../firebase_app_files.dart';
import '../providers/fingerprints.dart';
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
/// 보인다. 입력한 네이티브 앱 키가 Secret Manager 의 것과 다르고 어드민 키가 이미
/// 있으면 그 어드민 키를 그대로 둘지 묻는다.
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

  /// Secret Manager 의 어드민 키가 입력한 네이티브 앱 키와 같은 앱의 것인지 묻는
  /// 질문 — 키 값은 넣지 않는다.
  static const String adminKeyAppQuestion =
      '입력한 네이티브 앱 키가 Secret Manager 의 네이티브 앱 키와 다릅니다 — '
      'Secret Manager 의 어드민 키가 입력한 키와 같은 Kakao 앱의 키인가요?';

  /// 어드민 키 질문의 그대로 둠 선택지.
  static const String adminKeyKeepOption = '네 — 같은 Kakao 앱입니다 · 어드민 키를 그대로 둡니다';

  /// 어드민 키 질문의 새로 입력 선택지.
  static const String adminKeyRenewOption =
      '아니요 — 새 Kakao 앱입니다 · 어드민 키를 새로 입력합니다';

  /// Secret Manager 의 어드민 키를 그대로 둘지 묻는 질문 묶음.
  static const StoredSecretQuestion adminKeyStoredQuestion =
      StoredSecretQuestion(
        field: adminKeyField,
        question: adminKeyAppQuestion,
        keepOption: adminKeyKeepOption,
        renewOption: adminKeyRenewOption,
      );

  /// 값 표의 Android 키 해시 행 라벨.
  static const String keyHashRowLabel = 'Android 키 해시';

  /// 지문을 계산할 수 없을 때 값 표의 키 해시 행 값 — 칸을 비워 두고, 콘솔이
  /// 요구하면 Android 쪽 줄 안내대로 나중에 등록하라는 뜻이다.
  static const String keyHashUnavailableValue =
      '(이 Mac 에서는 계산할 수 없음 — 비워 두세요 · 콘솔이 이 값을 요구하면 '
      '그 Android 등록은 Android 쪽 줄 안내대로 나중에)';

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

  /// 패키지명 · 번들 ID 와 이번 실행에서 계산한 Android 키 해시 행을 만든다.
  ///
  /// 키 해시 행은 세션에 담긴 지문만 읽는다(keytool 을 부르지 않는다) — 계산했으면
  /// 키 해시, 계산할 수 없었으면 [keyHashUnavailableValue], 아직 계산 전이면
  /// 행을 넣지 않는다.
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
    ...?switch (context.session.debugFingerprints) {
      FingerprintsAvailable(:final String keyHash) => <SummaryRow>[
        SummaryRow(keyHashRowLabel, keyHash),
      ],
      FingerprintsUnavailable() => const <SummaryRow>[
        SummaryRow(keyHashRowLabel, keyHashUnavailableValue),
      ],
      null => null,
    },
  ];

  @override
  List<String> get todoLines => <String>[
    '「앱 생성」 창에서 새 앱 만들기',
    '네이티브 앱 키에 Android 패키지명 · 키 해시 · iOS 번들 ID 등록',
    '카카오 로그인 · OpenID Connect 켜기',
    '동의 항목에서 이메일을 받도록 설정 — ${formatDocReference(emailDocRef)}',
  ];

  /// 이번에 입력한 네이티브 앱 키가 Secret Manager 의 네이티브 앱 키와 다르고
  /// Secret Manager 에 어드민 키가 있을 때만 어드민 키 질문을 고른다.
  ///
  /// Kakao 에는 두 키가 같은 앱인지 서버로 가르는 API 가 없어 사용자에게 묻는다.
  /// 같은 앱의 키를 다시 넣는 재실행은 묻지 않는다.
  @override
  List<StoredSecretQuestion> selectStoredSecretQuestions(
    Map<KeyField, String> enteredValues,
    Map<String, String> storedSecretValues,
  ) {
    final String? enteredNative = enteredValues[nativeAppKeyField];
    final String? storedNative =
        storedSecretValues[nativeAppKeyField.secretNames.single];
    final bool hasStoredAdmin = storedSecretValues.containsKey(
      adminKeyField.secretNames.single,
    );
    if (enteredNative == null ||
        !hasStoredAdmin ||
        storedNative == null ||
        storedNative == enteredNative) {
      return const <StoredSecretQuestion>[];
    }
    return const <StoredSecretQuestion>[adminKeyStoredQuestion];
  }

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
