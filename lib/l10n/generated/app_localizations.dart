import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];

  /// Application title shown in the OS task switcher and accessibility surfaces. Used only when the `appName` dart-define is not injected.
  ///
  /// In en, this message translates to:
  /// **'Flutter Starter Kit'**
  String get appTitle;

  /// Common confirmation button label
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Common cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Common retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// SnackBar message shown after tap-to-copy clipboard action (Phase 10.1 — fingerprint copy)
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get commonCopied;

  /// Common close button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Common save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Common delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Common edit button label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Common loading indicator semantics label
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get commonLoading;

  /// Overlay label shown while a social OAuth flow finishes (user returned from external auth, app is exchanging tokens / persisting profile)
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get authSocialSigningIn;

  /// AppBar title for the environment info screen
  ///
  /// In en, this message translates to:
  /// **'Environment Info'**
  String get homeEnvironmentInfo;

  /// Section title for theme mode toggle
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get homeThemeMode;

  /// Section title for language selection
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get homeLanguage;

  /// Light theme option label
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get homeThemeLight;

  /// System default theme option label
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get homeThemeSystem;

  /// Dark theme option label
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get homeThemeDark;

  /// Section title for color palette showcase
  ///
  /// In en, this message translates to:
  /// **'Color Palette'**
  String get homeColorPalette;

  /// ColorScheme group header label for Primary color family
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get homeColorGroupPrimary;

  /// ColorScheme group header label for Secondary color family
  ///
  /// In en, this message translates to:
  /// **'Secondary'**
  String get homeColorGroupSecondary;

  /// ColorScheme group header label for Tertiary color family
  ///
  /// In en, this message translates to:
  /// **'Tertiary'**
  String get homeColorGroupTertiary;

  /// ColorScheme group header label for Error color family
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get homeColorGroupError;

  /// ColorScheme group header label for Surface color family
  ///
  /// In en, this message translates to:
  /// **'Surface'**
  String get homeColorGroupSurface;

  /// ColorScheme group header label for Outline and Utility color family
  ///
  /// In en, this message translates to:
  /// **'Outline & Utility'**
  String get homeColorGroupOutline;

  /// Section title for typography showcase
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get homeTypography;

  /// Section title for spacing showcase
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get homeSpacing;

  /// Section title for build environment info cards
  ///
  /// In en, this message translates to:
  /// **'Build Environment'**
  String get homeBuildEnvironment;

  /// Environment card label for the build flavor (dev/stg/prod)
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get homeEnvFlavor;

  /// Environment card label for the application display name injected via --dart-define appName
  ///
  /// In en, this message translates to:
  /// **'App Name'**
  String get homeEnvAppName;

  /// Environment card label for the Firebase connection status card
  ///
  /// In en, this message translates to:
  /// **'Firebase'**
  String get homeEnvFirebase;

  /// Environment card label for the Firebase project ID injected via --dart-define firebaseProjectId
  ///
  /// In en, this message translates to:
  /// **'Firebase Project ID'**
  String get homeEnvFirebaseProjectId;

  /// Firebase connection status when connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get homeFirebaseConnected;

  /// Firebase connection status when not connected
  ///
  /// In en, this message translates to:
  /// **'Not Connected'**
  String get homeFirebaseNotConnected;

  /// Semantics label for the Firebase environment card when Firebase is initialized. Includes the 'Firebase' word for screen reader context (distinct from homeFirebaseConnected which is the value-only string).
  ///
  /// In en, this message translates to:
  /// **'Firebase Connected'**
  String get homeFirebaseStatusConnected;

  /// Semantics label for the Firebase environment card when Firebase is NOT initialized. Includes the 'Firebase' word for screen reader context (distinct from homeFirebaseNotConnected which is the value-only string).
  ///
  /// In en, this message translates to:
  /// **'Firebase Not Connected'**
  String get homeFirebaseStatusNotConnected;

  /// Semantics label + visual warning shown on the Firebase Project ID card when the injected firebaseProjectId still starts with 'your-' (Starter Kit placeholder not yet replaced). See REVIEW WR-01.
  ///
  /// In en, this message translates to:
  /// **'Firebase Project ID is a placeholder. Replace it in the flavor config JSON before building.'**
  String get homeFirebaseProjectIdPlaceholderWarning;

  /// Snackbar message confirming the app language was changed successfully. Displayed in the newly selected language.
  ///
  /// In en, this message translates to:
  /// **'Language changed'**
  String get languageChanged;

  /// Error message when network connection times out
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Please try again.'**
  String get errorNetworkTimeout;

  /// Error message when there is no internet connection
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get errorNoInternet;

  /// Error message when a request times out
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please try again.'**
  String get errorRequestTimeout;

  /// Error message for incorrect login credentials
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password.'**
  String get errorInvalidCredentials;

  /// Error message when user account is not found
  ///
  /// In en, this message translates to:
  /// **'User not found.'**
  String get errorUserNotFound;

  /// Error message when email is already registered
  ///
  /// In en, this message translates to:
  /// **'Email is already in use.'**
  String get errorEmailAlreadyInUse;

  /// Error message when password does not meet requirements
  ///
  /// In en, this message translates to:
  /// **'Password is too weak.'**
  String get errorWeakPassword;

  /// Error message when user session has expired
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please sign in again.'**
  String get errorSessionExpired;

  /// Error message for internal server errors
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again later.'**
  String get errorInternalServer;

  /// Error message when service is temporarily down
  ///
  /// In en, this message translates to:
  /// **'Service is temporarily unavailable.'**
  String get errorServiceUnavailable;

  /// Error message when Firebase rejects email format
  ///
  /// In en, this message translates to:
  /// **'This email address is not valid.'**
  String get errorInvalidEmail;

  /// Error message when Firebase reports the account is disabled
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Contact support.'**
  String get errorUserDisabled;

  /// Error message when Firebase rate-limits authentication attempts
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get errorTooManyRequests;

  /// Catch-all error message for unrecognized or unexpected errors
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred.'**
  String get errorUnknown;

  /// Phase 16 WR-04 (4차 리뷰) — UnauthenticatedException 의 사용자 문구. 소비: (1) SettingsRepository.requestAccountDeletion 의 currentUser == null 가드가 throw 하는 UnauthenticatedException 을 Surface C 가 SnackBar 로 렌더, (2) resolveExceptionMessage 의 'errorUnauthenticated' arm (FormErrorBanner 등 AppException 을 무제한으로 받는 범용 표면 전체). **키 신설 근거:** UnauthenticatedException.userMessage 가 가리키는 ARB 키가 존재하지 않아 resolveExceptionMessage 의 `final other => other` 로 떨어지면 번역문이 아니라 식별자 문자열 'errorUnauthenticated' 가 그대로 렌더된다. errorSessionExpired(세션 만료) 와 달리 '애초에 로그인하지 않은 상태' 를 가리키므로 문구를 분리한다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'You need to be signed in to do that. Please sign in and try again.'**
  String get errorUnauthenticated;

  /// Form validation error when the email field is empty
  ///
  /// In en, this message translates to:
  /// **'Enter your email address.'**
  String get errorEmailRequired;

  /// Form validation error when email format is invalid
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get errorInvalidEmailFormat;

  /// Form validation error when password is shorter than the minimum length
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get errorPasswordTooShort;

  /// Form validation error when display name is empty
  ///
  /// In en, this message translates to:
  /// **'Enter your name.'**
  String get errorDisplayNameRequired;

  /// Form validation error when display name exceeds the maximum length
  ///
  /// In en, this message translates to:
  /// **'Name must be 32 characters or fewer.'**
  String get errorDisplayNameTooLong;

  /// Title shown in AppBar and body of the 404 error screen when a deep link hits an unknown route
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get errorNotFoundTitle;

  /// Body text of the 404 error screen explaining the cause
  ///
  /// In en, this message translates to:
  /// **'The page you requested does not exist.'**
  String get errorNotFoundBody;

  /// Label for the recovery button on the 404 error screen that navigates back to home
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get errorNotFoundGoHomeCta;

  /// Login screen AppBar title
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authLoginTitle;

  /// Signup screen AppBar title
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authSignupTitle;

  /// Forgot password screen AppBar title
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get authForgotTitle;

  /// Email input field label on login and signup screens
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authLoginEmailLabel;

  /// Password input field label on login and signup screens
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authLoginPasswordLabel;

  /// Display name input field label on the signup screen
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get authSignupDisplayNameLabel;

  /// Description shown above the forgot password form
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a password reset email to your account.'**
  String get authForgotDescription;

  /// Login screen submit button label
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authLoginCta;

  /// Signup screen submit button label
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authSignupCta;

  /// Forgot password screen submit button label
  ///
  /// In en, this message translates to:
  /// **'Send reset email'**
  String get authForgotCta;

  /// Login screen link to navigate to the forgot password screen
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get authLoginForgotPassword;

  /// Login screen link to navigate to the signup screen
  ///
  /// In en, this message translates to:
  /// **'No account? Create one'**
  String get authLoginNoAccount;

  /// Signup screen link to navigate back to the login screen
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authSignupHasAccount;

  /// Inline confirmation shown on the forgot password screen after a reset request. Uses passive voice to remain neutral about whether the address actually exists (Email Enumeration Protection compliant — see T-06.06-01).
  ///
  /// In en, this message translates to:
  /// **'Password reset email has been sent. Check your inbox.'**
  String get authForgotSent;

  /// Account section title on the home screen for signed-in users
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get authAccountSectionTitle;

  /// Label for the user's display name field in the account section
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get authAccountDisplayName;

  /// Label for the user's email field — home account card label and Settings 'My Account' row title (Phase 16.7 R1: title above the email address).
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authAccountEmail;

  /// Label for the user's profile photo URL field in the account section
  ///
  /// In en, this message translates to:
  /// **'Profile Photo'**
  String get authAccountPhotoUrl;

  /// Label for the Firebase user UID field in the account section
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get authAccountUid;

  /// Label for the account creation date in the account section
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get authAccountCreatedAt;

  /// Phase 16.7 D-08/D-09 (R1) — Label for the sign-up method: the provider that first created the account (fixed afterwards, even when signing in with a linked account). Used as the home account card label and as the Settings 'My Account' row title (value on the line below).
  ///
  /// In en, this message translates to:
  /// **'Sign-up method'**
  String get authAccountSignUpMethod;

  /// Phase 16.7 D-09 (R1) — Label for the providers linked after sign-up (all providers minus the sign-up method). Used as the home account card label and as the Settings 'My Account' row title (value on the line below).
  ///
  /// In en, this message translates to:
  /// **'Linked accounts'**
  String get authAccountLinkedAccounts;

  /// Phase 16.7 D-03 — Value shown for Linked accounts when no provider other than the sign-up method is linked (home card and settings row).
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get authAccountLinkedAccountsNone;

  /// Provider value displayed in the account section when the user signed in with email and password
  ///
  /// In en, this message translates to:
  /// **'Email / Password'**
  String get authAccountProviderEmailPassword;

  /// Account section button label to copy the Firebase ID token to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy ID token'**
  String get authAccountCopyToken;

  /// Snackbar message confirming the ID token was copied to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard.'**
  String get authAccountCopied;

  /// Account section sign-out button label
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authAccountSignOut;

  /// Debug-only snackbar shown when Firebase getIdToken() returns null in the account section
  ///
  /// In en, this message translates to:
  /// **'ID token unavailable (debug)'**
  String get debugAuthTokenUnavailable;

  /// 10-REVIEW IN-05 — Debug-only snackbar shown after _copyIdToken writes a Firebase ID token to the clipboard (environment_info_screen.dart, kDebugMode-guarded surface). **Why a dedicated key:** the clipboard is readable by any other app and a Firebase ID token is a bearer credential valid for one hour, so the confirmation must carry the do-not-share warning and the expiry window. The generic authAccountCopied ('Copied to clipboard.') is retained for _copyUid, which copies a non-secret identifier. Does not embed the token, email, or uid in the message itself.
  ///
  /// In en, this message translates to:
  /// **'ID token copied — debug only. Do not share; it stays readable by other apps until it expires (1 hour).'**
  String get debugAuthTokenCopiedWarning;

  /// Sign-out confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authLogoutConfirmTitle;

  /// Sign-out confirmation dialog message body
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get authLogoutConfirmMessage;

  /// Semantics label for the show-password toggle on password input
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// Semantics label for the hide-password toggle on password input
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// Email verification pending screen title
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get authVerifyEmailTitle;

  /// Email verification pending screen description with email placeholder
  ///
  /// In en, this message translates to:
  /// **'We sent a verification email to {email}. Click the link in the email to verify your account.'**
  String authVerifyEmailDescription(String email);

  /// Phase 9.2 Gap B (HUMAN-UAT 2026-05-11) — fallback description for verifyEmailScreen when currentUser.email is null or empty. Triggered if Custom Token (Kakao/Naver) issues a user without email field. No placeholder — used as-is. Phase 17 (Account Linking) — see ROADMAP.md
  ///
  /// In en, this message translates to:
  /// **'We sent a verification email to your registered address. Click the link in the email to verify your account.'**
  String get authVerifyEmailDescriptionNoEmail;

  /// Hint text suggesting the user check their spam folder
  ///
  /// In en, this message translates to:
  /// **'If you don\'t see the email, check your spam folder.'**
  String get authVerifyEmailSpamHint;

  /// Button label to check email verification status
  ///
  /// In en, this message translates to:
  /// **'I\'ve verified my email'**
  String get authVerifyEmailCheck;

  /// Button label to resend the verification email
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get authVerifyEmailResend;

  /// Cooldown timer text showing seconds until resend is available
  ///
  /// In en, this message translates to:
  /// **'Resend available in {seconds}s'**
  String authVerifyEmailResendCooldown(int seconds);

  /// Link label to sign out and use a different account
  ///
  /// In en, this message translates to:
  /// **'Sign in with a different account'**
  String get authVerifyEmailLogout;

  /// Success message shown after email verification is confirmed
  ///
  /// In en, this message translates to:
  /// **'Email verified successfully.'**
  String get authVerifyEmailSuccess;

  /// Plural example showing item count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String showcaseItemCount(int count);

  /// Label for date format showcase section
  ///
  /// In en, this message translates to:
  /// **'Date Format'**
  String get showcaseDateFormat;

  /// Label for number format showcase section
  ///
  /// In en, this message translates to:
  /// **'Number Format'**
  String get showcaseNumberFormat;

  /// Label showing the currently active locale
  ///
  /// In en, this message translates to:
  /// **'Current Locale'**
  String get showcaseCurrentLocale;

  /// Label for ICU yMd format in the date showcase section
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get showcaseDateShort;

  /// Label for ICU yMMMMd format in the date showcase section
  ///
  /// In en, this message translates to:
  /// **'Long'**
  String get showcaseDateLong;

  /// Label for ICU jm format in the date showcase section
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get showcaseDateTime;

  /// Label for ICU compact format in the number showcase section
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get showcaseNumberCompact;

  /// Label for ICU decimal format in the number showcase section
  ///
  /// In en, this message translates to:
  /// **'Decimal'**
  String get showcaseNumberDecimal;

  /// Text divider between social sign-in buttons and email/password form
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOrDivider;

  /// Google sign-in button label
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get authGoogleSignIn;

  /// Phase 16 R1 부활 anchor (was Phase 17 anchor) — placeholder {provider} 활용 가능 via errorAccountExistsWithProvider. Do not delete (3-tier ARB+getter+arm infrastructure).
  ///
  /// In en, this message translates to:
  /// **'This email is already registered with a different sign-in method. Please sign in with your password.'**
  String get errorAccountExistsWithDifferentCredential;

  /// Phase 9.2 R2 baseline 보존 — used when account-exists-with-different-credential or 'already-exists' triggers without server-side provider identification (lookupSignInMethods callable fail 시 fallback path). errorAccountExistsWithProvider 가 L1 (provider-aware), 본 키 가 L2 (unknown fallback).
  ///
  /// In en, this message translates to:
  /// **'This email is already registered with another sign-in method. Please sign in with the method you originally used.'**
  String get errorAccountExistsWithUnknownProvider;

  /// Phase 16 R1 부활 (Phase 9.2 deferred D-05~D-12/D-15/D-29 starting point). {provider} placeholder 는 7 brand verbatim 라벨 (audit trail: authAccountProvider{X} 7 ARB key — Google/Apple/Facebook/EmailPassword/Kakao/Naver/Line). exception_l10n.dart#_resolveAccountExists L1 branch 가 injection. SDK strings.xml > 공식 가이드 > 자산 embed 우선순위 (memory feedback_label_verbatim_audit).
  ///
  /// In en, this message translates to:
  /// **'This email is registered with {provider}. Sign in with {provider} to link your account.'**
  String errorAccountExistsWithProvider(String provider);

  /// Provider label displayed in the account section when the user signed in with Google
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get authAccountProviderGoogle;

  /// Apple sign-in button label
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get authAppleSignIn;

  /// Provider label displayed in the account section when the user signed in with Apple
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get authAccountProviderApple;

  /// Facebook sign-in button label
  ///
  /// In en, this message translates to:
  /// **'Login with Facebook'**
  String get authFacebookSignIn;

  /// Provider label displayed in the account section when the user signed in with Facebook
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get authAccountProviderFacebook;

  /// Kakao Login button label. EN verbatim from Kakao Design Guide (developers.kakao.com/docs/latest/en/kakaologin/design-guide). JA 공식 BI verbatim 적용 (R8 by Phase 13.3 — ja 는 [ASSUMED] 패턴 일관성 채택, starter 사용자 일본 진출 시점 공식 verbatim 재확정 의무). Phase 13.3 D-111 retroactive 갱신: Phase 12 D-29 'Continue with Kakao' → 'Login with Kakao' (user sign-off 2026-05-15 Wave 1 Task 1.0 Step 4 옵션 (b)).
  ///
  /// In en, this message translates to:
  /// **'Login with Kakao'**
  String get authKakaoSignIn;

  /// Account 섹션 Kakao 프로바이더 표시 (Phase 12 D-17).
  ///
  /// In en, this message translates to:
  /// **'Kakao'**
  String get authAccountProviderKakao;

  /// Naver Login button label. EN verbatim from Naver 공식 AI 파일 (developers.naver.com/docs/login/bi/bi.md, NAVER_login_EN.ai). JA 공식 BI verbatim 적용 (R8 by Phase 13.3 — ja 는 [ASSUMED] 패턴 일관성 채택, starter 사용자 일본 진출 시점 공식 verbatim 재확정 의무). #03C75A (NCloud SSO) carve-out — Phase 13.1 D-Note 일관. Phase 13.3 retroactive 갱신: Phase 13 D-23/D-52 'Continue with Naver' → 'Log in with NAVER'.
  ///
  /// In en, this message translates to:
  /// **'Log in with NAVER'**
  String get authNaverSignIn;

  /// LINE Login button label. EN verbatim from LINE official 'Login button design guidelines' long form (https://developers.line.biz/en/docs/line-login/login-button/). starter-kit active locale = en/ko/ja 3 종; 외 16 언어는 LINE 공식 가이드 동일 페이지 참조. brand_label_whitelist_test 가 [ASSUMED] tag audit trail + 1년 주기 갱신 정책 enforce. SDK strings audit 확정 2026-05-20 (quick task 260520-blt) — flutter_line_sdk 2.7.2 pub cache 의 strings.xml / Localizable.strings 0 hit, SDK 측 i18n 라벨 미제공 확인. 공식 가이드 long form (developers.line.biz/en/docs/line-login/login-button/) verbatim 채택, [ASSUMED] tag 부착 의무 해소. SDK version bump 시 재audit 의무 (14-LINE-LOCALE-REFERENCE.md § 4).
  ///
  /// In en, this message translates to:
  /// **'Log in with LINE'**
  String get authLineSignIn;

  /// Phase 13.1 REVIEW CR-03 — BrandedSocialButton placeholder fallback (LINE 자상 미commit 시점 회색 disabled 외관에 표시). Phase 14 자상 commit 완료 후 마지막 placeholder 해제로 본 path 도달 0 — caller 0 (sentinel 의무 해소, kPlaceholderProviders empty).
  ///
  /// In en, this message translates to:
  /// **'Asset missing: {label}'**
  String authBrandAssetMissing(String label);

  /// Phase 13 — Naver provider label in Account section (D-17 패턴 확장).
  ///
  /// In en, this message translates to:
  /// **'Naver'**
  String get authAccountProviderNaver;

  /// Phase 13 — LINE provider label (Phase 14 pre-registered, D-53 5 provider 일반화).
  ///
  /// In en, this message translates to:
  /// **'LINE'**
  String get authAccountProviderLine;

  /// Phase 13 D-53 — Localizable Unknown fallback for provider_label_formatter (raw slug 노출 차단).
  ///
  /// In en, this message translates to:
  /// **'Unknown sign-in method'**
  String get errorUnknownProvider;

  /// Onboarding carousel skip button label (top-right)
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// 10-REVIEW WR-09 — Screen-reader label for the onboarding carousel dot indicator (OnboardingIndicator). The wrapper sets liveRegion:true, so this string is announced on every page change — a hardcoded English literal was being read to ko/ja users. Placeholders are 1-based page numbers, matching what the user hears, not the 0-based activeIndex.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String onboardingPageIndicator(int current, int total);

  /// Onboarding carousel next button label (slides 1 and 2)
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Onboarding carousel primary CTA on the last slide
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// Onboarding slide 1 headline (placeholder, replace per project)
  ///
  /// In en, this message translates to:
  /// **'Get started quickly'**
  String get onboardingSlide1Title;

  /// Onboarding slide 1 body copy (placeholder, replace per project)
  ///
  /// In en, this message translates to:
  /// **'Explore core features without creating an account.'**
  String get onboardingSlide1Body;

  /// Onboarding slide 2 headline (placeholder, replace per project)
  ///
  /// In en, this message translates to:
  /// **'Kept safe and sound'**
  String get onboardingSlide2Title;

  /// Onboarding slide 2 body copy (placeholder, replace per project)
  ///
  /// In en, this message translates to:
  /// **'Sign in when you need more, and your data carries over.'**
  String get onboardingSlide2Body;

  /// Onboarding slide 3 headline (placeholder, replace per project)
  ///
  /// In en, this message translates to:
  /// **'Wherever you go'**
  String get onboardingSlide3Title;

  /// Onboarding slide 3 body copy (placeholder, replace per project)
  ///
  /// In en, this message translates to:
  /// **'The same experience across every language and device.'**
  String get onboardingSlide3Body;

  /// Main 'accept all' checkbox label in the terms group
  ///
  /// In en, this message translates to:
  /// **'Accept all'**
  String get termsAcceptAll;

  /// Badge label for required terms items
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get termsRequired;

  /// Badge label for optional terms items
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get termsOptional;

  /// Terms of service item label
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get termsService;

  /// Privacy policy item label
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get termsPrivacy;

  /// Optional marketing communications item label
  ///
  /// In en, this message translates to:
  /// **'Marketing communications'**
  String get termsMarketing;

  /// Inline 'view detail' link next to each terms item
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get termsViewDetail;

  /// Inline helper shown below the terms group when a required item is missing
  ///
  /// In en, this message translates to:
  /// **'Please agree to all required items.'**
  String get termsRequiredError;

  /// AppBar title of the Terms of service detail screen
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get termsDetailServiceTitle;

  /// AppBar title of the Privacy policy detail screen
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get termsDetailPrivacyTitle;

  /// Placeholder body of the terms detail screen (to be replaced per project)
  ///
  /// In en, this message translates to:
  /// **'Place your terms content here. Replace this placeholder with the final copy reviewed by your legal team.'**
  String get termsDetailPlaceholder;

  /// Splash screen progress caption shown while initializing
  ///
  /// In en, this message translates to:
  /// **'Getting things ready...'**
  String get splashPreparing;

  /// Title of the splash failure dialog
  ///
  /// In en, this message translates to:
  /// **'Can\'t connect right now'**
  String get splashFailureTitle;

  /// Body of the splash failure dialog
  ///
  /// In en, this message translates to:
  /// **'Something\'s blocking the connection. You can retry or continue offline.'**
  String get splashFailureMessage;

  /// Label for the 'sign in later' button in splash failure dialog (Phase 10.1 D-05 — navigates to /login instead of /home since anonymous UID does not exist after signInAnonymously failure).
  ///
  /// In en, this message translates to:
  /// **'Sign in later'**
  String get splashContinueOffline;

  /// Caption showing Firebase Auth error code in splash failure dialog. Tap to copy. PII-free (code only, no message — Phase 10.1 D-10/D-11).
  ///
  /// In en, this message translates to:
  /// **'Error code: {code}'**
  String splashErrorCodeFingerprint(String code);

  /// Muted banner shown on Home for anonymous users
  ///
  /// In en, this message translates to:
  /// **'Browsing as a guest · Sign in to unlock more'**
  String get homeGuestBanner;

  /// Home AppBar action label that opens the login prompt sheet
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get homeSignIn;

  /// Section title of the AuthRequired demo on Home
  ///
  /// In en, this message translates to:
  /// **'Example: this feature needs sign-in'**
  String get homeProtectedExampleTitle;

  /// Section body of the AuthRequired demo on Home
  ///
  /// In en, this message translates to:
  /// **'Wrap an action with \'AuthRequired\' to open the sign-in sheet automatically.'**
  String get homeProtectedExampleBody;

  /// Button label that triggers the AuthRequired demo flow
  ///
  /// In en, this message translates to:
  /// **'Run protected action'**
  String get homeProtectedExampleCta;

  /// LoginPromptSheet headline
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get authPromptSheetTitle;

  /// LoginPromptSheet body copy
  ///
  /// In en, this message translates to:
  /// **'You\'ll need an account to keep using this feature.'**
  String get authPromptSheetBody;

  /// LoginPromptSheet text link that navigates to the email form
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get authContinueWithEmail;

  /// Phase 16 D-03 / UI-SPEC Surface A verbatim — AccountLinkingSheet TextButton (cancel/dismiss). 탭 시 Navigator.pop(false) — linkedProviders 변경 0 (Phase 10.2 D-20 invariant 보존).
  ///
  /// In en, this message translates to:
  /// **'Sign in with another method'**
  String get accountLinkingDismiss;

  /// Developer tools section title (debug builds only)
  ///
  /// In en, this message translates to:
  /// **'Dev Tools'**
  String get devToolsSectionTitle;

  /// Developer tools section description caption
  ///
  /// In en, this message translates to:
  /// **'Developer tools, visible in debug builds only.'**
  String get devToolsSectionDescription;

  /// Dev tools action: clear onboarding completion flag
  ///
  /// In en, this message translates to:
  /// **'Reset onboarding'**
  String get devToolsResetOnboarding;

  /// SnackBar message after resetting onboarding
  ///
  /// In en, this message translates to:
  /// **'Onboarding state reset.'**
  String get devToolsResetOnboardingDone;

  /// Dev tools action: send a synthetic error to Crashlytics
  ///
  /// In en, this message translates to:
  /// **'Send test error'**
  String get devToolsTriggerError;

  /// SnackBar message after sending a test error
  ///
  /// In en, this message translates to:
  /// **'Test error sent to Crashlytics.'**
  String get devToolsTriggerErrorDone;

  /// Dev tools action: send a test analytics event
  ///
  /// In en, this message translates to:
  /// **'Send analytics event'**
  String get devToolsTriggerAnalytics;

  /// SnackBar message after sending a test analytics event
  ///
  /// In en, this message translates to:
  /// **'Test analytics event sent.'**
  String get devToolsTriggerAnalyticsDone;

  /// Dev tools action: force FirebaseAuth.signOut
  ///
  /// In en, this message translates to:
  /// **'Force sign out'**
  String get devToolsForceSignOut;

  /// Phase 16 D-11 / UI-SPEC Surface A verbatim — AccountLinkingSheet header title. 본문 (errorAccountExistsWithProvider) 위 표제로 노출.
  ///
  /// In en, this message translates to:
  /// **'Email already in use'**
  String get accountLinkingSheetTitle;

  /// Phase 16 D-11 / UI-SPEC Surface B verbatim — Settings screen AppBar title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Phase 16 D-11 / UI-SPEC Surface B verbatim — Settings 'My Account' section header (이메일 + 연결된 로그인 노출).
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get settingsAccountSection;

  /// Phase 16 D-11 / UI-SPEC Surface B verbatim — Settings account email placeholder (3 locale identical pass-through).
  ///
  /// In en, this message translates to:
  /// **'{email}'**
  String settingsAccountEmail(String email);

  /// Phase 16 SOCL-12 proactive linking — Surface D. Settings '계정 연결' section heading (proactive account-linking 진입점). 후보 = 소셜 provider only (email EXCLUDE — Surface D mockup §0 user sign-off 2026-06-02).
  ///
  /// In en, this message translates to:
  /// **'Link an account'**
  String get settingsAccountLinkingSection;

  /// Phase 16 SOCL-12 proactive linking — Surface D. Per-provider 'connect' button label. {provider} 는 기존 authAccountProvider{X} 소셜 라벨 주입 (brand verbatim 신규 0). proactive 후보 = 소셜 provider only (email EXCLUDE).
  ///
  /// In en, this message translates to:
  /// **'Link {provider}'**
  String settingsLinkProviderCta(String provider);

  /// Phase 16 SOCL-12 proactive linking — Surface D. 계정 연결 성공 토스트. {provider} 는 연결된 소셜 provider 의 authAccountProvider{X} 라벨 주입. reactive(16-08/16-09) 충돌 link 성공 시에도 재사용 가능.
  ///
  /// In en, this message translates to:
  /// **'Linked your {provider} account.'**
  String accountLinkingSucceededSnackbar(String provider);

  /// Phase 16 Plan 16-18 (CR-02 gap closure) — Surface A 2단계 reactive 플로우의 step 1 성공 안내 SnackBar. 경로 B(서버 already-exists 로 pendingCredential 부재)에서 시트 CTA 가 기존 provider 로 '로그인'(link 아님)에 성공한 직후 /home 에서 1회 노출되며, 나머지 로그인 수단 추가는 step 2 (Settings > 계정 연결, Surface D proactive arm)에서 한다는 후속 경로를 알린다. {provider} 에는 위젯이 계산한 _providerLabel(l10n, provider) 결과 = 기존 authAccountProvider{X} 8 키의 verbatim 라벨만 주입된다 (서버 응답/예외 문자열 주입 경로 0, brand 라벨 신설 0, brand_label_whitelist 확장 0 — 위협 T-16-18-01 mitigation). 문구의 'Settings' 는 settingsTitle, 'Link an account' 는 settingsAccountLinkingSection 값의 verbatim 인용이므로 그 두 키가 바뀌면 본 문구도 함께 바꾼다. 사용자 sign-off 및 확정 문구 표: .planning/phases/16-account-linking-withdrawal/mockups/surface-a-two-step-reactive.md (§8, status locked-plan-16-18).
  ///
  /// In en, this message translates to:
  /// **'Signed in with your {provider} account. You can add other sign-in methods in Settings > Link an account.'**
  String accountLinkingSignInThenLinkHint(String provider);

  /// Phase 16 WR-04 (2차 리뷰) — 인증 도메인 공용 re-auth 요구 SnackBar. 소비: (1) AccountLinkingSheet 경로 A (native + pendingCredential 보존 충돌의 linkPendingNativeCredential 실패가 ReauthenticationRequiredException 인 경우) → SnackBar 후 /login 라우팅, (2) Surface D — AccountLinkingSection 의 AccountLinkOutcome.reauthRequired SnackBar (WR-05, 4차 리뷰), (3) resolveExceptionMessage 의 'errorReauthenticationRequired' arm (WR-04, 4차 리뷰) — ReauthenticationRequiredException.userMessage 는 ARB 키가 아니라 taxonomy 토큰이며 매핑이 없으면 식별자 문자열이 그대로 렌더된다. 같은 뜻의 키를 또 만드는 대신 도메인 중립인 본 키로 매핑한다. 문구는 withdrawalReauthRequired 와 현재 동일하지만 키를 분리한 이유는 그 키의 소비처 계약이 UI-SPEC Surface C (Withdrawal Dialog) verbatim 1곳으로 못 박혀 있어서다 — 향후 Surface C 문구를 탈퇴 맥락에 맞게 (예: '탈퇴하려면 다시 로그인해 주세요') 다듬으면 계정 연동 시트에 엉뚱한 문구가 새어 나간다. 본 키는 도메인 중립을 유지할 의무가 있다 (탈퇴/연동 어느 쪽 어휘도 넣지 않는다). email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'For security, please sign in again and retry.'**
  String get authReauthRequired;

  /// 재인증 모드 AppBar 제목 (Q1). 소비: LoginScreen · EmailLoginScreen 의 isReauth 분기. debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get authReauthTitle;

  /// 재인증 모드 chooser 안내 문구 (Q1) — 소셜 버튼 위. 소비: LoginScreen 의 isReauth 분기. debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'For your security, sign in again with the account you\'re currently signed in with.'**
  String get authReauthGuide;

  /// 재인증 모드 이메일 화면 안내 문구 (Q3 렌더) — 읽기 전용 이메일 칸 위. 소비: EmailLoginScreen 의 isReauth 분기. debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'For your security, enter the password for this account.'**
  String get authReauthEmailGuide;

  /// 재인증 모드 이메일 화면 제출 버튼 라벨 (Q3). 소비: EmailLoginScreen 의 isReauth 분기. debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get authReauthConfirmCta;

  /// 재인증 성공 후 설정 화면으로 돌아가며 띄우는 SnackBar (Q6). 탈퇴 · 계정 연결 어느 쪽 어휘도 넣지 않는다 (두 진입점 공용). 소비: LoginScreen 의 재인증 완료 처리. debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'You\'re verified. Try that again.'**
  String get authReauthSucceeded;

  /// 재인증에 쓴 계정이 지금 로그인한 계정과 다를 때의 인라인 오류 배너 (Q2). 소비: resolveExceptionMessage 의 ReauthUserMismatch arm (user-mismatch · user-not-found · 서버 caller_identity_mismatch). debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'That\'s a different account from the one you\'re signed in with. Try again with the same account.'**
  String get errorReauthUserMismatch;

  /// 재인증 모드에서 쓸 수 있는 로그인 수단이 0 일 때의 오류 배너 (Q7 — 연결 provider 가 모두 kill switch 로 꺼진 경우 등). 소비: resolveExceptionMessage 의 ReauthMethodUnavailable arm. debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면(/login?reauth=1 · /login/email?reauth=1). ko 문구는 사용자 시각 sign-off(Q1~Q7) verbatim 이며 en/ja 는 번역 초안이다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'You can\'t confirm it\'s you with this account\'s sign-in methods right now. Try again later.'**
  String get errorReauthMethodUnavailable;

  /// Phase 16 WR-01 (4차 리뷰) — Surface A 경로 B step 1 (기존 provider 로 로그인) 의 **결정적(비-transient) 실패** 안내. 소비: AccountLinkingSheet._signInWithExistingProvider 의 AccountExistsWithDifferentCredential arm (A-16-19-01 익명 caller 재충돌 — 서버 resolveIdentity 의 R12 anonymous_existing_collision 재거부가 client 에서 이 타입으로 매핑된다). **재시도 어휘 금지 의무:** 이 실패는 익명 세션이 유지되는 한 재시도로 절대 해소되지 않는다 — '잠시 후 다시 시도' 계열 문구(settingsLinkFailedTransient / settingsLinkFailedUnknown)를 쓰면 사용자가 매 탭마다 실 IdP OAuth 왕복을 반복하는 무한 루프에 든다 (auth_repository.dart 의 1차 리뷰 WR-06 원칙과 동일 결함). 따라서 문구는 16-SECURITY.md AR-16-07 이 수용한 유일한 실 탈출구 — 시트 하단의 accountLinkingDismiss('다른 방식으로 로그인') — 를 가리킨다. signOut 후 재시도는 /onboarding 리셋 경합 때문에 채택하지 않았고(AR-16-07), 익명 문서 승계 정책 자체는 Phase 17+ 범위다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing as a guest, so this existing account can\'t be signed in here. Please use another sign-in method below.'**
  String get authSignInBlockedByGuestSession;

  /// Phase 16 IN-06 (4차 리뷰) — Surface A 경로 B step 1 (기존 provider 로 **로그인**) 의 일시적 네트워크·서비스 오류 문구. 소비: AccountLinkingSheet._signInWithExistingProvider 의 NetworkException / TooManyRequests / ServiceUnavailable arm. **키를 신설한 이유:** 이전에는 settingsLinkFailedTransient ('연결하지 못했습니다') 를 재사용했는데 그 순간 사용자가 수행한 동작은 link 가 아니라 로그인이다. 본 저장소는 ARB description 을 소비처 계약으로 운용하므로, '소비처 2곳의 동작 이름이 다른데 문구는 한쪽 어휘' 상태는 다음 문구 수정 때 다시 어긋난다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign in due to a network or service error. Please try again later.'**
  String get authSignInFailedTransient;

  /// Phase 16 IN-06 (4차 리뷰) — Surface A 경로 B step 1 (기존 provider 로 **로그인**) 의 미분류 catch-all 문구. 소비: AccountLinkingSheet._signInWithExistingProvider 의 마지막 arm. **키를 신설한 이유는 authSignInFailedTransient 와 동일** (link 어휘 vs 로그인 동작 불일치). 결정적 실패(A-16-19-01 익명 caller 재충돌)는 authSignInBlockedByGuestSession 전용 arm 이 먼저 가져가므로 이 키로 오지 않는다 — 여기에 '잠시 후 다시 시도' 어휘가 남아 있어도 무한 왕복을 유발하지 않는 이유다. 정확한 코드는 kDebugMode debugPrint 로 logcat 에 남는다 (T-16-15-01). email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign you in. Please try again later.'**
  String get authSignInFailedUnknown;

  /// Phase 16 G-16-A6-2 — Surface D proactive link 실패 문구 (원인: already-linked). 2026-09-07 A6 실측에서 실제 원인이 credential-already-in-use 였는데 errorAccountExistsWithUnknownProvider(이메일 문구)가 표시된 collapse 를 해소한다. 소비: (1) Surface D proactive — AccountLinkOutcome.alreadyLinked (AccountAlreadyLinked — credential-already-in-use), (2) Surface A 경로 A — AccountLinkingSheet 의 linkPendingNativeCredential 실패 중 AccountAlreadyLinked arm (WR-02, 4차 리뷰). 경로 A 도 동일 collapse (errorAccountExistsWithUnknownProvider) 를 쓰고 있었다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'This sign-in method is already linked to another account. Unlink it first, then try again.'**
  String get settingsLinkFailedAlreadyLinked;

  /// Phase 16 WR-04 (2차 리뷰) — Surface D proactive link 실패 문구 (원인: provider-already-linked, 즉 해당 provider 가 이미 *현재* 계정에 연결됨). 소비: (1) Surface D proactive — AccountLinkOutcome.alreadyLinkedHere (ProviderAlreadyLinkedToThisAccount), (2) reactive — ProviderAlreadyLinkedToThisAccount.userMessage 경유 resolveExceptionMessage (FormErrorBanner 등 AppException 렌더 표면 전체, WR-03), (3) Surface A 경로 A — AccountLinkingSheet 의 linkPendingNativeCredential 실패 중 ProviderAlreadyLinkedToThisAccount arm (WR-02, 4차 리뷰). settingsLinkFailedAlreadyLinked 는 credential-already-in-use (해당 자격증명이 *다른* 계정에 연결) 전용이며 두 문구는 의미가 정반대다 — 하나로 뭉개면 사실과 반대인 안내 + 수행 불가능한 해결책 (다른 계정 소유주만 해제 가능) 이 나간다. email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'This account is already linked to that sign-in method.'**
  String get settingsLinkFailedAlreadyLinkedHere;

  /// Phase 16 G-16-A6-2 — Surface D proactive link 실패 문구 (원인: email 중복). 소비: (1) Surface D proactive — AccountLinkOutcome.emailInUse (EmailAlreadyInUse — email-already-in-use, AccountExistsWithDifferentCredential), (2) Surface A 경로 A — AccountLinkingSheet 의 linkPendingNativeCredential 실패 중 동일 2 타입 arm (WR-02, 4차 리뷰). 문구에 email 값 자체를 echo 하지 않는다 (T-16-15-02 mitigate — 본인 link 시도 결과에만 노출되어 enumeration 표면 0).
  ///
  /// In en, this message translates to:
  /// **'This email is already in use by another account.'**
  String get settingsLinkFailedEmailInUse;

  /// Phase 16 G-16-A6-2 — Surface D proactive link 실패 문구 (원인: 일시적 네트워크·서비스 오류). 소비: (1) Surface D proactive — AccountLinkOutcome.transientFailure, (2) Surface A 경로 A — AccountLinkingSheet 의 linkPendingNativeCredential 실패 중 동일 예외 집합 arm (WR-02, 4차 리뷰). 두 표면 모두 동작이 link 다 — 경로 B step 1 은 로그인이므로 IN-06 에서 authSignInFailedTransient 로 분리되어 더 이상 이 키를 쓰지 않는다. 두 표면 모두 예외 타입 집합은 NetworkException 계열 network-request-failed / TooManyRequests too-many-requests / ServiceUnavailable 이다. 재시도 유도 문구 — 시트가 지목한 provider 로 '다시 로그인' 하라는 순환 안내(errorAccountExistsWithUnknownProvider)를 대체한다.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t link due to a network or service error. Please try again later.'**
  String get settingsLinkFailedTransient;

  /// Phase 16 G-16-A6-2 — Surface D proactive link 실패 문구 (원인: 미분류 catch-all). 소비: (1) Surface D proactive — AccountLinkOutcome.failed, (2) Surface A 경로 A 의 catch-all arm (WR-02, 4차 리뷰). 경로 B step 1 은 로그인이므로 IN-06 에서 authSignInFailedUnknown 으로 분리되어 더 이상 이 키를 쓰지 않는다. 분류되지 않은 실패가 조용히 사라지지 않도록 두는 마지막 arm 이며, 정확한 코드는 kDebugMode debugPrint(code=...) 로 logcat 에 남는다 (T-16-15-01).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t link your account. Please try again later.'**
  String get settingsLinkFailedUnknown;

  /// Phase 16 G-16-A6-2 — Surface D '미지원' 전용 문구. 실패가 아니라 미지원임을 실패 4 문구와 구분해 노출한다. 소비: AccountLinkOutcome.unsupported (email — Surface D EXCLUDE (naver 는 Phase 16.9 부터 linkNaverProviderArm 로 연결 지원)). {provider} 에는 caller 가 기존 authAccountProvider{X} 8 키의 brand verbatim 라벨을 주입하므로 brand 라벨 신규 0 → brand_label_whitelist_test 확장 불요 (settingsLinkProviderCta 선례 동일, T-16-15-03 mitigate).
  ///
  /// In en, this message translates to:
  /// **'Linking a {provider} account isn\'t supported yet.'**
  String settingsLinkUnsupportedProvider(String provider);

  /// Phase 16.8 D-07/D-10/D-12 — Settings 'Linked accounts' unlink button semantics label (screen reader). {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Unlink {provider}'**
  String settingsUnlinkProviderSemantic(String provider);

  /// Phase 16.8 D-07/D-10 — unlink confirmation dialog title. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Unlink {provider}?'**
  String settingsUnlinkDialogTitle(String provider);

  /// Phase 16.8 D-07/D-10 — unlink confirmation dialog body (consequence of unlinking). {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'You\'ll no longer be able to sign in with your {provider} account.'**
  String settingsUnlinkDialogBody(String provider);

  /// Phase 16.8 D-07/D-10 — unlink confirmation dialog confirm action (TextButton, M3 default style).
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get settingsUnlinkConfirmAction;

  /// Phase 16.8 D-07/D-10 — unlink success SnackBar (AccountUnlinkOutcome.success). {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Unlinked your {provider} account.'**
  String accountUnlinkSucceededSnackbar(String provider);

  /// Phase 16.8 D-03/D-07 — unlink rejected because it is the last sign-in method (AccountUnlinkOutcome.lastCredential · UnlinkLastCredentialRejected).
  ///
  /// In en, this message translates to:
  /// **'You can\'t unlink your only sign-in method.'**
  String get settingsUnlinkFailedLastCredential;

  /// Phase 16.8 D-07 — unlink target no longer linked (AccountUnlinkOutcome.alreadyUnlinked · ProviderNotLinked).
  ///
  /// In en, this message translates to:
  /// **'This account is already unlinked.'**
  String get settingsUnlinkFailedAlreadyUnlinked;

  /// Phase 16.8 D-07 — unlink failed with a transient network/service error (AccountUnlinkOutcome.transientFailure).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unlink due to a network or service error. Please try again later.'**
  String get settingsUnlinkFailedTransient;

  /// Phase 16.8 D-07 — unclassified unlink failure catch-all (AccountUnlinkOutcome.failed).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unlink your account. Please try again later.'**
  String get settingsUnlinkFailedUnknown;

  /// Phase 16.10 D-19 — unlink dialog disclosure: the provider-side app connection is removed too. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'This also removes the app\'s access to your {provider} account.'**
  String settingsUnlinkDialogDisclosure(String provider);

  /// Phase 16.10 D-10 — unlink dialog guide for re-sign-in providers: the user signs in once to unlink. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'To unlink, you\'ll sign in with {provider} once.'**
  String settingsUnlinkDialogSignInGuide(String provider);

  /// Phase 16.10 D-08 — unlink failed because the signed-in provider account is not the linked one (AccountUnlinkOutcome.identityMismatch). {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t the linked {provider} account. Sign in with the linked account and try again.'**
  String settingsUnlinkFailedIdentityMismatch(String provider);

  /// Phase 16.10 D-11 — unlink kept because the provider-side disconnect failed (AccountUnlinkOutcome.disconnectFailed). {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t disconnect from {provider}, so the account is still linked. Please try again later.'**
  String settingsUnlinkFailedDisconnect(String provider);

  /// Phase 16.10 review IN-03 (iteration 3 · UI-SPEC §N′ sign-off R2 · R3) — the provider-side disconnect succeeded but the following kit unlink failed with a transient or unclassified error, so the account is still linked while the app access on the provider side is already gone (AccountUnlinkOutcome.unlinkFailedAfterDisconnect). {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Disconnected from {provider}, but couldn\'t unlink the account. Please try again later.'**
  String settingsUnlinkFailedAfterDisconnect(String provider);

  /// Phase 16 D-11 / UI-SPEC Surface B verbatim — Settings 'Danger zone' section header. 3 locale 영문 일관 (ko/en/ja 모두 'Danger zone').
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get settingsDangerZoneSection;

  /// Phase 16 D-11 / UI-SPEC Surface B verbatim — Danger zone subheader caption (회원탈퇴 위 경고문).
  ///
  /// In en, this message translates to:
  /// **'These actions cannot be undone.'**
  String get settingsDangerZoneExplainer;

  /// Phase 16 D-11 / UI-SPEC Surface B verbatim — Settings withdrawal entry tile label. 탭 시 WithdrawalDialog 진입.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsWithdrawalLabel;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get withdrawalDialogTitle;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal Dialog body line 1 (영구 삭제 명시).
  ///
  /// In en, this message translates to:
  /// **'Your account and all data will be permanently deleted.'**
  String get withdrawalDialogBodyLine1;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal Dialog body line 2 (복구 불가 명시).
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get withdrawalDialogBodyLine2;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal Dialog body line 3 (재가입 시 동일 이메일/방식 신규 등록 명시).
  ///
  /// In en, this message translates to:
  /// **'To rejoin, you must register again with the same email or the same sign-in method.'**
  String get withdrawalDialogBodyLine3;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal confirm TextField hint (사용자가 입력해야 하는 phrase).
  ///
  /// In en, this message translates to:
  /// **'delete'**
  String get withdrawalConfirmFieldHint;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal confirm TextField label/description. {phrase} 는 withdrawalConfirmFieldHint 와 동일 문구.
  ///
  /// In en, this message translates to:
  /// **'Type \"{phrase}\" to continue.'**
  String withdrawalConfirmFieldLabel(String phrase);

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal Dialog confirm action button (destructive).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get withdrawalConfirmAction;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal Dialog re-auth required SnackBar/message (recent-login 만료 시). **소비처는 Surface C 1곳뿐이다** — 계정 연동(Surface A 경로 A / Surface D)은 도메인 중립 키 authReauthRequired 를 쓴다 (WR-04 2차 리뷰 + WR-05 4차 리뷰). 본 키는 탈퇴 맥락 전용이므로 문구를 탈퇴 어휘로 특화해도 안전하며, 그렇게 다듬는 것이 키를 분리한 원래 목적이다.
  ///
  /// In en, this message translates to:
  /// **'For security, please sign in again and retry.'**
  String get withdrawalReauthRequired;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal success SnackBar message.
  ///
  /// In en, this message translates to:
  /// **'Account deleted.'**
  String get withdrawalSuccess;

  /// Phase 16 D-11 / UI-SPEC Surface C verbatim — Withdrawal failure SnackBar message (generic fallback).
  ///
  /// In en, this message translates to:
  /// **'Could not delete account. Please try again.'**
  String get withdrawalFailure;

  /// Phase 16 WR-03 (2차 리뷰) — Surface C 탈퇴 실패 SnackBar 의 원인별 문구 (일시적 네트워크·서비스 오류). 소비: WithdrawalConfirmationDialog 가 SettingsRepository._mapDeleteError 의 NetworkException(unavailable/deadline-exceeded) / TooManyRequests(resource-exhausted) 분기에 렌더한다. 2026-09-07 실측에서 dev Cloud Run 할당량 차단이 generic withdrawalFailure 로 표시되어 원인 오인을 유발했다 — taxonomy 는 분리했으나 표면이 collapse 되어 있던 비대칭을 해소한다. Surface D 의 settingsLinkFailedTransient 와 동일 계열 문구이며 email/uid/token 을 노출하지 않는다.
  ///
  /// In en, this message translates to:
  /// **'Could not delete account due to a network or service error. Please try again later.'**
  String get withdrawalFailureTransient;

  /// Phase 16 D-08 destructive intent Semantics label — UI-SPEC line 332 verbatim 채택 (Warning 7). Plan 16-06 Task 6.2 WC10 의 withdrawalConfirmAction 버튼 Semantics label 이 본 key consume 의무. 시각 라벨 (withdrawalConfirmAction='Delete') 과 분리 — 스크린리더 사용자에게 destructive intent + 영구성 + 비가역성 명시.
  ///
  /// In en, this message translates to:
  /// **'Withdraw account — permanent deletion, cannot be undone'**
  String get withdrawalConfirmActionSemantic;

  /// Phase 16.10 D-06 · D-19 — withdrawal progress screen intro paragraph (discloses that each linked service's app connection is removed).
  ///
  /// In en, this message translates to:
  /// **'Before deleting your account, we\'ll disconnect this app from each linked service and remove the access you gave it. Some services ask you to sign in once more to do this.'**
  String get withdrawalDisconnectIntro;

  /// Phase 16.10 D-06 — progress row status: waiting (not the current sign-in row yet).
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get withdrawalDisconnectStatusWaiting;

  /// Phase 16.10 D-06 — progress row status: the current re-sign-in row waits for the user to sign in.
  ///
  /// In en, this message translates to:
  /// **'Sign in to disconnect'**
  String get withdrawalDisconnectStatusNeedsSignIn;

  /// Phase 16.10 D-06 — progress row status: disconnect in progress (spinner row).
  ///
  /// In en, this message translates to:
  /// **'Disconnecting…'**
  String get withdrawalDisconnectStatusWorking;

  /// Phase 16.10 D-06 — progress row status: provider-side disconnect finished.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get withdrawalDisconnectStatusDone;

  /// Phase 16.10 D-06 · D-12 — progress row status: disconnect failed (retry or skip).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t disconnect'**
  String get withdrawalDisconnectStatusFailed;

  /// Phase 16.10 D-08 — progress row status: the signed-in provider account is not the linked one. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the linked {provider} account'**
  String withdrawalDisconnectStatusMismatch(String provider);

  /// Phase 16.10 D-12 — progress row status: the user skipped this provider.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get withdrawalDisconnectStatusSkipped;

  /// Phase 16.10 D-12 — guide under a skipped row: disconnect the app manually in the provider account settings. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Disconnect this app yourself in your {provider} account settings.'**
  String withdrawalDisconnectSkippedGuide(String provider);

  /// Phase 16.10 D-12 — progress row skip button label.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get withdrawalDisconnectSkip;

  /// Phase 16.10 D-12 — screen reader label of the skip button. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Skip {provider}'**
  String withdrawalDisconnectSkipSemantic(String provider);

  /// Phase 16.10 D-12 — screen reader label of the server row retry button. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'Retry {provider}'**
  String withdrawalDisconnectRetrySemantic(String provider);

  /// Phase 16.10 D-06 — screen reader label of a progress row header. {status} is one withdrawalDisconnectStatus* value. {provider} is one authAccountProvider{X} label.
  ///
  /// In en, this message translates to:
  /// **'{provider}: {status}'**
  String withdrawalDisconnectRowSemantic(String provider, String status);

  /// Phase 16.10 D-05 — hint above the disabled final delete button until every row is disconnected or skipped.
  ///
  /// In en, this message translates to:
  /// **'You can delete your account once every service is disconnected or skipped.'**
  String get withdrawalDisconnectFinalHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
