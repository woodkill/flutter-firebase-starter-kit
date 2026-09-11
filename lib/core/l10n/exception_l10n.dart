import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/provider_id.dart';
import '../error/app_exception.dart';

/// [AppException]의 [AppException.userMessage] ARB 키를
/// 현재 로케일의 번역 문자열로 변환한다.
///
/// [AppException.userMessage]에 저장된 ARB 키 문자열을
/// [AppLocalizations]에서 룩업하여 번역된 메시지를 반환한다.
///
/// **매핑 누락 시 동작 (코드 리뷰 WR-06).** 과거에는 마지막 arm 이
/// `final other => other` 여서 **ARB 키 문자열 자체가 사용자 화면에**
/// 렌더됐다. 컴파일도 analyze 도 통과하므로 검출 수단이 실사용뿐이었고,
/// 이 코드베이스에서 최소 4회 재발한 사고다 (아래 WR-03 / WR-04 주석이 그
/// 흔적이다). 지금은 [_resolveUnmappedFallback] 이 debug 에서 즉시 실패시키고
/// release 에서는 `errorUnknown` 으로 강등하여 **식별자 노출 경로를 닫는다.**
String resolveExceptionMessage(BuildContext context, AppException exception) {
  final l10n = AppLocalizations.of(context);
  // (Phase 16 D-12 / Task 4.1) AccountExistsWithDifferentCredential 인스턴스의
  // provider-aware variant 부활. Phase 9.2 P-A-narrow 시점 단일 unknown
  // fallback (R2) 만 노출했으나, Phase 16 의 `lookupSignInMethods` callable
  // wiring (Plan 16-02 + 16-04 Task 4.3) 로 `existingProvider` 가 채워지면
  // L1 provider-aware 메시지를 노출한다.
  //
  // - L1 (provider-aware): existingProvider != null →
  //     errorAccountExistsWithProvider({provider}) 로 정확한 provider 라벨
  //     (authAccountProvider{X}) 노출.
  // - L2 (unknown fallback): existingProvider == null →
  //     errorAccountExistsWithUnknownProvider (R2 baseline 보존, 회귀 0).
  if (exception is AccountExistsWithDifferentCredential) {
    return _resolveAccountExists(l10n, exception);
  }
  return switch (exception.userMessage) {
    'errorNetworkTimeout' => l10n.errorNetworkTimeout,
    'errorNoInternet' => l10n.errorNoInternet,
    'errorRequestTimeout' => l10n.errorRequestTimeout,
    'errorInvalidCredentials' => l10n.errorInvalidCredentials,
    'errorUserNotFound' => l10n.errorUserNotFound,
    'errorEmailAlreadyInUse' => l10n.errorEmailAlreadyInUse,
    'errorWeakPassword' => l10n.errorWeakPassword,
    'errorSessionExpired' => l10n.errorSessionExpired,
    'errorInternalServer' => l10n.errorInternalServer,
    'errorServiceUnavailable' => l10n.errorServiceUnavailable,
    'errorInvalidEmail' => l10n.errorInvalidEmail,
    'errorUserDisabled' => l10n.errorUserDisabled,
    'errorTooManyRequests' => l10n.errorTooManyRequests,
    // (Phase 9.2 D-13 dead-code anchor — intentional 보존)
    // 위 instance type-check 가 모든 AccountExistsWithDifferentCredential 을
    // 흡수하므로 본 분기는 unreachable. Phase 16 후에도 dead-code anchor 로
    // 보존하여 3-tier ARB+getter+arm 인프라 유지 — 향후 다른 caller 가
    // ARB key 만 가지고 분기에 진입할 가능성에 대비.
    'errorAccountExistsWithDifferentCredential' =>
      l10n.errorAccountExistsWithDifferentCredential,
    'errorUnknown' => l10n.errorUnknown,
    // WR-03: ProviderAlreadyLinkedToThisAccount (`provider-already-linked`).
    // 매핑이 없으면 `final other => other` 로 떨어져 ARB **키 문자열 자체**가
    // 사용자에게 노출된다.
    'settingsLinkFailedAlreadyLinkedHere' =>
      l10n.settingsLinkFailedAlreadyLinkedHere,
    // WR-04 (4차 리뷰) — 아래 3개는 `userMessage` 리터럴이 존재하는데 표에만
    // 없어서 raw key 가 새어 나가던 칸이다. 현 시점 실도달성은 0 이지만
    // FormErrorBanner 는 AppException 을 무제한으로 받는 범용 표면이고
    // (Phase 16 만도 소비처가 2번 늘었다), 잠재 결함으로 두면 다음 표면
    // 추가 시 사용자에게 영문 식별자가 표시된다.
    // AccountAlreadyLinked (`credential-already-in-use`).
    'errorAccountExistsWithUnknownProvider' =>
      l10n.errorAccountExistsWithUnknownProvider,
    // ReauthenticationRequiredException — 전용 ARB 키를 또 만들지 않고 도메인
    // 중립 키인 authReauthRequired 로 매핑한다 (문구가 정확히 그 뜻이며,
    // @authReauthRequired.description 에 본 소비처를 등록해 두었다).
    'errorReauthenticationRequired' => l10n.authReauthRequired,
    // UnauthenticatedException — ARB 키 자체가 없어 신설했다 (WR-04).
    'errorUnauthenticated' => l10n.errorUnauthenticated,
    final other => _resolveUnmappedFallback(l10n, other),
  };
}

