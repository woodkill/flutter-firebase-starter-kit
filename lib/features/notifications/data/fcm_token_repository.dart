import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/guard_result.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/fcm_token.dart';

part 'fcm_token_repository.g.dart';

/// `users/{uid}/fcmTokens` 타입 안전 저장소 (Phase 17 D-14).
///
/// 「`withConverter` + Freezed + [Result]」 저장소 패턴의 킷 예제다 —
/// 컬렉션 참조가 [FcmToken] 으로 타입이 고정되어 있어 쓰기 · 읽기 모두 raw
/// map 을 다루지 않는다(raw map 을 쓰는 `terms_notifier` 와 대비).
///
/// 모든 메서드는 [guardResult] 를 거친다 — 예상치 못한 오류는 Crashlytics 에
/// 1회 기록하고 `UnknownException` 으로 돌려준다(D-20 ①). reason 은 코드
/// 경로 상수뿐이며 uid · 토큰 문자열은 넣지 않는다.
///
/// **정식 사용자만 저장한다.** 익명 사용자 차단은 호출부(plan 15 notifier)와
/// `firestore.rules` 의 `isRegular()` 가 2중으로 맡는다.
class FcmTokenRepository {
  /// [FcmTokenRepository] 를 생성한다.
  FcmTokenRepository({
    required FirebaseFirestore firestore,
    required CrashlyticsService crashlytics,
  }) : _firestore = firestore,
       _crashlytics = crashlytics;

  final FirebaseFirestore _firestore;
  final CrashlyticsService _crashlytics;

  /// [uid] 의 fcmTokens 서브컬렉션을 [FcmToken] typed 참조로 돌려준다.
  CollectionReference<FcmToken> _tokens(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('fcmTokens')
      .withConverter<FcmToken>(
        fromFirestore: (snapshot, _) {
          final data = snapshot.data();
          if (data == null) {
            // 쿼리 결과 문서는 항상 데이터가 있다 — 방어용. 문서 id(토큰)는
            // 메시지에 넣지 않는다.
            throw StateError('fcmTokens 문서 데이터가 없다');
          }
          return FcmToken.fromJson(data);
        },
        toFirestore: (token, _) => token.toJson(),
      );

  /// [token] 을 `users/{uid}/fcmTokens/{token.token}` 에 set-merge 로 쓴다.
  ///
  /// 같은 토큰을 다시 등록하면 같은 문서를 덮어쓴다(`updatedAt` ·
  /// `expireAt` 갱신). 토큰이 바뀌었을 때 옛 문서 삭제는 호출부가 [delete] 로
  /// 한다.
  Future<Result<void>> upsert({required String uid, required FcmToken token}) =>
      guardResult(
        'fcm_token_repository_upsert',
        () => _tokens(uid).doc(token.token).set(token, SetOptions(merge: true)),
        crashlytics: _crashlytics,
      );
}

/// [FcmTokenRepository] Provider (Phase 17 D-14).
@Riverpod(keepAlive: true)
FcmTokenRepository fcmTokenRepository(Ref ref) {
  return FcmTokenRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
  );
}
