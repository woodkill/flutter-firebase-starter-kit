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

  /// Label for the user's email field in the account section
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

  /// Label for the linked auth providers list in the account section
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get authAccountProviders;

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

  /// Error message when account-exists-with-different-credential Firebase error occurs during social sign-in
  ///
  /// In en, this message translates to:
  /// **'This email is already registered with a different sign-in method. Please sign in with your password.'**
  String get errorAccountExistsWithDifferentCredential;

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
  /// **'Sign in with Facebook'**
  String get authFacebookSignIn;

  /// Provider label displayed in the account section when the user signed in with Facebook
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get authAccountProviderFacebook;

  /// Onboarding carousel skip button label (top-right)
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

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

  /// Splash failure dialog action that continues without Firebase
  ///
  /// In en, this message translates to:
  /// **'Continue offline'**
  String get splashContinueOffline;

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
