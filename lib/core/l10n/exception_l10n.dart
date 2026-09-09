import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/provider_id.dart';
import '../error/app_exception.dart';

/// [AppException]의 [AppException.userMessage] ARB 키를
/// 현재 로케일의 번역 문자열로 변환한다.
///
/// [AppException.userMessage]에 저장된 ARB 키 문자열을
/// [AppLocalizations]에서 룩업하여 번역된 메시지를 반환한다.
/// 매칭되지 않는 키는 원본 문자열을 그대로 반환한다.
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
    final other => other,
  };
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
