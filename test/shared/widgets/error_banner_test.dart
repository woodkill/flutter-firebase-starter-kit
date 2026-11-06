import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';
import 'package:flutter_starter_kit/core/theme/app_radius.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart'
    show FormErrorBanner;
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_banner.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// liveRegion 이 켜진 [Semantics] 위젯 finder.
Finder findLiveRegion() => find.byWidgetPredicate(
  (widget) => widget is Semantics && (widget.properties.liveRegion ?? false),
);

void main() {
  group('Phase 17 오류 안전망 (T-17-ERR)', () {
    testWidgets(
      'T-17-ERR-04 exception null 이면 SizedBox.shrink 만 · liveRegion 0',
      (tester) async {
        await pumpKo(tester, const ErrorBanner(exception: null));

        expect(
          find.descendant(
            of: find.byType(ErrorBanner),
            matching: find.byType(SizedBox),
          ),
          findsOneWidget,
        );
        expect(tester.getSize(find.byType(ErrorBanner)).height, 0);
        expect(findLiveRegion(), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      },
    );

    testWidgets('T-17-ERR-04 FormErrorBanner 별칭으로 만든 위젯이 ErrorBanner 로 찾아진다', (
      tester,
    ) async {
      await pumpKo(
        tester,
        const FormErrorBanner(exception: ServiceUnavailable()),
      );

      final ko = lookupAppLocalizations(const Locale('ko'));
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text(ko.errorServiceUnavailable), findsOneWidget);
      expect(findLiveRegion(), findsOneWidget);
    });

    testWidgets('T-17-ERR-04 아이콘 크기는 AppIconSizes.sm 토큰을 따른다 '
        '(기본 20 · 리뷰 IN-10)', (tester) async {
      await pumpKo(tester, const ErrorBanner(exception: ServiceUnavailable()));
      expect(
        tester.getSize(find.byIcon(Icons.error_outline)),
        const Size(20, 20),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[
              const AppIconSizes().copyWith(sm: 28),
            ],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ko'),
          home: const Scaffold(
            body: ErrorBanner(exception: ServiceUnavailable()),
          ),
        ),
      );
      // MaterialApp 의 AnimatedTheme 가 테마 전환을 lerp 로 그린다.
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byIcon(Icons.error_outline)),
        const Size(28, 28),
      );
    });

    testWidgets('기본 테마에서 모서리는 AppRadius.sm 기본값 8 이다', (tester) async {
      final container = find.descendant(
        of: find.byType(ErrorBanner),
        matching: find.byType(Container),
      );

      await pumpKo(tester, const ErrorBanner(exception: ServiceUnavailable()));
      expect(
        tester.widget<Container>(container).decoration,
        isA<BoxDecoration>().having(
          (d) => d.borderRadius,
          'borderRadius',
          BorderRadius.circular(8),
        ),
      );
    });

    testWidgets('둥글기 sm · 간격 sm 을 함께 바꾼 테마에서 모서리는 둥글기 값이다', (tester) async {
      // 첫 pump 로 그려 AnimatedTheme 보간 없이 최종 값을 본다.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[
              const AppRadius().copyWith(sm: 2),
              const AppSpacing().copyWith(sm: 10),
            ],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ko'),
          home: const Scaffold(
            body: ErrorBanner(exception: ServiceUnavailable()),
          ),
        ),
      );

      final container = find.descendant(
        of: find.byType(ErrorBanner),
        matching: find.byType(Container),
      );
      expect(
        tester.widget<Container>(container).decoration,
        isA<BoxDecoration>().having(
          (d) => d.borderRadius,
          'borderRadius',
          BorderRadius.circular(2),
        ),
      );
    });
  });
}
