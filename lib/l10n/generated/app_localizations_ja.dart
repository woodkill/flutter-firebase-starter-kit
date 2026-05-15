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
  String get commonCopied => 'コピーしました';

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
  String get authSocialSigningIn => 'サインイン処理中…';

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
  String get homeColorGroupPrimary => 'プライマリ';

  @override
  String get homeColorGroupSecondary => 'セカンダリ';

  @override
  String get homeColorGroupTertiary => 'ターシャリ';

  @override
  String get homeColorGroupError => 'エラー';

  @override
  String get homeColorGroupSurface => 'サーフェス';

  @override
  String get homeColorGroupOutline => 'アウトライン & ユーティリティ';

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
  String get homeFirebaseProjectIdPlaceholderWarning =>
      'Firebase プロジェクト ID が placeholder のままです。ビルド前に flavor 別の config JSON を置き換えてください。';

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
  String get authAccountPhotoUrl => 'プロフィール写真';

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
  String get authVerifyEmailDescriptionNoEmail =>
      'ご登録のメールアドレスに認証メールを送信しました。メール内のリンクをクリックして認証を完了してください。';

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

  @override
  String get authOrDivider => 'または';

  @override
  String get authGoogleSignIn => 'Googleでログイン';

  @override
  String get errorAccountExistsWithDifferentCredential =>
      'このメールアドレスは別の方法で登録されています。パスワードでログインしてください。';

  @override
  String get errorAccountExistsWithUnknownProvider =>
      'このメールアドレスは別の方法で登録されています。最初に登録した方法でログインしてください。';

  @override
  String get authAccountProviderGoogle => 'Google';

  @override
  String get authAppleSignIn => 'Appleでサインイン';

  @override
  String get authAccountProviderApple => 'Apple';

  @override
  String get authFacebookSignIn => 'Facebookでログイン';

  @override
  String get authAccountProviderFacebook => 'Facebook';

  @override
  String get authKakaoSignIn => 'Kakaoでログイン';

  @override
  String get authAccountProviderKakao => 'カカオ';

  @override
  String get authNaverSignIn => 'NAVERでログイン';

  @override
  String authBrandAssetMissing(String label) {
    return 'アセットが見つかりません: $label';
  }

  @override
  String get authAccountProviderNaver => 'ネイバー';

  @override
  String get authAccountProviderLine => 'LINE';

  @override
  String get authAccountProviderYahooJp => 'Yahoo! JAPAN';

  @override
  String get authAccountProviderWechat => 'WeChat';

  @override
  String get errorUnknownProvider => '不明なログイン方法';

  @override
  String get onboardingSkip => 'スキップ';

  @override
  String get onboardingNext => '次へ';

  @override
  String get onboardingGetStarted => 'はじめる';

  @override
  String get onboardingSlide1Title => 'すぐに始められます';

  @override
  String get onboardingSlide1Body => 'アカウント登録なしで主要機能をお試しいただけます。';

  @override
  String get onboardingSlide2Title => 'データは安全に保護';

  @override
  String get onboardingSlide2Body => '必要になったタイミングでログインすれば、データはそのまま引き継がれます。';

  @override
  String get onboardingSlide3Title => 'どこでも一緒に';

  @override
  String get onboardingSlide3Body => 'あらゆる言語と端末で同じ体験をお届けします。';

  @override
  String get termsAcceptAll => 'すべて同意する';

  @override
  String get termsRequired => '必須';

  @override
  String get termsOptional => '任意';

  @override
  String get termsService => '利用規約';

  @override
  String get termsPrivacy => 'プライバシーポリシー';

  @override
  String get termsMarketing => 'マーケティング情報の受信';

  @override
  String get termsViewDetail => '詳細を見る';

  @override
  String get termsRequiredError => '必須項目にすべて同意してください。';

  @override
  String get termsDetailServiceTitle => '利用規約';

  @override
  String get termsDetailPrivacyTitle => 'プライバシーポリシー';

  @override
  String get termsDetailPlaceholder =>
      'ここに規約の本文を記載してください。プロジェクトの法務チームが確認した最終版に置き換えてください。';

  @override
  String get splashPreparing => 'アプリを準備しています...';

  @override
  String get splashFailureTitle => '接続できません';

  @override
  String get splashFailureMessage => '接続に問題があります。再試行するか、オフラインで続行できます。';

  @override
  String get splashContinueOffline => '後でサインイン';

  @override
  String splashErrorCodeFingerprint(String code) {
    return 'エラーコード: $code';
  }

  @override
  String get homeGuestBanner => 'ゲストとして利用中 · ログインでさらに多くの機能を利用できます';

  @override
  String get homeSignIn => 'ログイン';

  @override
  String get homeProtectedExampleTitle => '例：この機能にはログインが必要です';

  @override
  String get homeProtectedExampleBody =>
      '\'AuthRequired\' でラップすると、保護されたアクションで自動的にログインシートが開きます。';

  @override
  String get homeProtectedExampleCta => '保護されたアクションを実行';

  @override
  String get authPromptSheetTitle => 'ログインが必要です';

  @override
  String get authPromptSheetBody => 'この機能を使い続けるには、アカウントが必要です。';

  @override
  String get authContinueWithEmail => 'メールアドレスで続行';

  @override
  String get devToolsSectionTitle => 'Dev Tools';

  @override
  String get devToolsSectionDescription => 'デバッグビルドでのみ表示される開発者向けツールです。';

  @override
  String get devToolsResetOnboarding => 'オンボーディングをリセット';

  @override
  String get devToolsResetOnboardingDone => 'オンボーディングの状態をリセットしました。';

  @override
  String get devToolsTriggerError => 'テストエラーを送信';

  @override
  String get devToolsTriggerErrorDone => 'テストエラーをCrashlyticsに送信しました。';

  @override
  String get devToolsTriggerAnalytics => 'アナリティクスイベントを送信';

  @override
  String get devToolsTriggerAnalyticsDone => 'テスト用アナリティクスイベントを送信しました。';

  @override
  String get devToolsForceSignOut => '強制ログアウト';
}
