import '../command_runner.dart';
import '../rest_client.dart';
import '../steps/run_step.dart';
import '../wizard.dart';

/// Firebase Auth 가 직접 받는 로그인 수단 토큰 → 사용자의 `providerUserInfo`
/// 에 실리는 `providerId`.
///
/// 이 수단들의 가입자는 Identity Toolkit 사용자 목록(`accounts:batchGet`)으로 센다.
const Map<String, String> authProviderIds = <String, String>{
  'google': 'google.com',
  'apple': 'apple.com',
  'facebook': 'facebook.com',
};

/// Custom Token 으로 가입하는 로그인 수단 토큰 — Firestore `identity_index`
/// 문서의 `provider` 필드 값과 같다.
const Set<String> identityIndexProviders = <String>{'kakao', 'naver', 'line'};

/// identity_index 목록 API 주소의 앞부분 — 뒤에 `<프로젝트 ID>/databases/…` 가 붙는다.
const String identityIndexUrlPrefix =
    'https://firestore.googleapis.com/v1/projects/';

/// identity_index 목록 한 페이지의 문서 수.
const int identityIndexPageSize = 300;

/// Custom Token 수단(Kakao · Naver · LINE)을 무엇으로 셀지 정하는 기준.
enum SignInBasis {
  /// 가입 흔적으로 센다 — Google · Apple · Facebook 은 Auth `providerUserInfo`,
  /// Kakao · Naver · LINE 은 identity_index 문서가 있는 것만으로 센다(끄기 전
  /// 가입자 수 — 더 많이 세는 쪽이 끄기 경고에 안전하다).
  registered,

  /// 실제 로그인으로 센다 — Kakao · Naver · LINE 은 문서 주인(`firebaseUid`)의
  /// Auth 기록이 Custom Token 로그인(`customAuth`)이고 마지막 로그인 시각
  /// (`lastLoginAt`)이 문서가 생긴 시각(`createTime`) 이후인 문서만 센다.
  signedIn,
}

/// 로그인 수단별 가입자 수 집계 결과.
sealed class SignInCount {
  /// 하위 클래스만 만든다.
  const SignInCount();
}

/// 집계를 마쳤다 — 요청한 토큰마다 가입자 수가 있다.
final class SignInCountOk extends SignInCount {
  /// 토큰 → 가입자 수 [countsByToken] 으로 만든다.
  const SignInCountOk(this.countsByToken);

  /// 로그인 수단 토큰 → 가입자 수.
  final Map<String, int> countsByToken;
}

/// 집계하지 못했다 — 사유와, 있으면 실패 응답 원문을 담는다.
final class SignInCountFailed extends SignInCount {
  /// 실패 사유 [reason] 과 실패 응답 [result] 로 만든다.
  const SignInCountFailed(this.reason, this.result);

  /// 실패 사유 — 상태만 적고 응답의 사용자 값은 싣지 않는다.
  final String reason;

  /// 실패 응답 원문(오류 설명). 없으면 null.
  final CommandResult? result;
}

/// [projectId] 의 Firestore `identity_index` 한 페이지를 읽는 요청을 만든다.
///
/// [basis] 가 [SignInBasis.registered] 면 `provider` 필드만, [SignInBasis.signedIn]
/// 이면 문서 주인 uid(`firebaseUid`) 필드도 읽는다 — 사용자 ID 필드는 어느
/// 쪽도 싣지 않는다. 문서 이름 · 주인 uid 가 실리므로 민감 응답으로 둔다.
/// [pageToken] 이 있으면 그 페이지부터 읽는다.
RestRequest buildIdentityIndexRequest(
  String projectId, {
  String? pageToken,
  SignInBasis basis = SignInBasis.registered,
}) {
  final url = StringBuffer()
    ..write('$identityIndexUrlPrefix$projectId')
    ..write('/databases/(default)/documents/identity_index')
    ..write('?pageSize=$identityIndexPageSize&mask.fieldPaths=provider');
  if (basis == SignInBasis.signedIn) {
    url.write('&mask.fieldPaths=firebaseUid');
  }
  if (pageToken != null) {
    url.write('&pageToken=${Uri.encodeQueryComponent(pageToken)}');
  }
  return RestRequest(
    method: 'GET',
    url: Uri.parse(url.toString()),
    quotaProject: projectId,
    isResponseSensitive: true,
  );
}

