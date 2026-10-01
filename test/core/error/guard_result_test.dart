import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/guard_result.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_banner.dart';

/// [CrashlyticsService] mocktail 대역 — 기록 횟수 · reason 검증용.
class MockCrashlyticsService extends Mock implements CrashlyticsService {}

void main() {
  late MockCrashlyticsService crashlytics;

  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  setUp(() {
    crashlytics = MockCrashlyticsService();
    when(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  });

  group('Phase 17 오류 안전망 (T-17-ERR)', () {
    testWidgets('T-17-ERR-01 예상치 못한 오류 → 기록 1회 · UnknownException · 배너 문구', (
      tester,
    ) async {
      final result = await guardResult<int>(
        'demo_repo_load',
        () async => throw StateError('boom'),
        crashlytics: crashlytics,
      );

      expect(result, isA<Failure<int>>());
      final failure = result as Failure<int>;
      expect(failure.exception, isA<UnknownException>());
      verify(
        () => crashlytics.recordError(
          any(that: isA<StateError>()),
          any(),
          reason: 'demo_repo_load',
          fatal: false,
        ),
      ).called(1);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ko'),
          home: Scaffold(body: ErrorBanner(exception: failure.exception)),
        ),
      );

      final ko = lookupAppLocalizations(const Locale('ko'));
      expect(find.text(ko.errorUnknown), findsOneWidget);
    });

    test('T-17-ERR-02 AppException 은 그대로 실패 · 기록 0', () async {
      const unavailable = ServiceUnavailable();

      final result = await guardResult<int>(
        'demo_repo_load',
        () async => throw unavailable,
        crashlytics: crashlytics,
      );

      expect(result, isA<Failure<int>>());
      expect((result as Failure<int>).exception, same(unavailable));
      verifyNever(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('T-17-ERR-03 성공하면 Success(값) · 기록 0', () async {
      final result = await guardResult<int>(
        'demo_repo_load',
        () async => 42,
        crashlytics: crashlytics,
      );

      expect(result, isA<Success<int>>());
      expect((result as Success<int>).data, 42);
      verifyNever(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });
  });
}
