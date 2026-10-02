// Phase 17 — see ROADMAP.md (D-24 · D-42 · D-43 · D-44) — 모든 callable 오류
// 매퍼가 공유하는 App Check 차단 판정 helper.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;

import '../crashlytics/crashlytics_service.dart';
import '../error/app_exception.dart';

/// firebase-functions SDK 가 callable 의 계층 검증 거부에 싣는 상수 message.
///
/// **출처 (RESEARCH R-01):** firebase-functions 7.2.5
/// `lib/common/providers/https.js:441-453` — ID token INVALID · App Check
/// INVALID(enforceAppCheck) · App Check MISSING(enforceAppCheck) 세 경로가 모두
/// `new HttpsError("unauthenticated", "Unauthenticated")` 를 details 없이
/// 던진다. message 는 cloud_functions 6.5.0 플러그인(Android · iOS)과
/// platform interface 6.0.7 을 거쳐 [FirebaseFunctionsException.message] 로
/// 그대로 전달된다.
///
/// **IN-04 원칙의 예외 1건.** 킷은 서버 taxonomy message 로 분기하지 않는다
/// (`code` + `details.reason` 만). 이 상수는 서버 코드가 아니라 SDK 가 만든
/// 값이라 예외로 둔다. 서버가 같은 문자열을 message 로 쓰지 않는다는 전제는
/// `functions/test/unauthenticated_message_sentinel.test.ts` 가 잠그고, 같은
/// sentinel 이 SDK 설치본의 throw 3회도 pin 해 SDK 상향 시 판별자 변경을
/// 조기에 드러낸다. lib 에서 이 리터럴은 이 파일 한 곳뿐이다.
const String kSdkUnauthenticatedMessage = 'Unauthenticated';

/// [e] 가 firebase-functions SDK 계층 검증 거부인지 판정한다.
///
/// 조건 3요소 = `code == 'unauthenticated'` · `details == null` · message 가
/// [kSdkUnauthenticatedMessage]. 서버가 스스로 던지는 `unauthenticated`
/// (`errorUnauthenticated` · `errorInvalidCredentials` ·
/// `errorReauthenticationRequired` + `details.reason`)는 모두 이 조건에서
/// 빠진다.
///
/// **의미 (Pitfall 1):** 「SDK 계층 검증 거부」 — App Check 토큰 무효/부재
/// **또는** ID token 무효(계정 비활성화 · 폐기 토큰 등. 만료 토큰은 클라이언트
/// SDK 가 자동 갱신하므로 드묾). SDK 가 세 경로에 같은 throw 를 쓰므로
/// 클라이언트는 둘을 가를 수 없고, 안내 문구(재시도 → 계속되면 업데이트 ·
/// D-42)는 둘 모두에 무해하다.
bool isSdkLayerUnauthenticated(FirebaseFunctionsException e) =>
    e.code == 'unauthenticated' &&
    e.details == null &&
    e.message == kSdkUnauthenticatedMessage;

/// callable 거부 [e] 가 App Check 차단([isSdkLayerUnauthenticated])이면
/// [AppCheckFailedException] 을, 아니면 `null` 을 돌려준다 (Phase 17 D-43).
///
/// 매퍼는 「서버 `details.reason` 분기 → 이 helper → 기존 code switch」 순서로
/// 호출한다. reason 이 있는 거부는 details 가 null 이 아니라 여기서 판정되지
/// 않지만, 의미 순서를 코드로도 드러내기 위해 reason 분기를 먼저 둔다.
///
/// 판정이면 [crashlytics] 에 non-fatal 을 정확히 1회 기록한다 (D-44).
/// reason 은 `app_check_rejected_<callable>` 이고 [callable] 은 호출부가 넘기는
/// export 이름 상수다 — 서버 message · details 본문 · 토큰은 reason 에 넣지
/// 않는다(PII 0). 기록은 best-effort 라 기다리지 않는다
/// ([CrashlyticsService] 는 예외를 던지지 않는다). 판정이 아니면 기록 0.
/// 스택은 예외의 원 스택([FirebaseException.stackTrace] — method channel 이
/// 호출 지점 스택을 싣는다)을 쓰고, 없을 때만 이 helper 호출 지점이다
/// (리뷰 IN-08).
AppCheckFailedException? classifyAppCheckRejection(
  FirebaseFunctionsException e, {
  required String callable,
  required CrashlyticsService crashlytics,
}) {
  if (!isSdkLayerUnauthenticated(e)) return null;
  unawaited(
    crashlytics.recordError(
      e,
      e.stackTrace ?? StackTrace.current,
      reason: 'app_check_rejected_$callable',
      fatal: false,
    ),
  );
  return AppCheckFailedException(cause: e);
}
