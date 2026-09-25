import 'package:freezed_annotation/freezed_annotation.dart';

import 'terms_acceptance.dart';

part 'terms_state.freezed.dart';

/// `TermsNotifier` 가 노출하는 불변 state (quick 260920-b28).
///
/// 약관 게이트가 읽어야 하는 두 값을 한 값 객체로 묶는다 — Notifier 는 public
/// 필드 · getter 없이 **불변 state 만** 노출한다
/// (riverpod_lint `avoid_public_notifier_properties` 의 규칙 의도).
///
/// freezed 가 만드는 구조적 `==` 가 필수다. 동등성이 없으면 Riverpod 의
/// `updateShouldNotify` 기본 구현이 매 publish 를 "변경" 으로 보고
/// `resolveAuthRedirect` 재평가가 폭증한다.
@freezed
abstract class TermsState with _$TermsState {
  /// 약관 state 를 생성한다. 두 필드 모두 "아직 알려지지 않음" 을 뜻하는
  /// `null` 이 기본값이다 (cold-start).
  const factory TermsState({
    /// 현재 사용자의 약관 동의 기록. `null` 은 미동의 또는 logout 직후를
    /// 뜻하며 `resolveAuthRedirect` 분기 (3)(5) 의 `termsAccepted=false` 다.
    ///
    /// `TermsNotifier` 의 내부 캐시 `_acceptance` 와 **같은 원본**이다 —
    /// 캐시 갱신 직후 항상 같은 publish helper 가 호출되므로 Custom Token
    /// payload 값과 `mirrorToFirestore` 가 쓰는 값이 갈라질 수 없다
    /// (Phase 16 G-16-A9-1).
    TermsAcceptance? acceptance,

    /// 가장 최근 `TermsNotifier.reloadForUser` 가 로드한 uid
    /// (Issue #7 C-1 — Plan 10-11 stale 가드).
    ///
    /// `resolveAuthRedirect` 분기 (5) 는 본 값이 `currentUser.uid` 와
    /// 일치하는 경우에만 [acceptance] 를 신뢰한다. UID 는 일치하지만 reload
    /// 가 아직 완료되지 않은 시점의 stale 평가를 차단하여 오진 리다이렉트
    /// (/onboarding flash) 를 방지한다. `null` 은 "한 번도 reload 된 적 없음"
    /// (cold-start) 또는 "직전에 uid=null 로 reload 되어 logout 상태" 를
    /// 의미한다.
    String? lastReloadedUid,
  }) = _TermsState;
}

/// Custom Token callable payload 파생 (Phase 16 G-16-A9-1 / CR-01).
extension TermsStatePayload on TermsState {
  /// Custom Token callable payload 로 전송할 `termsAcceptanceSnapshot` JSON 을
  /// 만든다 (Phase 16 CR-01 — timezone 정합성 고정).
  ///
  /// 3 Custom Token provider (kakao/naver/line) 로 보내는 payload 를
  /// `AuthRepository` 가 콜백으로 읽는다. notifier 의 getter 가 아니라 state
  /// 의 순수 파생이므로, payload 값과 `TermsNotifier.mirrorToFirestore` 가
  /// 쓰는 값은 언제나 같은 원본([TermsState.acceptance])에서 나온다.
  ///
  /// [TermsAcceptance.toJson] 을 그대로 쓰면 안 된다. `TermsNotifier.accept`
  /// 는 `DateTime.now()` (**local**) 로 [TermsAcceptance.acceptedAt] 을 만들고,
  /// Dart 의 `toIso8601String()` 은 UTC 가 아닌 `DateTime` 에 타임존 지시자를
  /// 붙이지 않는다 (`2026-09-07T23:30:38.738305`). 서버(Cloud Functions,
  /// TZ=UTC) 는 `new Date(...)` 로 offset 없는 문자열을 **런타임 local = UTC**
  /// 로 해석하므로, KST 사용자의 동의 시각이 9시간 미래로 기록된다.
  ///
  /// 따라서 직렬화 시점에 `DateTime.toUtc` 로 정규화해 항상 `Z` 접미
  /// (절대 instant) 문자열을 전송한다. 이 정규화로 Custom Token 경로와
  /// `TermsNotifier.mirrorToFirestore` (`Timestamp.fromDate` — local
  /// `DateTime` 도 정확한 instant 로 변환) 의 기준이 일치한다.
  ///
  /// 정규화 책임은 [TermsAcceptanceServerJson.toServerJson] 확장 1곳에 모은다
  /// (WR-05) — 계약 sentinel 테스트가 같은 메서드를 통과해야 fixture drift 가
  /// 없다. 동의 기록이 없으면 `null` (payload 미부착).
  Map<String, dynamic>? buildAcceptanceSnapshotJson() =>
      acceptance?.toServerJson();
}
