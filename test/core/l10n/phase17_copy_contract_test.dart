import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/l10n/exception_l10n.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

// Phase 17 — see ROADMAP.md (D-42 · UI-SPEC §Copywriting Q5 LOCK).
// 기대 문자열은 17-UI-SPEC.md 「ARB 신설」 표의 셀을 그대로 복사한 상수다.
// 문구를 바꾸려면 sign-off 를 다시 받고 표와 이 상수를 함께 고친다.

/// UI-SPEC 표 `errorAppCheckFailed` 행 — locale 코드별 verbatim 문구.
const Map<String, String> _kAppCheckFailedCopy = <String, String>{
  'ko':
      '요청을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요. '
      '계속되면 앱을 최신 버전으로 업데이트해 주세요.',
  'en':
      "We couldn't verify this request. Please try again later. "
      'If this keeps happening, update the app to the latest version.',
  'ja':
      'リクエストを確認できませんでした。しばらくしてからもう一度お試しください。'
      '解決しない場合は、アプリを最新バージョンにアップデートしてください。',
};

/// UI-SPEC 「ARB 신설」 표 한 행 — 키 · getter · 3 locale verbatim 문구.
class _CopyRow {
  /// [_CopyRow] 를 만든다.
  const _CopyRow(this.key, this.read, this.ko, this.en, this.ja);

  /// ARB 키 이름.
  final String key;

  /// [AppLocalizations] 에서 이 키의 값을 읽는다.
  final String Function(AppLocalizations l10n) read;

  /// ko 셀.
  final String ko;

  /// en 셀.
  final String en;

  /// ja 셀.
  final String ja;

  /// [languageCode] 에 해당하는 기대 문구를 돌려준다.
  String expectedFor(String languageCode) => switch (languageCode) {
    'ko' => ko,
    'en' => en,
    'ja' => ja,
    _ => throw ArgumentError.value(languageCode, 'languageCode'),
  };
}

