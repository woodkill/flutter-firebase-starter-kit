import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';
import '../error/app_exception.dart';

/// [AppException]의 [AppException.userMessage] ARB 키를
/// 현재 로케일의 번역 문자열로 변환한다.
///
/// [AppException.userMessage]에 저장된 ARB 키 문자열을
/// [AppLocalizations]에서 룩업하여 번역된 메시지를 반환한다.
/// 매칭되지 않는 키는 원본 문자열을 그대로 반환한다.
String resolveExceptionMessage(BuildContext context, AppException exception) {
  final l10n = AppLocalizations.of(context);
  // (Phase 9.2 D-13 — Path A-narrow) AccountExistsWithDifferentCredential
  // 인스턴스는 항상 unknown fallback 메시지로 단일 경로 매핑한다 (R2).
  // _mapAuthException 의 'account-exists-with-different-credential' 분기 +
  // _mapFunctionsException 의 'already-exists' 분기 (Phase 12.1 R3 — D-34)
  // 모두 동일 경로.
  // Phase 17 (Account Linking) — see ROADMAP.md 부활 시 본 분기 안에서
  // exception.provider (AccountProvider enum) 검사 + arbKey 이중 lookup
  // (D-14) 도입.
  if (exception is AccountExistsWithDifferentCredential) {
    return l10n.errorAccountExistsWithUnknownProvider;
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
    // line 22-24 의 instance type-check 이 모든
    // AccountExistsWithDifferentCredential 을 흡수하므로 본 분기는 unreachable.
    // Phase 17 (Account Linking) 부활 시 provider-aware 메시지 dispatch 로
    // 활용된다 — ARB key + generated getter + present switch arm 3-tier
    // 인프라 유지.
    'errorAccountExistsWithDifferentCredential' =>
      l10n.errorAccountExistsWithDifferentCredential,
    'errorUnknown' => l10n.errorUnknown,
    final other => other,
  };
}
