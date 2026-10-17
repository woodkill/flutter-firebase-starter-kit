import '../command_runner.dart';
import '../redactor.dart';
import '../rest_client.dart';
import '../wizard.dart';

/// Identity Toolkit 관리 API 주소의 앞부분 — 뒤에 `<프로젝트 ID>/…` 가 붙는다.
const String idpConfigUrlPrefix =
    'https://identitytoolkit.googleapis.com/admin/v2/projects/';

/// 로그인 수단(IdP) 설정 응답에서 값을 가릴 키 — 중첩 객체 · 배열 어디에 있어도
/// 가린다.
const Set<String> idpSecretKeys = <String>{'clientSecret', 'privateKey'};

/// [projectId] 의 로그인 수단 설정 모음 주소(문자열).
String _buildCollectionUrl(String projectId) =>
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs';

/// [projectId] 의 [idpId](예: `facebook.com`) 설정을 읽는 요청을 만든다.
///
/// 응답에 client secret · 개인 키가 평문으로 실릴 수 있어 민감 응답이다.
RestRequest buildIdpGetRequest(String projectId, String idpId) => RestRequest(
  method: 'GET',
  url: Uri.parse('${_buildCollectionUrl(projectId)}/$idpId'),
  quotaProject: projectId,
  isResponseSensitive: true,
);

/// [projectId] 에 [idpId] 설정을 새로 만드는 요청을 만든다.
///
/// 화면 · 기록에는 [body] 대신 [bodyDisplay] 를 보인다. 응답은 만든 설정 전체라
/// 민감 응답이다.
RestRequest buildIdpCreateRequest(
  String projectId,
  String idpId, {
  required String body,
  required String bodyDisplay,
}) => RestRequest(
  method: 'POST',
  url: Uri.parse('${_buildCollectionUrl(projectId)}?idpId=$idpId'),
  quotaProject: projectId,
  body: body,
  bodyDisplay: bodyDisplay,
  isResponseSensitive: true,
);

/// [projectId] 의 [idpId] 설정에서 [updateMask] 필드만 바꾸는 요청을 만든다.
///
/// 화면 · 기록에는 [body] 대신 [bodyDisplay] 를 보인다. 응답은 바뀐 설정 전체라
/// 민감 응답이다.
RestRequest buildIdpPatchRequest(
  String projectId,
  String idpId, {
  required String updateMask,
  required String body,
  required String bodyDisplay,
}) => RestRequest(
  method: 'PATCH',
  url: Uri.parse(
    '${_buildCollectionUrl(projectId)}/$idpId?updateMask=$updateMask',
  ),
  quotaProject: projectId,
  body: body,
  bodyDisplay: bodyDisplay,
  isResponseSensitive: true,
);

/// 해석한 응답 [decoded] 를 끝까지 돌며 [idpSecretKeys] 키의 문자열 값을
/// [redactor] 에 등록한다.
///
/// 객체 · 배열은 재귀로 들어가고, 문자열이 아닌 값은 건너뛴다. 여러 줄 값(PEM 개인
/// 키)은 [Redactor.register] 가 각 줄도 등록한다.
void registerIdpSecrets(Redactor redactor, Object? decoded) {
  switch (decoded) {
    case Map<Object?, Object?>():
      for (final MapEntry<Object?, Object?> entry in decoded.entries) {
        final Object? value = entry.value;
        if (value is String && idpSecretKeys.contains(entry.key)) {
          redactor.register(value);
        } else {
          registerIdpSecrets(redactor, value);
        }
      }
    case List<Object?>():
      for (final Object? item in decoded) {
        registerIdpSecrets(redactor, item);
      }
    default:
      return;
  }
}

/// 로그인 수단 설정 [request] 를 보내고, 응답을 해석하자마자 비밀 값을 등록한다.
///
/// 상태와 관계없이(오류 본문 포함) 등록한 뒤 응답을 돌려준다 — 판정 · 표시는 그
/// 뒤에 한다.
Future<RestResponse> sendIdpRequest(
  WizardContext context,
  RestRequest request,
) async {
  final RestResponse response = await context.rest.send(request);
  registerIdpSecrets(context.redactor, response.decodeJson());
  return response;
}

/// 로그인 수단 설정 읽기 결과.
sealed class IdpRead {
  /// 하위 클래스만 만든다.
  const IdpRead();
}

/// 설정이 있다.
final class IdpFound extends IdpRead {
  /// 읽은 설정 [config] 로 만든다.
  const IdpFound(this.config);

  /// 읽은 설정 객체 — 비밀 값은 이미 가림 함수에 등록돼 있다.
  final Map<String, Object?> config;
}

/// 설정이 아직 없다(404).
final class IdpMissing extends IdpRead {
  /// 없음 결과를 만든다.
  const IdpMissing();
}

/// 읽지 못했다 — 권한 · 네트워크 · 알 수 없는 응답.
final class IdpReadFailed extends IdpRead {
  /// 실패 [reason] 과 가린 실패 원문 [result] 로 만든다.
  const IdpReadFailed(this.reason, this.result);

  /// 실패 요약(상태만).
  final String reason;

  /// 가린 뒤의 응답 본문 — 본문이 없으면 null.
  final CommandResult? result;
}

/// [projectId] 의 [idpId] 설정을 읽는다.
///
/// 응답을 해석하자마자 비밀 값을 등록한 뒤 판정한다 — 2xx 이고 객체면
/// [IdpFound], 404 면 [IdpMissing], 그 밖은 [IdpReadFailed](실패 원문은 가린
/// 뒤 담는다).
Future<IdpRead> readIdpConfig(
  WizardContext context,
  String projectId,
  String idpId,
) async {
  final RestResponse response = await sendIdpRequest(
    context,
    buildIdpGetRequest(projectId, idpId),
  );
  if (response.statusCode == 404) return const IdpMissing();
  final Object? decoded = response.decodeJson();
  if (response.isOk && decoded is Map<String, Object?>) {
    return IdpFound(decoded);
  }
  return IdpReadFailed(
    'Firebase $idpId 로그인 설정을 읽지 못했습니다 — '
    '${describeRestStatus(response)}',
    toFailureResult(response, redactor: context.redactor),
  );
}