/// UI-SPEC 표 26행 전체 (표 순서 그대로).
///
/// `devToolsSendTestPushDone` 은 count 3 의 값으로 담는다 — count 1 의 en
/// 단수형은 T-17-COPY-02 안에서 따로 단언한다.
final List<_CopyRow> _kPhase17Rows = <_CopyRow>[
  _CopyRow(
    'homeAnnouncementLabel',
    (l) => l.homeAnnouncementLabel,
    '공지',
    'Announcement',
    'お知らせ',
  ),
  _CopyRow(
    'homeAnnouncementDismiss',
    (l) => l.homeAnnouncementDismiss,
    '공지 닫기',
    'Dismiss announcement',
    'お知らせを閉じる',
  ),
  _CopyRow(
    'settingsNotificationsSection',
    (l) => l.settingsNotificationsSection,
    '알림',
    'Notifications',
    '通知',
  ),
  _CopyRow(
    'settingsNotificationsToggle',
    (l) => l.settingsNotificationsToggle,
    '알림 받기',
    'Receive notifications',
    '通知を受け取る',
  ),
  _CopyRow(
    'settingsNotificationsToggleSubtitle',
    (l) => l.settingsNotificationsToggleSubtitle,
    '이 기기에서 알림을 받습니다.',
    'Get notifications on this device.',
    'この端末で通知を受け取ります。',
  ),
  _CopyRow(
    'settingsNotificationsPermissionDenied',
    (l) => l.settingsNotificationsPermissionDenied,
    '알림 권한이 꺼져 있습니다. 휴대폰 설정에서 이 앱의 알림을 허용해 주세요.',
    "Notifications are turned off for this app. Allow them in your phone's "
        'settings.',
    'このアプリの通知がオフになっています。端末の設定で通知を許可してください。',
  ),
  _CopyRow(
    'errorNotificationsUpdateFailed',
    (l) => l.errorNotificationsUpdateFailed,
    '알림 설정을 바꾸지 못했습니다. 잠시 후 다시 시도해 주세요.',
    "Couldn't update notification settings. Please try again later.",
    '通知設定を変更できませんでした。しばらくしてからもう一度お試しください。',
  ),
  _CopyRow(
    'settingsProfilePhotoSourceCustom',
    (l) => l.settingsProfilePhotoSourceCustom,
    '직접 올린 사진',
    'Uploaded photo',
    'アップロードした写真',
  ),
  _CopyRow(
    'settingsProfilePhotoSourceSocial',
    (l) => l.settingsProfilePhotoSourceSocial,
    '소셜 계정 사진',
    'Photo from your social account',
    'ソーシャルアカウントの写真',
  ),
  _CopyRow(
    'settingsProfilePhotoSourceNone',
    (l) => l.settingsProfilePhotoSourceNone,
    '없음',
    'None',
    'なし',
  ),
  _CopyRow(
    'settingsProfilePhotoUploading',
    (l) => l.settingsProfilePhotoUploading,
    '사진을 올리는 중…',
    'Uploading photo…',
    '写真をアップロード中…',
  ),
  _CopyRow(
    'settingsProfilePhotoPick',
    (l) => l.settingsProfilePhotoPick,
    '갤러리에서 사진 선택',
    'Choose from gallery',
    'ギャラリーから選択',
  ),
  _CopyRow(
    'settingsProfilePhotoRemove',
    (l) => l.settingsProfilePhotoRemove,
    '올린 사진 삭제',
    'Remove uploaded photo',
    'アップロードした写真を削除',
  ),
  _CopyRow(
    'settingsProfilePhotoUpdated',
    (l) => l.settingsProfilePhotoUpdated,
    '프로필 사진을 변경했습니다.',
    'Profile photo updated.',
    'プロフィール写真を変更しました。',
  ),
  _CopyRow(
    'settingsProfilePhotoRemoved',
    (l) => l.settingsProfilePhotoRemoved,
    '올린 사진을 삭제했습니다.',
    'Uploaded photo removed.',
    'アップロードした写真を削除しました。',
  ),
  _CopyRow(
    'errorProfilePhotoUploadFailed',
    (l) => l.errorProfilePhotoUploadFailed,
    '사진을 올리지 못했습니다. 잠시 후 다시 시도해 주세요.',
    "Couldn't upload the photo. Please try again later.",
    '写真をアップロードできませんでした。しばらくしてからもう一度お試しください。',
  ),
  _CopyRow(
    'errorProfilePhotoRemoveFailed',
    (l) => l.errorProfilePhotoRemoveFailed,
    '사진을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    "Couldn't remove the photo. Please try again later.",
    '写真を削除できませんでした。しばらくしてからもう一度お試しください。',
  ),
  _CopyRow(
    'devToolsSendTestPush',
    (l) => l.devToolsSendTestPush,
    '나에게 테스트 알림 보내기',
    'Send me a test notification',
    '自分にテスト通知を送る',
  ),
  _CopyRow(
    'devToolsSendTestPushDone',
    (l) => l.devToolsSendTestPushDone(3),
    '기기 3대에 테스트 알림을 보냈어요.',
    'Sent a test notification to 3 devices.',
    'テスト通知を3台の端末に送りました。',
  ),
  _CopyRow(
    'devToolsSendTestPushNoDevice',
    (l) => l.devToolsSendTestPushNoDevice,
    '알림을 받을 기기가 없어요. 설정에서 알림 받기를 켜 주세요.',
    'No devices can receive notifications. Turn on "Receive notifications" '
        'in Settings.',
    '通知を受け取る端末がありません。設定で「通知を受け取る」をオンにしてください。',
  ),
  _CopyRow(
    'devToolsSendTestPushDisabled',
    (l) => l.devToolsSendTestPushDisabled,
    '이 환경에서는 테스트 알림을 보낼 수 없어요.',
    'Test notifications are turned off in this environment.',
    'この環境ではテスト通知を送信できません。',
  ),
  _CopyRow(
    'errorAppCheckFailed',
    (l) => l.errorAppCheckFailed,
    _kAppCheckFailedCopy['ko']!,
    _kAppCheckFailedCopy['en']!,
    _kAppCheckFailedCopy['ja']!,
  ),
  _CopyRow(
    'errorWidgetFallbackTitle',
    (l) => l.errorWidgetFallbackTitle,
    '문제가 발생했습니다',
    'Something went wrong',
    '問題が発生しました',
  ),
  _CopyRow(
    'errorWidgetFallbackBody',
    (l) => l.errorWidgetFallbackBody,
    '앱을 종료한 뒤 다시 실행해 주세요.',
    'Close the app and open it again.',
    'アプリを終了して、もう一度起動してください。',
  ),
  _CopyRow(
    'notificationChannelGeneralName',
    (l) => l.notificationChannelGeneralName,
    '일반 알림',
    'General notifications',
    '一般の通知',
  ),
  _CopyRow(
    'notificationChannelGeneralDescription',
    (l) => l.notificationChannelGeneralDescription,
    '이 앱에서 보내는 알림입니다.',
    'Notifications sent by this app.',
    'このアプリから送信される通知です。',
  ),
];

