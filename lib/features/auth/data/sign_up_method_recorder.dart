import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../terms/presentation/terms_notifier.dart';

part 'sign_up_method_recorder.g.dart';

/// 가입 수단을 Firestore `users/{uid}.signUpProviderId` 에 기록한다
/// (Phase 16.7 D-13 · D-15 · D-28).
///
/// 값 형식은 `User.providerIds` 와 같다 (`'password'` · `'google.com'` ·
/// `'kakao'` 등). 호출처는 `AuthRepository` 의 native 가입 분기이며, 콜백
/// `recordSignUpMethod` 로 주입된다 (D-A2 관례 — `AuthRepository` 본체는 본
/// 타입을 모른다). Custom Token 경로는 서버 `resolveIdentity` 가 기록한다.
///
/// **왜 약관 mirror 가 먼저인가 (D-19 · D-29):**
/// `TermsNotifier.mirrorToFirestore(force: false)` 는 pre-read 로
/// `users/{uid}` 문서가 이미 있으면 skip 한다 (Plan 10-12 multi-user
/// invariant). 가입 수단 set-merge 를 먼저 하면 Firestore latency
/// compensation 이 자기 pending write 를 로컬 읽기에 반영해 pre-read 가
/// `exists == true` 를 보고 약관 mirror 를 skip 한다 → 서버에
/// `termsAccepted` 가 없어 다음 재읽기에서 재동의 화면이 뜬다. 그래서
/// [record] 는 경로 구분 없이 항상 mirror 를 먼저 await 한 뒤 set-merge 한다.
/// mirror 결과(`Result`)는 무시한다 — mirror 내부가 이미 Crashlytics 에
/// 기록하며, 약관 기록이 실패해도 가입 수단 기록은 이어간다.
///
/// **왜 throw 하지 않는가 (D-17):**
/// 호출처는 `unawaited(...)` 로 부른다 — 로그인 흐름은 서버 ack 를 기다리지
/// 않고, 네트워크 실패는 Firestore SDK 오프라인 큐가 재전송한다. 여기서
/// 예외가 새면 zone 의 `runZonedGuarded` 가 치명 오류로 기록하므로, mirror 와
/// set 을 각각 `on Object catch` 로 흡수해 Crashlytics 에 남기고 끝낸다.
/// 앱 레벨 재시도는 하지 않는다. reason 은 경로 식별 상수뿐이며 uid ·
/// providerId 등 사용자 값은 로그 · reason 에 넣지 않는다.
class SignUpMethodRecorder {
  /// 가입 수단 recorder 를 생성한다.
  ///
  /// [mirrorTerms] 는 device-local 약관 동의를 `users/{uid}` 에 mirror 하는
  /// 콜백이다 (production = `TermsNotifier.mirrorToFirestore`).
  SignUpMethodRecorder({
    required FirebaseFirestore firestore,
    required CrashlyticsService crashlytics,
    required Future<void> Function(String uid) mirrorTerms,
  }) : _firestore = firestore,
       _crashlytics = crashlytics,
       _mirrorTerms = mirrorTerms;

  final FirebaseFirestore _firestore;
  final CrashlyticsService _crashlytics;
  final Future<void> Function(String uid) _mirrorTerms;

  /// [uid] 문서에 가입 수단 [providerId] 를 set-merge 로 기록한다.
  ///
  /// 순서 = 약관 mirror await → `signUpProviderId` set-merge (D-19).
  /// 두 단계 어느 쪽이 실패해도 Crashlytics 에 기록하고 정상 완료한다 —
  /// 이 Future 는 절대 에러로 끝나지 않는다 (D-17).
  Future<void> record({required String uid, required String providerId}) async {
    // ① 약관 mirror 선행 — 실패해도 가입 수단 기록은 계속한다.
    try {
      await _mirrorTerms(uid);
    } on Object catch (e, st) {
      await _crashlytics.recordError(
        e,
        st,
        reason: 'sign_up_method_terms_mirror',
      );
    }
    // ② 가입 수단 set-merge — 즉시 던지는 예외(permission-denied 등)만 흡수.
    try {
      await _firestore.collection('users').doc(uid).set(<String, dynamic>{
        'signUpProviderId': providerId,
      }, SetOptions(merge: true));
    } on Object catch (e, st) {
      await _crashlytics.recordError(e, st, reason: 'sign_up_method_record');
    }
  }
}

/// [SignUpMethodRecorder] Provider (Phase 16.7).
///
/// `authRepository` factory 가 `recordSignUpMethod` 콜백 안에서 읽는다.
/// 약관 mirror 는 `termsProvider.notifier` 의 `mirrorToFirestore` 를
/// 그대로 쓴다 — 반환 `Result` 는 무시한다(mirror 내부가 Crashlytics 기록
/// 완료).
@Riverpod(keepAlive: true)
SignUpMethodRecorder signUpMethodRecorder(Ref ref) {
  return SignUpMethodRecorder(
    firestore: ref.watch(firebaseFirestoreProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
    mirrorTerms: (uid) async {
      await ref.read(termsProvider.notifier).mirrorToFirestore(uid: uid);
    },
  );
}
