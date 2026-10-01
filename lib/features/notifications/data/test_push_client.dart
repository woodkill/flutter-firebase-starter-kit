// Phase 17 — see ROADMAP.md (D-05 · D-35 · D-43 · D-44) — Dev Tools
// 「나에게 테스트 알림 보내기」 의 callable `sendTestPush` 클라이언트.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/functions/callable_rejection.dart';
import '../../../core/providers/firebase_providers.dart';

part 'test_push_client.g.dart';

/// 테스트 알림 요청 결과 (Phase 17 UI-SPEC (T)).
///
/// Dev Tools 버튼이 `switch` 로 SnackBar 문구를 고른다.
sealed class TestPushOutcome {
  const TestPushOutcome();
}

/// 서버가 [count] 대(≥ 1)의 기기에 알림을 보냈다.
final class TestPushSent extends TestPushOutcome {
  /// 성공 기기 수 [count] 로 결과를 만든다.
  const TestPushSent(this.count);

  /// FCM 이 수락한 기기 수 (서버 `sentCount`).
  final int count;
}

/// 알림을 받을 기기가 없다 (토큰 0 또는 성공 0).
final class TestPushNoDevice extends TestPushOutcome {
  /// 기기 없음 결과를 만든다.
  const TestPushNoDevice();
}

/// 이 환경은 테스트 발송이 꺼져 있다 (서버 D-35 운영 거부).
final class TestPushDisabled extends TestPushOutcome {
  /// 운영 거부 결과를 만든다.
  const TestPushDisabled();
}

/// 그 밖의 실패 — [exception] 의 사용자 문구로 안내한다.
final class TestPushFailed extends TestPushOutcome {
  /// 실패 원인 [exception] 으로 결과를 만든다.
  const TestPushFailed(this.exception);

  /// `showErrorSnackBar` 로 보일 원인.
  final AppException exception;
}

/// callable `sendTestPush` 를 호출해 [TestPushOutcome] 으로 돌려준다
/// (Phase 17 D-05).
///
/// 서버는 호출자 본인의 모든 기기(fcmTokens)로 앱 언어 알림을 보내고 성공
/// 수를 돌려준다. 요청 본문은 보내지 않는다(서버 입력 0 · D-34).
class TestPushClient {
  /// [TestPushClient] 를 생성한다.
  ///
  /// [functions] 가 `null` 이면 Firebase 미초기화 환경(stg · prod placeholder
  /// 등)이다 — 호출 없이 [TestPushFailed] 를 돌려준다. [crashlytics] 는 예상
  /// 밖 오류를 non-fatal 로 남기는 채널이다.
  TestPushClient({
    required FirebaseFunctions? functions,
    required CrashlyticsService crashlytics,
  }) : _functions = functions,
       _crashlytics = crashlytics;

  final FirebaseFunctions? _functions;
  final CrashlyticsService _crashlytics;

  /// 테스트 알림을 요청하고 결과를 돌려준다. 예외를 던지지 않는다.
  ///
  /// - 응답 `sentCount` ≥ 1 → [TestPushSent], 0 → [TestPushNoDevice].
  /// - callable 거부 → [_mapRejection] (운영 거부 · App Check · code 순).
  /// - 예상 밖 오류(응답 형식 등) → Crashlytics 1회 + [UnknownException].
  Future<TestPushOutcome> send() async {
    final functions = _functions;
    if (functions == null) {
      return const TestPushFailed(ServiceUnavailable());
    }
    try {
      final result = await functions
          .httpsCallable('sendTestPush')
          .call<Object?>();
      final count = _readSentCount(result.data);
      return count > 0 ? TestPushSent(count) : const TestPushNoDevice();
    } on FirebaseFunctionsException catch (e) {
      return _mapRejection(e);
    } on Object catch (e, stack) {
      // 예상 밖 오류(응답 형식 등) — reason 은 코드 경로 상수만 (PII 0).
      await _crashlytics.recordError(e, stack, reason: 'test_push_client_send');
      return TestPushFailed(UnknownException(cause: e));
    }
  }

  /// callable 거부 [e] 를 [TestPushOutcome] 으로 바꾼다.
  ///
  /// 판정 순서 (Phase 17 D-35 · D-43 · D-44 — 앞 단계가 이긴다):
  /// 1. `failed-precondition` + `details.reason == 'test_push_disabled'` →
  ///    [TestPushDisabled] (서버 환경 스위치 꺼짐 · D-35).
  /// 2. `classifyAppCheckRejection` — SDK 계층 거부(App Check 차단 · 무효 ID
  ///    token)면 [AppCheckFailedException] + Crashlytics non-fatal 1회
  ///    (reason `app_check_rejected_sendTestPush` · D-44).
  /// 3. code switch: `resource-exhausted` → [TooManyRequests] (서버 rate
  ///    limit 10회/60초) · `unavailable` / `deadline-exceeded` →
  ///    [NoInternetConnection] · 그 밖 → [ServiceUnavailable].
  ///
  /// 서버 message 는 읽지 않는다 — 판별은 `code` + `details.reason` 만 본다
  /// (IN-04 · SDK 상수 판정은 helper 안).
  TestPushOutcome _mapRejection(FirebaseFunctionsException e) {
    final details = e.details;
    // 1. 서버가 reason 으로 지목한 운영 거부 — helper 보다 먼저 판정한다.
    if (e.code == 'failed-precondition' &&
        details is Map &&
        details['reason'] == 'test_push_disabled') {
      return const TestPushDisabled();
    }
    // 2. Phase 17 D-43 — SDK 계층 거부(App Check 차단). 호출 머리(helper ·
    // 대상 · callable 이름)를 한 줄로 유지해 helper 경유 지점을 grep 한 번으로
    // 계수할 수 있게 한다(plan 17-18 verify).
    // dart format off
    final appCheck = classifyAppCheckRejection(e, callable: 'sendTestPush',
        crashlytics: _crashlytics);
    // dart format on
    if (appCheck != null) return TestPushFailed(appCheck);
    return TestPushFailed(switch (e.code) {
      'resource-exhausted' => TooManyRequests(cause: e),
      'unavailable' || 'deadline-exceeded' => NoInternetConnection(cause: e),
      _ => ServiceUnavailable(cause: e),
    });
  }

  /// 응답 본문에서 `sentCount` 를 읽는다. 형식이 어긋나면 [StateError].
  static int _readSentCount(Object? data) {
    if (data is Map) {
      final raw = data['sentCount'];
      if (raw is int && raw >= 0) return raw;
    }
    throw StateError('sendTestPush 응답에 sentCount 가 없다');
  }
}

/// [TestPushClient] 를 제공한다 (Phase 17 D-05).
///
/// Firebase 가 초기화되지 않았으면 callable 없이 실패를 돌려주는 인스턴스다
/// (Phase 1 D-13 — 미초기화 환경에서도 Dev Tools 가 깨지지 않는다).
@riverpod
TestPushClient testPushClient(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  return TestPushClient(
    functions: isInitialized ? ref.watch(firebaseFunctionsProvider) : null,
    crashlytics: ref.watch(crashlyticsServiceProvider),
  );
}
