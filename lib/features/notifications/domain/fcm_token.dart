import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/firestore/timestamp_converter.dart';

part 'fcm_token.freezed.dart';
part 'fcm_token.g.dart';

/// FCM 토큰 문서의 만료 기간 (Phase 17 D-33).
///
/// FCM 공식 「registration token 관리」 문서는 한 달 동안 연결되지 않은
/// 기기를 stale 로 본다 — 샘플도 30일을 쓴다(RESEARCH R-02). 앱을 열 때마다
/// `expireAt` 을 이 기간만큼 뒤로 밀고, Firestore TTL 정책이 지난 문서를
/// 지운다.
///
/// **커스터마이징 포인트:** 만료 기간을 바꾸려면 이 상수 1개만 고친다.
const Duration kFcmTokenTtl = Duration(days: 30);

/// 토큰 문서가 지원하는 locale 집합 (D-31 · `firestore.rules` 와 같음).
const Set<String> _supportedFcmLocales = {'ko', 'en', 'ja'};

/// 기기 언어 코드를 토큰 문서 `locale` 값으로 정규화한다 (D-31).
///
/// `ko` · `en` · `ja` 는 그대로, 그 밖의 언어(미지원)는 `en` 으로 돌려준다 —
/// 서버 발송(plan 18)이 이 값으로 알림 문구 언어를 고른다.
String normalizeFcmLocale(String languageCode) =>
    _supportedFcmLocales.contains(languageCode) ? languageCode : 'en';

/// `users/{uid}/fcmTokens/{token}` 문서 모델 (Phase 17 D-02 · D-14).
///
/// 문서 id 는 [token] 과 같다 — 같은 토큰을 다시 등록하면 같은 문서를
/// 덮어써 중복 문서가 생기지 않는다. 직렬화 키 5개(`token` · `platform` ·
/// `locale` · `updatedAt` · `expireAt`)는 `firestore.rules` 의 fcmTokens
/// `hasOnly` 목록과 정확히 같아야 한다 — 필드를 추가하면 rules 도 함께
/// 고친다.
///
/// [token] 은 그 기기로 알림을 보낼 수 있는 주소다. 로그 · Crashlytics ·
/// 화면에 내보내지 않는다.
@freezed
abstract class FcmToken with _$FcmToken {
  /// [FcmToken] 을 생성한다.
  const factory FcmToken({
    /// FCM registration token. 문서 id 와 같다.
    required String token,

    /// 기기 플랫폼 — `android` 또는 `ios` (rules 지원 집합).
    required String platform,

    /// 알림 문구 언어 — `ko` · `en` · `ja` ([normalizeFcmLocale] 결과).
    required String locale,

    /// 마지막 등록 · 갱신 시각 (Firestore Timestamp).
    @TimestampConverter() required DateTime updatedAt,

    /// TTL 만료 시각 = [updatedAt] + [kFcmTokenTtl] (Firestore Timestamp).
    @TimestampConverter() required DateTime expireAt,
  }) = _FcmToken;

  /// 기기 정보로 저장할 [FcmToken] 을 만든다 (D-33).
  ///
  /// [now] 를 [updatedAt] 으로 쓰고 [expireAt] 은 [now] + [kFcmTokenTtl] 이다.
  /// [locale] 은 [normalizeFcmLocale] 로 정규화한다.
  factory FcmToken.forDevice({
    required String token,
    required String platform,
    required String locale,
    required DateTime now,
  }) => FcmToken(
    token: token,
    platform: platform,
    locale: normalizeFcmLocale(locale),
    updatedAt: now,
    expireAt: now.add(kFcmTokenTtl),
  );

  /// JSON(Firestore 문서 데이터)에서 [FcmToken] 을 만든다.
  factory FcmToken.fromJson(Map<String, dynamic> json) =>
      _$FcmTokenFromJson(json);
}
