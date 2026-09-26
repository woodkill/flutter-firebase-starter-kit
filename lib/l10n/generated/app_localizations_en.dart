// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Flutter Starter Kit';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCopied => 'Copied to clipboard';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonLoading => 'Loading';

  @override
  String get authSocialSigningIn => 'Signing you in…';

  @override
  String get homeEnvironmentInfo => 'Environment Info';

  @override
  String get homeThemeMode => 'Theme Mode';

  @override
  String get homeLanguage => 'Language';

  @override
  String get homeThemeLight => 'Light';

  @override
  String get homeThemeSystem => 'System';

  @override
  String get homeThemeDark => 'Dark';

  @override
  String get homeColorPalette => 'Color Palette';

  @override
  String get homeColorGroupPrimary => 'Primary';

  @override
  String get homeColorGroupSecondary => 'Secondary';

  @override
  String get homeColorGroupTertiary => 'Tertiary';

  @override
  String get homeColorGroupError => 'Error';

  @override
  String get homeColorGroupSurface => 'Surface';

  @override
  String get homeColorGroupOutline => 'Outline & Utility';

  @override
  String get homeTypography => 'Typography';

  @override
  String get homeSpacing => 'Spacing';

  @override
  String get homeBuildEnvironment => 'Build Environment';

  @override
  String get homeEnvFlavor => 'Flavor';

  @override
  String get homeEnvAppName => 'App Name';

  @override
  String get homeEnvFirebase => 'Firebase';

  @override
  String get homeEnvFirebaseProjectId => 'Firebase Project ID';

  @override
  String get homeFirebaseConnected => 'Connected';

  @override
  String get homeFirebaseNotConnected => 'Not Connected';

  @override
  String get homeFirebaseStatusConnected => 'Firebase Connected';

  @override
  String get homeFirebaseStatusNotConnected => 'Firebase Not Connected';

  @override
  String get homeFirebaseProjectIdPlaceholderWarning =>
      'Firebase Project ID is a placeholder. Replace it in the flavor config JSON before building.';

  @override
  String get languageChanged => 'Language changed';

  @override
  String get errorNetworkTimeout => 'Connection timed out. Please try again.';

  @override
  String get errorNoInternet => 'No internet connection.';

  @override
  String get errorRequestTimeout => 'Request timed out. Please try again.';

  @override
  String get errorInvalidCredentials => 'Invalid email or password.';

  @override
  String get errorUserNotFound => 'User not found.';

  @override
  String get errorEmailAlreadyInUse => 'Email is already in use.';

  @override
  String get errorWeakPassword => 'Password is too weak.';

  @override
  String get errorSessionExpired => 'Session expired. Please sign in again.';

  @override
  String get errorInternalServer =>
      'Something went wrong. Please try again later.';

  @override
  String get errorServiceUnavailable => 'Service is temporarily unavailable.';

  @override
  String get errorInvalidEmail => 'This email address is not valid.';

  @override
  String get errorUserDisabled =>
      'This account has been disabled. Contact support.';

  @override
  String get errorTooManyRequests =>
      'Too many attempts. Please try again later.';

  @override
  String get errorUnknown => 'An unknown error occurred.';

  @override
  String get errorUnauthenticated =>
      'You need to be signed in to do that. Please sign in and try again.';

  @override
  String get errorEmailRequired => 'Enter your email address.';

  @override
  String get errorInvalidEmailFormat => 'Enter a valid email address.';

  @override
  String get errorPasswordTooShort => 'Password must be at least 8 characters.';

  @override
  String get errorDisplayNameRequired => 'Enter your name.';

  @override
  String get errorDisplayNameTooLong => 'Name must be 32 characters or fewer.';

  @override
  String get errorNotFoundTitle => 'Page not found';

  @override
  String get errorNotFoundBody => 'The page you requested does not exist.';

  @override
  String get errorNotFoundGoHomeCta => 'Go home';

  @override
  String get authLoginTitle => 'Sign in';

  @override
  String get authSignupTitle => 'Create account';

  @override
  String get authForgotTitle => 'Reset password';

  @override
  String get authLoginEmailLabel => 'Email';

  @override
  String get authLoginPasswordLabel => 'Password';

  @override
  String get authSignupDisplayNameLabel => 'Display name';

  @override
  String get authForgotDescription =>
      'We\'ll send a password reset email to your account.';

  @override
  String get authLoginCta => 'Sign in';

  @override
  String get authSignupCta => 'Create account';

  @override
  String get authForgotCta => 'Send reset email';

  @override
  String get authLoginForgotPassword => 'Forgot your password?';

  @override
  String get authLoginNoAccount => 'No account? Create one';

  @override
  String get authSignupHasAccount => 'Already have an account? Sign in';

  @override
  String get authForgotSent =>
      'Password reset email has been sent. Check your inbox.';

  @override
  String get authAccountSectionTitle => 'Account';

  @override
  String get authAccountDisplayName => 'Display Name';

  @override
  String get authAccountEmail => 'Email';

  @override
  String get authAccountPhotoUrl => 'Profile Photo';

  @override
  String get authAccountUid => 'User ID';

  @override
  String get authAccountCreatedAt => 'Created at';

  @override
  String get authAccountSignUpMethod => 'Sign-up method';

  @override
  String get authAccountLinkedAccounts => 'Linked accounts';

  @override
  String get authAccountLinkedAccountsNone => 'None';

  @override
  String get authAccountProviderEmailPassword => 'Email / Password';

  @override
  String get authAccountCopyToken => 'Copy ID token';

  @override
  String get authAccountCopied => 'Copied to clipboard.';

  @override
  String get authAccountSignOut => 'Sign out';

  @override
  String get debugAuthTokenUnavailable => 'ID token unavailable (debug)';

  @override
  String get debugAuthTokenCopiedWarning =>
      'ID token copied — debug only. Do not share; it stays readable by other apps until it expires (1 hour).';

  @override
  String get authLogoutConfirmTitle => 'Sign out';

  @override
  String get authLogoutConfirmMessage => 'Are you sure you want to sign out?';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authVerifyEmailTitle => 'Verify your email';

  @override
  String authVerifyEmailDescription(String email) {
    return 'We sent a verification email to $email. Click the link in the email to verify your account.';
  }

  @override
  String get authVerifyEmailDescriptionNoEmail =>
      'We sent a verification email to your registered address. Click the link in the email to verify your account.';

  @override
  String get authVerifyEmailSpamHint =>
      'If you don\'t see the email, check your spam folder.';

  @override
  String get authVerifyEmailCheck => 'I\'ve verified my email';

  @override
  String get authVerifyEmailResend => 'Resend verification email';

  @override
  String authVerifyEmailResendCooldown(int seconds) {
    return 'Resend available in ${seconds}s';
  }

  @override
  String get authVerifyEmailLogout => 'Sign in with a different account';

  @override
  String get authVerifyEmailSuccess => 'Email verified successfully.';

  @override
  String showcaseItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String get showcaseDateFormat => 'Date Format';

  @override
  String get showcaseNumberFormat => 'Number Format';

  @override
  String get showcaseCurrentLocale => 'Current Locale';

  @override
  String get showcaseDateShort => 'Short';

  @override
  String get showcaseDateLong => 'Long';

  @override
  String get showcaseDateTime => 'Time';

  @override
  String get showcaseNumberCompact => 'Compact';

  @override
  String get showcaseNumberDecimal => 'Decimal';

  @override
  String get authOrDivider => 'or';

  @override
  String get authGoogleSignIn => 'Sign in with Google';

  @override
  String get errorAccountExistsWithDifferentCredential =>
      'This email is already registered with a different sign-in method. Please sign in with your password.';

  @override
  String get errorAccountExistsWithUnknownProvider =>
      'This email is already registered with another sign-in method. Please sign in with the method you originally used.';

  @override
  String errorAccountExistsWithProvider(String provider) {
    return 'This email is registered with $provider. Sign in with $provider to link your account.';
  }

  @override
  String get authAccountProviderGoogle => 'Google';

  @override
  String get authAppleSignIn => 'Sign in with Apple';

  @override
  String get authAccountProviderApple => 'Apple';

  @override
  String get authFacebookSignIn => 'Login with Facebook';

  @override
  String get authAccountProviderFacebook => 'Facebook';

  @override
  String get authKakaoSignIn => 'Login with Kakao';

  @override
  String get authAccountProviderKakao => 'Kakao';

  @override
  String get authNaverSignIn => 'Log in with NAVER';

  @override
  String get authLineSignIn => 'Log in with LINE';

  @override
  String authBrandAssetMissing(String label) {
    return 'Asset missing: $label';
  }

  @override
  String get authAccountProviderNaver => 'Naver';

  @override
  String get authAccountProviderLine => 'LINE';

  @override
  String get errorUnknownProvider => 'Unknown sign-in method';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String onboardingPageIndicator(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingSlide1Title => 'Get started quickly';

  @override
  String get onboardingSlide1Body =>
      'Explore core features without creating an account.';

  @override
  String get onboardingSlide2Title => 'Kept safe and sound';

  @override
  String get onboardingSlide2Body =>
      'Sign in when you need more, and your data carries over.';

  @override
  String get onboardingSlide3Title => 'Wherever you go';

  @override
  String get onboardingSlide3Body =>
      'The same experience across every language and device.';

  @override
  String get termsAcceptAll => 'Accept all';

  @override
  String get termsRequired => 'Required';

  @override
  String get termsOptional => 'Optional';

  @override
  String get termsService => 'Terms of service';

  @override
  String get termsPrivacy => 'Privacy policy';

  @override
  String get termsMarketing => 'Marketing communications';

  @override
  String get termsViewDetail => 'View';

  @override
  String get termsRequiredError => 'Please agree to all required items.';

  @override
  String get termsDetailServiceTitle => 'Terms of service';

  @override
  String get termsDetailPrivacyTitle => 'Privacy policy';

  @override
  String get termsDetailPlaceholder =>
      'Place your terms content here. Replace this placeholder with the final copy reviewed by your legal team.';

  @override
  String get splashPreparing => 'Getting things ready...';

  @override
  String get splashFailureTitle => 'Can\'t connect right now';

  @override
  String get splashFailureMessage =>
      'Something\'s blocking the connection. You can retry or continue offline.';

  @override
  String get splashContinueOffline => 'Sign in later';

  @override
  String splashErrorCodeFingerprint(String code) {
    return 'Error code: $code';
  }

  @override
  String get homeGuestBanner => 'Browsing as a guest · Sign in to unlock more';

  @override
  String get homeSignIn => 'Sign in';

  @override
  String get homeProtectedExampleTitle => 'Example: this feature needs sign-in';

  @override
  String get homeProtectedExampleBody =>
      'Wrap an action with \'AuthRequired\' to open the sign-in sheet automatically.';

  @override
  String get homeProtectedExampleCta => 'Run protected action';

  @override
  String get authPromptSheetTitle => 'Sign-in required';

  @override
  String get authPromptSheetBody =>
      'You\'ll need an account to keep using this feature.';

  @override
  String get authContinueWithEmail => 'Continue with email';

  @override
  String get accountLinkingDismiss => 'Sign in with another method';

  @override
  String get devToolsSectionTitle => 'Dev Tools';

  @override
  String get devToolsSectionDescription =>
      'Developer tools, visible in debug builds only.';

  @override
  String get devToolsResetOnboarding => 'Reset onboarding';

  @override
  String get devToolsResetOnboardingDone => 'Onboarding state reset.';

  @override
  String get devToolsTriggerError => 'Send test error';

  @override
  String get devToolsTriggerErrorDone => 'Test error sent to Crashlytics.';

  @override
  String get devToolsTriggerAnalytics => 'Send analytics event';

  @override
  String get devToolsTriggerAnalyticsDone => 'Test analytics event sent.';

  @override
  String get devToolsForceSignOut => 'Force sign out';

  @override
  String get accountLinkingSheetTitle => 'Email already in use';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccountSection => 'My Account';

  @override
  String settingsAccountEmail(String email) {
    return '$email';
  }

  @override
  String get settingsAccountLinkingSection => 'Link an account';

  @override
  String settingsLinkProviderCta(String provider) {
    return 'Link $provider';
  }

  @override
  String accountLinkingSucceededSnackbar(String provider) {
    return 'Linked your $provider account.';
  }

  @override
  String accountLinkingSignInThenLinkHint(String provider) {
    return 'Signed in with your $provider account. You can add other sign-in methods in Settings > Link an account.';
  }

  @override
  String get authReauthRequired =>
      'For security, please sign in again and retry.';

  @override
  String get authReauthTitle => 'Confirm it\'s you';

  @override
  String get authReauthGuide =>
      'For your security, sign in again with the account you\'re currently signed in with.';

  @override
  String get authReauthEmailGuide =>
      'For your security, enter the password for this account.';

  @override
  String get authReauthConfirmCta => 'Confirm';

  @override
  String get authReauthSucceeded => 'You\'re verified. Try that again.';

  @override
  String get errorReauthUserMismatch =>
      'That\'s a different account from the one you\'re signed in with. Try again with the same account.';

  @override
  String get errorReauthMethodUnavailable =>
      'You can\'t confirm it\'s you with this account\'s sign-in methods right now. Try again later.';

  @override
  String get authSignInBlockedByGuestSession =>
      'You\'re browsing as a guest, so this existing account can\'t be signed in here. Please use another sign-in method below.';

  @override
  String get authSignInFailedTransient =>
      'Couldn\'t sign in due to a network or service error. Please try again later.';

  @override
  String get authSignInFailedUnknown =>
      'Couldn\'t sign you in. Please try again later.';

  @override
  String get settingsLinkFailedAlreadyLinked =>
      'This sign-in method is already linked to another account. Unlink it first, then try again.';

  @override
  String get settingsLinkFailedAlreadyLinkedHere =>
      'This account is already linked to that sign-in method.';

  @override
  String get settingsLinkFailedEmailInUse =>
      'This email is already in use by another account.';

  @override
  String get settingsLinkFailedTransient =>
      'Couldn\'t link due to a network or service error. Please try again later.';

  @override
  String get settingsLinkFailedUnknown =>
      'Couldn\'t link your account. Please try again later.';

  @override
  String settingsLinkUnsupportedProvider(String provider) {
    return 'Linking a $provider account isn\'t supported yet.';
  }

  @override
  String get settingsDangerZoneSection => 'Danger zone';

  @override
  String get settingsDangerZoneExplainer => 'These actions cannot be undone.';

  @override
  String get settingsWithdrawalLabel => 'Delete account';

  @override
  String get withdrawalDialogTitle => 'Delete account';

  @override
  String get withdrawalDialogBodyLine1 =>
      'Your account and all data will be permanently deleted.';

  @override
  String get withdrawalDialogBodyLine2 => 'This action cannot be undone.';

  @override
  String get withdrawalDialogBodyLine3 =>
      'To rejoin, you must register again with the same email or the same sign-in method.';

  @override
  String get withdrawalConfirmFieldHint => 'delete';

  @override
  String withdrawalConfirmFieldLabel(String phrase) {
    return 'Type \"$phrase\" to continue.';
  }

  @override
  String get withdrawalConfirmAction => 'Delete';

  @override
  String get withdrawalReauthRequired =>
      'For security, please sign in again and retry.';

  @override
  String get withdrawalSuccess => 'Account deleted.';

  @override
  String get withdrawalFailure => 'Could not delete account. Please try again.';

  @override
  String get withdrawalFailureTransient =>
      'Could not delete account due to a network or service error. Please try again later.';

  @override
  String get withdrawalConfirmActionSemantic =>
      'Withdraw account — permanent deletion, cannot be undone';
}
