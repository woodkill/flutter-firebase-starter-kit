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
  });
}
