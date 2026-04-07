// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

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
  String get homeTypography => 'Typography';

  @override
  String get homeSpacing => 'Spacing';

  @override
  String get homeBuildEnvironment => 'Build Environment';

  @override
  String get homeFirebaseConnected => 'Connected';

  @override
  String get homeFirebaseNotConnected => 'Not Connected';

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
}
