import '../confirm.dart';
import '../firebase_app_files.dart';
import '../providers/fingerprints.dart';
import '../providers/key_formats.dart';
import '../providers/keyed_provider_step.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../wizard.dart';
import 'kakao_step.dart';

/// LINE 로그인 단계 — Channel ID · Channel Secret 을 한 번 입력받아 config ·
/// xcconfig · Secret Manager 에 쓴다.
///
/// Channel ID 는 보이는 입력으로 받아 config · xcconfig · Secret Manager 에,
/// Channel Secret 은 숨김 입력으로 받아 Secret Manager 에만 쓴다(서버 전용 값).
/// 쓰기 전에 stateless 채널 액세스 토큰을 요청해 짝을 확인한다 — 발급된 토큰은
/// 저장 · 폐기 대상이 아니고, 응답은 민감 응답이라 화면 · 기록에 남기지 않는다.
final class LineStep extends KeyedProviderStep {
  /// LINE 로그인 단계를 만든다.
  LineStep();

  /// 단계 제목.
  static const String stepTitle = 'LINE 로그인';

  /// 로그인 수단 표의 토큰.
  static const String token = 'line';

  /// Channel ID — config · xcconfig · Secret Manager 세 자리에 같은 값이 들어간다.
  static const KeyField channelIdField = KeyField(
    label: 'LINE Channel ID',
    format: lineChannelId,
    configKey: 'lineChannelId',
    xcconfigVar: 'LINE_CHANNEL_ID',
    secretNames: <String>['LINE_CHANNEL_ID'],
  );

  /// Channel Secret — 서버 전용 secret 이라 Secret Manager 에만 들어간다.
  static const KeyField channelSecretField = KeyField(
    label: 'LINE Channel Secret',
    format: lineChannelSecret,
    secretNames: <String>['LINE_CHANNEL_SECRET'],
    isHidden: true,
  );

  /// 짝 확인에 쓰는 stateless 채널 액세스 토큰 발급 주소.
  static const String pairCheckUrl = 'https://api.line.me/oauth2/v3/token';

  /// 값 표의 Android 서명 SHA-1 행 라벨.
  static const String sha1RowLabel = 'Android 서명 SHA-1';

  /// 응답이 Channel ID 를 가리킬 때 보이는 문장.
  static const String channelIdMismatchMessage = 'Channel ID 가 맞지 않습니다';

  /// 응답이 Channel ID 를 가리키지 않을 때 보이는 문장.
  static const String channelSecretMismatchMessage =
      'Channel Secret 이 Channel ID 와 맞지 않습니다';

  /// 응답 본문에서 Channel ID 를 가리키는 말.
  static const String _channelIdErrorMarker = 'client_id';

  /// Channel ID · Channel Secret 짝을 확인하는 토큰 요청을 만든다.
  ///
  /// 값은 form 본문에만 싣고 URL 쿼리에 넣지 않는다. 표시형에는 Channel Secret
  /// 자리에 [KeyField.valueLabel] 을 넣는다. 응답(액세스 토큰)은 민감 응답이다.
  static ExternalRequest buildPairCheckRequest(
    String channelId,
    String channelSecret,
  ) => ExternalRequest(
    method: 'POST',
    url: Uri.parse(pairCheckUrl),
    formBody: <String, String>{
      'grant_type': 'client_credentials',
      'client_id': channelId,
      'client_secret': channelSecret,
    },
    formDisplay:
        'grant_type=client_credentials'
        '&client_id=$channelId'
        '&client_secret=${channelSecretField.valueLabel}',
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
    channelIdField,
    channelSecretField,
  ];

  /// 번들 ID · 패키지명과 이번 실행에서 계산한 서명 SHA-1 행을 만든다.
  ///
  /// 콘솔에는 iOS scheme 칸이 없어 그 행을 두지 않는다 — 앱의 scheme 은
  /// Info.plist 가 이미 갖고 있다. SHA-1 은 LINE 콘솔이 받는 대문자 · 콜론
  /// 형식이다. 세션에 담긴 지문만 읽는다(keytool 을 부르지 않는다) — 계산했으면
  /// SHA-1, 계산할 수 없었으면 [KakaoStep.keyHashUnavailableValue], 아직 계산
  /// 전이면 행을 넣지 않는다.
  @override
  List<SummaryRow> buildValueRows(WizardContext context) {
    final String? bundleId = readBundleId(context.projectRoot, context.flavor);
    return <SummaryRow>[
      SummaryRow('iOS 번들 ID', bundleId ?? '(읽지 못했습니다)'),
      SummaryRow(
        'Android 패키지명',
        readAndroidPackage(context.projectRoot, context.flavor) ?? '(읽지 못했습니다)',
      ),
      ...?switch (context.session.debugFingerprints) {
        FingerprintsAvailable(:final String sha1Hex) => <SummaryRow>[
          SummaryRow(sha1RowLabel, formatSha1Colon(sha1Hex)),
        ],
        FingerprintsUnavailable() => const <SummaryRow>[
          SummaryRow(sha1RowLabel, KakaoStep.keyHashUnavailableValue),
        ],
        null => null,
      },
    ];
  }

  @override
  List<String> get todoLines => const <String>[
    'LINE Login 채널 만들기',
    'iOS 번들 ID · Android 패키지명 · 서명 SHA-1 등록',
    'OpenID Connect 의 이메일 주소 권한 신청 — 신청하지 않으면 로그인 때 이메일을 받지 못합니다',
    '개발 중인 채널은 Admin 이나 Tester 역할을 준 계정으로 로그인합니다',
  ];

  /// Channel ID · Channel Secret 이 둘 다 있을 때만 서버로 확인한다.
  ///
  /// 200 = 맞음 · 400 · 401 = 응답 본문이 `client_id` 를 가리키면 Channel ID,
  /// 아니면 Channel Secret 만 다시 묻기 · 그 밖(500 · 네트워크 실패 포함) =
  /// 실패. 응답 본문은 다시 물을 값을 고르는 데만 쓰고 문장에는 넣지 않는다.
  @override
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String? channelId = values[channelIdField];
    final String? channelSecret = values[channelSecretField];
    if (channelId == null || channelSecret == null) {
      return const PairNotAvailable();
    }
    final RestResponse response = await context.rest.sendExternal(
      buildPairCheckRequest(channelId, channelSecret),
    );
    final String status = describeRestStatus(response);
    if (response.statusCode == 200) return const PairOk();
    if (response.statusCode == 400 || response.statusCode == 401) {
      return response.body.contains(_channelIdErrorMarker)
          ? PairMismatch(channelIdField, '$channelIdMismatchMessage — $status')
          : PairMismatch(
              channelSecretField,
              '$channelSecretMismatchMessage — $status',
            );
    }
    return PairFailed(
      'Channel ID · Channel Secret 을 서버에서 확인하지 못했습니다 — $status',
    );
  }
}
