import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
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
  /// **'Photo URL'**
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

  /// Title text on the Phase 10 splash placeholder screen
  ///
  /// In en, this message translates to:
  /// **'Splash'**
  String get splashPlaceholderTitle;

  /// Stub marker text on the splash placeholder screen indicating it is a throwaway UI that will be replaced in Phase 10
  ///
  /// In en, this message translates to:
  /// **'Phase 10 placeholder'**
  String get splashPlaceholderStub;

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
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
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
