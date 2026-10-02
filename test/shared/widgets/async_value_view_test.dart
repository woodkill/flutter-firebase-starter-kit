import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/async_value_view.dart';
import 'package:flutter_starter_kit/shared/widgets/error_banner.dart';

/// [child] 를 ko 로케일 · 앱 테마로 pump 하는 헬퍼.
Future<void> pumpKo(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: Scaffold(body: child),
    ),
  );
}

/// data builder — 값을 문자열로 그린다.
Widget renderData(int data) => Text('data:$data');

void main() {
  group('Phase 17 오류 안전망 (T-17-ERR)', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    testWidgets('T-17-ERR-07 loading 기본값은 CircularProgressIndicator 1개', (
      tester,
    ) async {
      await pumpKo(
        tester,
        const AsyncValueView<int>(value: AsyncLoading<int>(), data: renderData),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('data:3'), findsNothing);
    });

    testWidgets('T-17-ERR-07 error 기본값은 ErrorBanner 문구 + 재시도 콜백 1회', (
      tester,
    ) async {
      var retryCount = 0;
      await pumpKo(
        tester,
        AsyncValueView<int>(
          value: AsyncError<int>(StateError('boom'), StackTrace.empty),
          data: renderData,
          onRetry: () => retryCount++,
        ),
      );

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text(ko.errorUnknown), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.text(ko.commonRetry));
      await tester.pump();

      expect(retryCount, 1);
    });

    testWidgets('T-17-ERR-07 onRetry 가 없으면 재시도 버튼 0', (tester) async {
      await pumpKo(
        tester,
        AsyncValueView<int>(
          value: AsyncError<int>(StateError('boom'), StackTrace.empty),
          data: renderData,
        ),
      );

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text(ko.commonRetry), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('T-17-ERR-07 data 상태는 data builder 결과를 그린다', (tester) async {
      await pumpKo(
        tester,
        const AsyncValueView<int>(value: AsyncData<int>(3), data: renderData),
      );

      expect(find.text('data:3'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ErrorBanner), findsNothing);
    });

    testWidgets('T-17-ERR-07 errorPadding 은 기본 오류 표시(배너 · 재시도)만 '
        '감싼다 (리뷰 IN-17)', (tester) async {
      const padding = EdgeInsets.symmetric(horizontal: 16);
      await pumpKo(
        tester,
        AsyncValueView<int>(
          value: AsyncError<int>(StateError('boom'), StackTrace.empty),
          data: renderData,
          onRetry: () {},
          errorPadding: padding,
        ),
      );

      final view = tester.getRect(find.byType(AsyncValueView<int>));
      final banner = tester.getRect(find.byType(ErrorBanner));
      expect(banner.left - view.left, 16);
      expect(view.right - banner.right, 16);
      expect(tester.getRect(find.byType(TextButton)).left - view.left, 16);

      // data 상태에는 여백이 없다.
      await pumpKo(
        tester,
        const AsyncValueView<int>(
          value: AsyncData<int>(3),
          data: renderData,
          errorPadding: padding,
        ),
      );
      expect(
        tester.getRect(find.text('data:3')).left,
        tester.getRect(find.byType(AsyncValueView<int>)).left,
      );
    });

    testWidgets('T-17-ERR-07 loading · error builder 를 주면 기본값 대신 그린다', (
      tester,
    ) async {
      await pumpKo(
        tester,
        AsyncValueView<int>(
          value: const AsyncLoading<int>(),
          data: renderData,
          loading: () => const Text('custom-loading'),
        ),
      );
      expect(find.text('custom-loading'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await pumpKo(
        tester,
        AsyncValueView<int>(
          value: AsyncError<int>(StateError('boom'), StackTrace.empty),
          data: renderData,
          error: (error, stackTrace) => const Text('custom-error'),
        ),
      );
      expect(find.text('custom-error'), findsOneWidget);
      expect(find.byType(ErrorBanner), findsNothing);
    });
  });
}
