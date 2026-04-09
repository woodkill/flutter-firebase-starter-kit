// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '削除';

  @override
  String get commonEdit => '編集';

  @override
  String get commonLoading => '読み込み中';

  @override
  String get homeEnvironmentInfo => '環境情報';

  @override
  String get homeThemeMode => 'テーマモード';

  @override
  String get homeLanguage => '言語';

  @override
  String get homeThemeLight => 'ライト';

  @override
  String get homeThemeSystem => 'システム';

  @override
  String get homeThemeDark => 'ダーク';

  @override
  String get homeColorPalette => 'カラーパレット';

  @override
  String get homeTypography => 'タイポグラフィ';

  @override
  String get homeSpacing => 'スペーシング';

  @override
  String get homeBuildEnvironment => 'ビルド環境';

  @override
  String get homeEnvFlavor => 'フレーバー';

  @override
  String get homeEnvAppName => 'アプリ名';

  @override
  String get homeEnvFirebase => 'Firebase';

  @override
  String get homeEnvFirebaseProjectId => 'Firebase プロジェクト ID';

  @override
  String get homeFirebaseConnected => '接続済み';

  @override
  String get homeFirebaseNotConnected => '未接続';

  @override
  String get homeFirebaseStatusConnected => 'Firebase 接続済み';

  @override
  String get homeFirebaseStatusNotConnected => 'Firebase 未接続';

  @override
  String get languageChanged => '言語を変更しました';

  @override
  String get errorNetworkTimeout => '接続がタイムアウトしました。もう一度お試しください。';

  @override
  String get errorNoInternet => 'インターネット接続がありません。';

  @override
  String get errorRequestTimeout => 'リクエストがタイムアウトしました。もう一度お試しください。';

  @override
  String get errorInvalidCredentials => 'メールアドレスまたはパスワードが正しくありません。';

  @override
  String get errorUserNotFound => 'ユーザーが見つかりません。';

  @override
  String get errorEmailAlreadyInUse => 'このメールアドレスは既に使用されています。';

  @override
  String get errorWeakPassword => 'パスワードが脆弱です。';

  @override
  String get errorSessionExpired => 'セッションの有効期限が切れました。再度ログインしてください。';

  @override
  String get errorInternalServer => '問題が発生しました。しばらくしてからもう一度お試しください。';

  @override
  String get errorServiceUnavailable => 'サービスを一時的にご利用いただけません。';

  @override
  String get errorInvalidEmail => '有効なメールアドレスではありません。';

  @override
  String get errorUserDisabled => 'このアカウントは無効化されています。サポートにお問い合わせください。';

  @override
  String get errorTooManyRequests => '試行回数が多すぎます。しばらくしてからもう一度お試しください。';

  @override
  String get errorUnknown => '不明なエラーが発生しました。';

  @override
  String get errorEmailRequired => 'メールアドレスを入力してください。';

  @override
  String get errorInvalidEmailFormat => '有効なメールアドレスの形式で入力してください。';

  @override
  String get errorPasswordTooShort => 'パスワードは8文字以上で入力してください。';

  @override
  String get errorDisplayNameRequired => 'お名前を入力してください。';

  @override
  String get errorDisplayNameTooLong => 'お名前は32文字以内で入力してください。';

  @override
  String get errorNotFoundTitle => 'ページが見つかりません';

  @override
  String get errorNotFoundBody => 'リクエストされたページは存在しません。';

  @override
  String get errorNotFoundGoHomeCta => 'ホームへ';

  @override
  String get authLoginTitle => 'ログイン';

  @override
  String get authSignupTitle => 'アカウント作成';

  @override
  String get authForgotTitle => 'パスワードリセット';

  @override
  String get authLoginEmailLabel => 'メールアドレス';

  @override
  String get authLoginPasswordLabel => 'パスワード';

  @override
  String get authSignupDisplayNameLabel => 'お名前';

  @override
  String get authForgotDescription => 'ご登録のメールアドレスにパスワード再設定メールをお送りします。';

  @override
  String get authLoginCta => 'ログイン';

  @override
  String get authSignupCta => 'アカウントを作成';

  @override
  String get authForgotCta => '再設定メールを送信';

  @override
  String get authLoginForgotPassword => 'パスワードをお忘れですか？';

  @override
  String get authLoginNoAccount => 'アカウントをお持ちでない方はこちら';

  @override
  String get authSignupHasAccount => 'すでにアカウントをお持ちの方はログイン';

  @override
  String get authForgotSent => 'パスワード再設定メールを送信しました。受信トレイをご確認ください。';

  @override
  String get authAccountSectionTitle => 'アカウント';

  @override
  String get authAccountDisplayName => '表示名';

  @override
  String get authAccountEmail => 'メールアドレス';

  @override
  String get authAccountPhotoUrl => 'プロフィール画像URL';

  @override
  String get authAccountUid => 'ユーザーID';

  @override
  String get authAccountCreatedAt => '作成日';

  @override
  String get authAccountProviders => 'ログイン方法';

  @override
  String get authAccountProviderEmailPassword => 'メール / パスワード';

  @override
  String get authAccountCopyToken => 'IDトークンをコピー';

  @override
  String get authAccountCopied => 'クリップボードにコピーしました。';

  @override
  String get authAccountSignOut => 'ログアウト';

  @override
  String get debugAuthTokenUnavailable => 'IDトークンを取得できません (debug)';

  @override
  String get authLogoutConfirmTitle => 'ログアウト';

  @override
  String get authLogoutConfirmMessage => 'ログアウトしますか？';

  @override
  String get authShowPassword => 'パスワードを表示';

  @override
  String get authHidePassword => 'パスワードを非表示';

  @override
  String get authVerifyEmailTitle => 'メール認証';

  @override
  String authVerifyEmailDescription(String email) {
    return '認証メールを$emailに送信しました。メール内のリンクをクリックして認証を完了してください。';
  }

  @override
  String get authVerifyEmailSpamHint => 'メールが届かない場合は、迷惑メールフォルダをご確認ください。';

  @override
  String get authVerifyEmailCheck => '認証を確認する';

  @override
  String get authVerifyEmailResend => '認証メールを再送信';

  @override
  String authVerifyEmailResendCooldown(int seconds) {
    return '再送信まで($seconds秒)';
  }

  @override
  String get authVerifyEmailLogout => '別のアカウントでログイン';

  @override
  String get authVerifyEmailSuccess => 'メール認証が完了しました。';

  @override
  String get splashPlaceholderTitle => 'スプラッシュ';

  @override
  String get splashPlaceholderStub => 'Phase 10 プレースホルダー';

  @override
  String showcaseItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件',
      one: '1件',
      zero: '項目なし',
    );
    return '$_temp0';
  }

  @override
  String get showcaseDateFormat => '日付形式';

  @override
  String get showcaseNumberFormat => '数値形式';

  @override
  String get showcaseCurrentLocale => '現在のロケール';

  @override
  String get showcaseDateShort => '短い形式';

  @override
  String get showcaseDateLong => '長い形式';

  @override
  String get showcaseDateTime => '時刻';

  @override
  String get showcaseNumberCompact => '省略表記';

  @override
  String get showcaseNumberDecimal => '区切り付き';
}
