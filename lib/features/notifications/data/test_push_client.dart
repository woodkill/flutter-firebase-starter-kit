// Phase 17 — see ROADMAP.md (D-05 · D-35 · D-43 · D-44) — Dev Tools
// 「나에게 테스트 알림 보내기」 의 callable `sendTestPush` 클라이언트.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
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
  /// - 그 밖의 실패 → [TestPushFailed].
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
      return TestPushFailed(ServiceUnavailable(cause: e));
    } on Object catch (e, stack) {
      // 예상 밖 오류(응답 형식 등) — reason 은 코드 경로 상수만 (PII 0).
      await _crashlytics.recordError(e, stack, reason: 'test_push_client_send');
      return TestPushFailed(UnknownException(cause: e));
    }
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
