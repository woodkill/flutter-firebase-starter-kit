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
    'errorAccountExistsWithDifferentCredential' =>
      l10n.errorAccountExistsWithDifferentCredential,
    'errorUnknown' => l10n.errorUnknown,
    final other => other,
  };
}