/// [projectId] 에서 로그인 수단 [tokens] 마다 가입자 수를 센다.
///
/// Google · Apple · Facebook 은 사용자 목록의 `providerUserInfo[].providerId` 로
/// 센다. Kakao · Naver · LINE 은 [basis] 를 따른다 — [SignInBasis.registered] 면
/// `identity_index` 문서의 `provider` 필드로, [SignInBasis.signedIn] 이면 그 문서
/// 가운데 [hasSignedInAfter] 가 참인 것만 센다(이때는 사용자 목록 한 번 읽기로
/// Google 등의 개수와 문서 주인의 로그인 기록을 함께 모은다). 필요한 쪽만
/// 요청하고 둘 다 끝 페이지까지 읽는다. 응답 본문은 메모리에서 비교 · 계수만
/// 하고 버리며 화면 · 기록에 쓰지 않는다. 표에 없는 토큰은 결과에 넣지 않는다.
Future<SignInCount> countSignIns(
  WizardContext context,
  String projectId,
  Set<String> tokens, {
  SignInBasis basis = SignInBasis.registered,
}) async {
  final counts = <String, int>{};
  final authTokens = <String, String>{
    for (final MapEntry<String, String> entry in authProviderIds.entries)
      if (tokens.contains(entry.key)) entry.key: entry.value,
  };
  final Set<String> indexTokens = tokens.intersection(identityIndexProviders);
  // 로그인 대조 모드에서만 채운다 — Custom Token 로그인 uid → 마지막 로그인 시각.
  final Map<String, String?>? customAuthLogins =
      basis == SignInBasis.signedIn && indexTokens.isNotEmpty
      ? <String, String?>{}
      : null;
  if (authTokens.isNotEmpty || customAuthLogins != null) {
    final SignInCountFailed? failed = await _countAuthUsers(
      context,
      projectId,
      authTokens,
      counts,
      customAuthLogins,
    );
    if (failed != null) return failed;
  }
  if (indexTokens.isNotEmpty) {
    final SignInCountFailed? failed = await _countIndexDocuments(
      context,
      projectId,
      indexTokens,
      counts,
      customAuthLogins,
    );
    if (failed != null) return failed;
  }
  return SignInCountOk(counts);
}

/// Custom Token 수단의 문서 하나를 「로그인함」 으로 셀지 판정한다.
///
/// 문서 주인이 Custom Token 으로 로그인한 사용자([isCustomAuth])이고, 그 마지막
/// 로그인 시각 [lastLoginAt](epoch ms 문자열)이 문서가 생긴 시각 [createTime]
/// (RFC 3339) 과 같거나 뒤일 때만 참이다. 하나라도 없거나 읽지 못하면 거짓이다
/// — 문서만 남은 실패한 로그인을 「로그인함」 으로 세지 않는 쪽으로 기운다.
bool hasSignedInAfter({
  required bool isCustomAuth,
  required String? lastLoginAt,
  required String? createTime,
}) {
  if (!isCustomAuth || lastLoginAt == null || createTime == null) return false;
  final int? loginMs = int.tryParse(lastLoginAt);
  final DateTime? created = DateTime.tryParse(createTime);
  if (loginMs == null || created == null) return false;
  return loginMs >= created.millisecondsSinceEpoch;
}

/// 사용자 목록을 끝 페이지까지 읽어 [authTokens] 의 가입자 수를 [counts] 에 더한다.
///
/// [customAuthLogins] 가 있으면 `customAuth` 가 참인 사용자의 uid → `lastLoginAt`
/// 을 함께 채운다(같은 페이지 읽기). 실패하면 그 결과를, 끝까지 읽으면 null 을
/// 돌려준다.
Future<SignInCountFailed?> _countAuthUsers(
  WizardContext context,
  String projectId,
  Map<String, String> authTokens,
  Map<String, int> counts,
  Map<String, String?>? customAuthLogins,
) async {
  for (final String token in authTokens.keys) {
    counts[token] = 0;
  }
  String? pageToken;
  for (var page = 0; page < RunStep.maxPages; page++) {
    final RestResponse response = await context.rest.send(
      RunStep.buildBatchGetRequest(projectId, pageToken: pageToken),
    );
    final _Page page = _readPage(response, '로그인 사용자 목록');
    final Map<String, Object?>? decoded = page.body;
    if (decoded == null) return page.failed;
    final Object? users = decoded['users'];
    if (users is List<Object?>) {
      for (final Object? user in users) {
        final Set<String> providerIds = _readProviderIds(user);
        for (final MapEntry<String, String> entry in authTokens.entries) {
          if (providerIds.contains(entry.value)) {
            counts[entry.key] = counts[entry.key]! + 1;
          }
        }
        if (customAuthLogins != null) {
          _collectCustomAuthLogin(user, customAuthLogins);
        }
      }
    }
    final Object? next = decoded['nextPageToken'];
    if (next is! String || next.isEmpty || next == pageToken) break;
    pageToken = next;
  }
  return null;
}