/// 매핑 표에 없는 [AppException.userMessage] 키를 처리한다 (WR-06).
///
/// debug/profile 빌드에서는 [assert] 로 즉시 실패시켜 매핑 누락을 개발 중에
/// 드러내고, release 빌드에서는 `errorUnknown` 으로 강등한다. 어느 쪽이든
/// **ARB 키 문자열이 사용자에게 노출되지 않는다.**
///
/// 이 fallback 이 발동했다는 것은 새 [AppException] 서브타입을 추가하면서
/// [resolveExceptionMessage] 의 switch arm 등록을 잊었다는 뜻이다. 근본
/// 해소는 [AppException.userMessage] 를 `String` 대신 enum 으로 승격해 switch
/// 를 exhaustive 하게 만드는 것이며, 그 작업은 소비처 폭이 넓어 별도 작업으로
/// 분리했다 (REVIEW-FIX.md WR-06 참조).
String _resolveUnmappedFallback(AppLocalizations l10n, String key) {
  assert(
    false,
    'resolveExceptionMessage 매핑 누락: "$key" — exception_l10n.dart 의 switch 에 '
    'arm 을 추가할 것. 방치하면 사용자 화면에 영문 식별자가 그대로 렌더된다.',
  );
  return l10n.errorUnknown;
}

/// [AccountExistsWithDifferentCredential] 인스턴스의 provider-aware variant
/// 또는 unknown fallback 메시지를 반환한다 (Phase 16 D-12).
///
/// **L1 (provider-aware):** `existingProvider != null` 일 때, `_resolveProviderLabel`
/// 로 provider 별 정확 라벨 (authAccountProvider{X}) 을 룩업한 뒤
/// `errorAccountExistsWithProvider({provider})` placeholder 에 채운다.
///
/// **L2 (unknown fallback):** `existingProvider == null` 일 때 R2 baseline
/// (`errorAccountExistsWithUnknownProvider`) 노출 — Phase 9.2 회귀 0.
String _resolveAccountExists(
  AppLocalizations l10n,
  AccountExistsWithDifferentCredential exception,
) {
  final provider = exception.existingProvider;
  if (provider != null) {
    return l10n.errorAccountExistsWithProvider(
      _resolveProviderLabel(l10n, provider),
    );
  }
  return l10n.errorAccountExistsWithUnknownProvider;
}

/// [AccountProvider] 를 현재 로케일의 정확 provider 라벨로 변환한다.
///
/// 8 provider (google/apple/facebook/email + kakao/naver/line/yahoojp) 모두
/// `authAccountProvider{X}` ARB key 와 매핑된다. brand_label_whitelist_test
/// (Phase 13.1 / 15 mirror) 가 ARB key 의 verbatim brand 라벨 정확성을
/// 별도 lock — 본 함수는 단순 dispatch.
String _resolveProviderLabel(AppLocalizations l10n, AccountProvider provider) {
  return switch (provider) {
    AccountProvider.google => l10n.authAccountProviderGoogle,
    AccountProvider.apple => l10n.authAccountProviderApple,
    AccountProvider.facebook => l10n.authAccountProviderFacebook,
    AccountProvider.email => l10n.authAccountProviderEmailPassword,
    AccountProvider.kakao => l10n.authAccountProviderKakao,
    AccountProvider.naver => l10n.authAccountProviderNaver,
    AccountProvider.line => l10n.authAccountProviderLine,
    AccountProvider.yahoojp => l10n.authAccountProviderYahooJp,
  };
}