/// 테스트가 대조하는 3 locale.
const List<String> _kLocales = <String>['ko', 'en', 'ja'];

/// 키 이름으로 [_kPhase17Rows] 의 행을 찾는다.
_CopyRow _rowOf(String key) => _kPhase17Rows.singleWhere((r) => r.key == key);

/// [locale] 위젯 트리에서 [resolveExceptionMessage] 로 [exception] 을 해석한다.
Future<String> _resolveIn(
  WidgetTester tester,
  Locale locale,
  AppException exception,
) async {
  late String resolved;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          resolved = resolveExceptionMessage(context, exception);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  group('Phase 17 문구 계약 (T-17-COPY)', () {
    testWidgets('T-17-COPY-01 AppCheckFailedException 은 3 locale verbatim 문구이고 '
        '재로그인 안내와 다르다 (D-42)', (tester) async {
      for (final entry in _kAppCheckFailedCopy.entries) {
        final locale = Locale(entry.key);
        final appCheck = await _resolveIn(
          tester,
          locale,
          const AppCheckFailedException(),
        );
        expect(appCheck, entry.value, reason: 'locale ${entry.key}');

        // D-42 — App Check 차단을 재로그인으로 오안내하면 불필요한 로그아웃을
        // 유도한다(T-17-12). 같은 locale 의 재인증 문구와 달라야 한다.
        final reauth = await _resolveIn(
          tester,
          locale,
          const ReauthenticationRequiredException(),
        );
        expect(appCheck, isNot(reauth), reason: 'locale ${entry.key}');
      }
    });

    test('T-17-COPY-02 ARB 26키가 ko · en · ja 모두 UI-SPEC 셀과 verbatim 같다', () {
      // 양성 대조 — 표가 26행 전부를 담고 있고 키 중복이 없다.
      expect(_kPhase17Rows, hasLength(26));
      expect(_kPhase17Rows.map((r) => r.key).toSet(), hasLength(26));

      for (final code in _kLocales) {
        final l10n = lookupAppLocalizations(Locale(code));
        for (final row in _kPhase17Rows) {
          expect(
            row.read(l10n),
            row.expectedFor(code),
            reason: '${row.key} ($code)',
          );
        }
      }

      // devToolsSendTestPushDone — en 은 ICU plural 이라 count 1 이 단수형이다.
      expect(
        lookupAppLocalizations(const Locale('en')).devToolsSendTestPushDone(1),
        'Sent a test notification to 1 device.',
      );
    });

    testWidgets('T-17-COPY-03 새 예외 3종은 ko 문구로 해석되고 26키 ko 값에 문의 채널 '
        '문구가 없다', (tester) async {
      const ko = Locale('ko');
      final cases = <AppException, String>{
        const NotificationSettingsUpdateException(): _rowOf(
          'errorNotificationsUpdateFailed',
        ).ko,
        const ProfilePhotoUploadException(): _rowOf(
          'errorProfilePhotoUploadFailed',
        ).ko,
        const ProfilePhotoRemoveException(): _rowOf(
          'errorProfilePhotoRemoveFailed',
        ).ko,
      };
      for (final entry in cases.entries) {
        expect(
          await _resolveIn(tester, ko, entry.key),
          entry.value,
          reason: '${entry.key.runtimeType}',
        );
      }

      // 양성 대조를 먼저 — 검사 대상이 26개 전부임을 확인한 뒤 부재를 단언한다.
      final koL10n = lookupAppLocalizations(ko);
      final koValues = _kPhase17Rows.map((r) => r.read(koL10n)).toList();
      expect(koValues, hasLength(26));
      for (final value in koValues) {
        expect(value, isNot(contains('문의')));
        expect(value, isNot(contains('고객센터')));
      }
    });
  });
}
