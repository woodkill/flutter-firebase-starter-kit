import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/error_widget_builder.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_fallback.dart';

import '../../helpers/source_text.dart';

/// [width]×[height] logical viewport 를 DPR 1 로 주입한다.
void setViewport(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// [home] 을 [locale] · 앱 라이트 테마 [MaterialApp] 안에 그린다.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// 버튼 계열 위젯(ElevatedButton · TextButton · OutlinedButton · FilledButton
/// · IconButton) finder — 대체 화면에는 재시도 버튼이 없어야 한다.
Finder findAnyButton() => find.byWidgetPredicate(
  (widget) => widget is ButtonStyleButton || widget is IconButton,
);

void main() {
  group('Phase 17 깨진 화면 대체 (T-17-FALLBACK)', () {
    testWidgets(
      'T-17-FALLBACK-01 관통: 빌드 예외 → buildReleaseErrorWidget → 기록 1회 + ko 문구 · 버튼 0',
      (tester) async {
        setViewport(tester, 280, 800);
        final details = FlutterErrorDetails(
          exception: StateError('secret-internal-detail'),
          stack: StackTrace.current,
        );
        final recorded = <FlutterErrorDetails>[];

        await pumpLocalized(
          tester,
          Builder(
            builder: (_) =>
                buildReleaseErrorWidget(details, onBuildError: recorded.add),
          ),
        );

        final ko = lookupAppLocalizations(const Locale('ko'));
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorFallback), findsOneWidget);
        expect(find.text(ko.errorWidgetFallbackTitle), findsOneWidget);
        expect(find.text(ko.errorWidgetFallbackBody), findsOneWidget);
        // 기록은 그 details 그대로 정확히 1회.
        expect(recorded, hasLength(1));
        expect(identical(recorded.single, details), isTrue);
        // 재시도 버튼 없음 · 예외 문자열 노출 없음 (T-17-24).
        expect(findAnyButton(), findsNothing);
        expect(find.textContaining('secret-internal-detail'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);
        expect(kErrorWidgetBuildReason, 'error_widget_build');
      },
    );

    test(
      'T-17-FALLBACK-02 소스 계약: bootstrap 이 !kDebugMode 에서만 ErrorWidget.builder 를 설치하고 기존 fatal 경로를 유지한다',
      () {
        final source = stripBlockComments(
          stripSlashComments(readTrackedFile('lib/core/bootstrap.dart')),
        );

        // 양성 대조 — 같은 API 가 기존 fatal 경로를 실제로 센다.
        expect(countOccurrences(source, 'recordFlutterFatalError'), 1);

        expect(countOccurrences(source, 'ErrorWidget.builder ='), 1);
        expect(countOccurrences(source, 'kErrorWidgetBuildReason'), 1);
        expect(
          countOccurrences(source, 'fatal: false'),
          greaterThanOrEqualTo(1),
        );

        // builder 대입 직전의 조건이 `!kDebugMode` 여야 한다 — debug 는 SDK
        // 기본 빨간 화면을 유지한다 (D-22).
        final builderAt = source.indexOf('ErrorWidget.builder =');
        final guardAt = source.lastIndexOf('if (!kDebugMode) {', builderAt);
        expect(guardAt, greaterThanOrEqualTo(0));
        final between = source.substring(guardAt, builderAt);
        expect(between.contains('}'), isFalse);

        // 설치는 Firebase 초기화 분기 밖 · runApp 앞이다.
        final runAppAt = source.indexOf('runApp(');
        expect(builderAt, lessThan(runAppAt));
        final initCatchAt = source.indexOf(
          "debugPrint('bootstrap 초기화 실패 (Firebase 비활성)",
        );
        expect(initCatchAt, greaterThanOrEqualTo(0));
        expect(builderAt, greaterThan(initCatchAt));
      },
    );
  });
}
