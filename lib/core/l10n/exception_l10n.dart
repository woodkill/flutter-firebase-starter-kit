import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/provider_id.dart';
import '../error/app_exception.dart';
import 'l10n_extensions.dart';

/// [AppException]의 [AppException.userMessage] ARB 키를
/// 현재 로케일의 번역 문자열로 변환한다.
///
/// - 입력: [AppException]. [AccountExistsWithDifferentCredential] 인스턴스는
///   provider-aware 분기(`_resolveAccountExists`)가 먼저 흡수한다.
/// - 출력: [AppException.userMessage] ARB 키에 대응하는 현재 로케일 문자열.
/// - 미매핑 키: `_resolveUnmappedFallback` 이 처리하며, ARB 키 문자열이
///   사용자 화면에 노출되는 경로는 없다.
///
/// 새 [AppException] 서브타입을 추가하면 아래 switch 에 arm 도 함께 등록할 것
/// — 누락은 `exception_l10n_test.dart` 의 3자 정합 테스트가 RED 로 잡는다.
/// 재발 이력과 근거는 `.planning/phases/**/REVIEW-FIX.md` 참조.
String resolveExceptionMessage(BuildContext context, AppException exception) {
  final l10n = context.l10n;
  // existingProvider 유무로 메시지가 갈리므로 전용 헬퍼에 위임한다 (Phase 16
  // D-12).
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
    // 위 instance type-check 가 모두 흡수하므로 unreachable. ARB+getter+arm
    // 인프라 유지를 위한 의도적 dead-code anchor (Phase 9.2 D-13).
    'errorAccountExistsWithDifferentCredential' =>
      l10n.errorAccountExistsWithDifferentCredential,
    'errorUnknown' => l10n.errorUnknown,
    // ProviderAlreadyLinkedToThisAccount (`provider-already-linked`).
    'settingsLinkFailedAlreadyLinkedHere' =>
      l10n.settingsLinkFailedAlreadyLinkedHere,
    // ProviderNotLinked (native `no-such-provider` · callable `not-found`).
    'settingsUnlinkFailedAlreadyUnlinked' =>
      l10n.settingsUnlinkFailedAlreadyUnlinked,
    // UnlinkLastCredentialRejected (callable `failed-precondition` +
    // `details.reason: 'last_credential'`).
    'settingsUnlinkFailedLastCredential' =>
      l10n.settingsUnlinkFailedLastCredential,
    // AccountAlreadyLinked (`credential-already-in-use`).
    'errorAccountExistsWithUnknownProvider' =>
      l10n.errorAccountExistsWithUnknownProvider,
    // ReauthenticationRequiredException — 도메인 중립 공용 키로 매핑한다
    // (전용 키 분리 계약은 reauth_key_consumer_sentinel_test.dart 가 잠근다).
    'errorReauthenticationRequired' => l10n.authReauthRequired,
    // UnauthenticatedException.
    'errorUnauthenticated' => l10n.errorUnauthenticated,
    // ReauthUserMismatch — 재인증 계정이 현재 계정과 다름 (Q2 배너).
    'errorReauthUserMismatch' => l10n.errorReauthUserMismatch,
    // ReauthMethodUnavailable — 재인증 수단 0 (Q7 배너).
    'errorReauthMethodUnavailable' => l10n.errorReauthMethodUnavailable,
    final other => _resolveUnmappedFallback(l10n, other),
  };
}

/// 매핑 표에 없는 [AppException.userMessage] 키를 처리한다.
///
/// debug 빌드에서는 [assert] 로 즉시 실패시켜 매핑 누락을 개발 중에 드러낸다.
/// profile/release 는 AOT 컴파일로 [assert] 가 제거되므로 둘 다 `errorUnknown`
/// 강등 경로를 탄다 — 어느 쪽이든 **ARB 키 문자열이 사용자에게 노출되지
/// 않는다.**
///
/// 이 fallback 이 발동했다면 [resolveExceptionMessage] 의 arm 등록을 잊은
/// 것이다. 근본 해소([AppException.userMessage] 의 enum 승격)는 소비처 폭이
/// 넓어 별도 작업으로 분리했다 — 근거는 REVIEW-FIX.md 참조.
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
/// - `existingProvider != null`: [_resolveProviderLabel] 이 룩업한 provider
///   라벨을 `errorAccountExistsWithProvider` placeholder 에 채운다.
/// - `existingProvider == null`: `errorAccountExistsWithUnknownProvider` 를
///   그대로 노출한다 (Phase 9.2 baseline).
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
/// 7 provider 전부 `authAccountProvider{X}` ARB key 와 매핑되는 단순 dispatch
/// 이며, 라벨 문자열의 verbatim 정확성은 brand_label_whitelist_test 가 잠근다.
String _resolveProviderLabel(AppLocalizations l10n, AccountProvider provider) {
  return switch (provider) {
    AccountProvider.google => l10n.authAccountProviderGoogle,
    AccountProvider.apple => l10n.authAccountProviderApple,
    AccountProvider.facebook => l10n.authAccountProviderFacebook,
    AccountProvider.email => l10n.authAccountProviderEmailPassword,
    AccountProvider.kakao => l10n.authAccountProviderKakao,
    AccountProvider.naver => l10n.authAccountProviderNaver,
    AccountProvider.line => l10n.authAccountProviderLine,
  };
}