/// identity_index 를 끝 페이지까지 읽어 [indexTokens] 의 가입자 수를 [counts] 에
/// 더한다.
///
/// [customAuthLogins] 가 없으면 문서 존재로, 있으면 그 표와 문서 주인 · 생성
/// 시각을 [hasSignedInAfter] 로 대조해 센다(로그인 대조 주소로 읽는다). 실패하면
/// 그 결과를, 끝까지 읽으면 null 을 돌려준다. 컬렉션이 없으면 문서 없는 응답이라
/// 0 이다.
Future<SignInCountFailed?> _countIndexDocuments(
  WizardContext context,
  String projectId,
  Set<String> indexTokens,
  Map<String, int> counts,
  Map<String, String?>? customAuthLogins,
) async {
  for (final token in indexTokens) {
    counts[token] = 0;
  }
  final SignInBasis basis = customAuthLogins == null
      ? SignInBasis.registered
      : SignInBasis.signedIn;
  String? pageToken;
  for (var page = 0; page < RunStep.maxPages; page++) {
    final RestResponse response = await context.rest.send(
      buildIdentityIndexRequest(projectId, pageToken: pageToken, basis: basis),
    );
    final _Page page = _readPage(response, 'Firestore identity_index');
    final Map<String, Object?>? decoded = page.body;
    if (decoded == null) return page.failed;
    final Object? documents = decoded['documents'];
    if (documents is List<Object?>) {
      for (final Object? document in documents) {
        final String? provider = _readIndexField(document, 'provider');
        if (provider == null || !indexTokens.contains(provider)) continue;
        if (customAuthLogins != null) {
          final String? ownerUid = _readIndexField(document, 'firebaseUid');
          final bool isSignedIn = hasSignedInAfter(
            isCustomAuth:
                ownerUid != null && customAuthLogins.containsKey(ownerUid),
            lastLoginAt: customAuthLogins[ownerUid],
            createTime: _readCreateTime(document),
          );
          if (!isSignedIn) continue;
        }
        counts[provider] = counts[provider]! + 1;
      }
    }
    final Object? next = decoded['nextPageToken'];
    if (next is! String || next.isEmpty || next == pageToken) break;
    pageToken = next;
  }
  return null;
}

/// 응답 한 페이지의 해석 결과 — 본문 객체 또는 실패 중 하나만 있다.
typedef _Page = ({Map<String, Object?>? body, SignInCountFailed? failed});

/// [target] 응답 한 페이지를 JSON 객체로 해석한다.
///
/// 실패 응답은 오류 설명뿐이라 원문을 결과에 담는다 — 사용자 목록이 아니다.
/// 해석하지 못한 응답은 본문을 어디에도 싣지 않는다.
_Page _readPage(RestResponse response, String target) {
  if (!response.isOk) {
    return (
      body: null,
      failed: SignInCountFailed(
        '$target 을 읽지 못했습니다 — ${describeRestStatus(response)}',
        toFailureResult(response),
      ),
    );
  }
  final Object? decoded = response.decodeJson();
  if (decoded is! Map<String, Object?>) {
    return (
      body: null,
      failed: SignInCountFailed('$target 응답을 해석하지 못했습니다', null),
    );
  }
  return (body: decoded, failed: null);
}

/// 사용자 하나의 `providerUserInfo[].providerId` 를 모은다 — 모양이 다르면 빈 집합.
Set<String> _readProviderIds(Object? user) {
  if (user is! Map<String, Object?>) return const <String>{};
  final Object? providers = user['providerUserInfo'];
  if (providers is! List<Object?>) return const <String>{};
  return <String>{
    for (final Object? provider in providers)
      if (provider is Map<String, Object?> && provider['providerId'] is String)
        provider['providerId']! as String,
  };
}

/// 사용자 하나가 `customAuth` 참이면 uid → `lastLoginAt`(없으면 null) 을
/// [logins] 에 넣는다 — 모양이 다르거나 `customAuth` 가 참이 아니면 넣지 않는다.
void _collectCustomAuthLogin(Object? user, Map<String, String?> logins) {
  if (user is! Map<String, Object?>) return;
  final Object? uid = user['localId'];
  if (uid is! String || user['customAuth'] != true) return;
  final Object? lastLoginAt = user['lastLoginAt'];
  logins[uid] = lastLoginAt is String ? lastLoginAt : null;
}

/// identity_index 문서 하나의 `fields.<field>.stringValue` 를 읽는다 — 없으면 null.
String? _readIndexField(Object? document, String field) {
  if (document is! Map<String, Object?>) return null;
  final Object? fields = document['fields'];
  if (fields is! Map<String, Object?>) return null;
  final Object? entry = fields[field];
  if (entry is! Map<String, Object?>) return null;
  final Object? value = entry['stringValue'];
  return value is String ? value : null;
}

/// identity_index 문서 하나의 메타데이터 `createTime` 을 읽는다 — 없으면 null.
String? _readCreateTime(Object? document) {
  if (document is! Map<String, Object?>) return null;
  final Object? createTime = document['createTime'];
  return createTime is String ? createTime : null;
}
