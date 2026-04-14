import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _FakeStackTrace extends Fake implements StackTrace {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeStackTrace());
  });

  late _MockCrashlyticsService mockCrashlytics;

  setUp(() {
    mockCrashlytics = _MockCrashlyticsService();
    when(
      () => mockCrashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('OnboardingNotifier', () {
    test('Test 1: SharedPreferences 빈 상태 → build() false', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();

      // 동기 초기값 확인
      expect(container.read(onboardingProvider), isFalse);

      // 비동기 _loadSeenStatus 완료 대기
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(onboardingProvider), isFalse);
    });

    test('Test 2: seen_version=0 저장 → build() false (구 버전)', () async {
      SharedPreferences.setMockInitialValues({
        'onboarding.seen_version': 0,
      });
      final container = createContainer();
      container.read(onboardingProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(onboardingProvider), isFalse);
    });

    test('Test 3: seen_version=1 저장 → build() true (최신)', () async {
      SharedPreferences.setMockInitialValues({
        'onboarding.seen_version': 1,
      });
      final container = createContainer();
      container.read(onboardingProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(onboardingProvider), isTrue);
    });

    test('Test 4: seen_version=2 저장 → build() true (미래 버전도 완료로 간주)',
        () async {
      SharedPreferences.setMockInitialValues({
        'onboarding.seen_version': 2,
      });
      final container = createContainer();
      container.read(onboardingProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(onboardingProvider), isTrue);
    });

    test(
        'Test 5: markSeen() → state=true + SharedPreferences에 currentVersion 저장',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();

      final notifier = container.read(onboardingProvider.notifier);
      await notifier.markSeen();

      expect(container.read(onboardingProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('onboarding.seen_version'),
        OnboardingNotifier.currentVersion,
      );
    });

    test(
        'Test 6: reset() → state=false + SharedPreferences 키 제거 (public 메서드, '
        'WARNING #8 — @visibleForTesting 없이 일반 호출)', () async {
      SharedPreferences.setMockInitialValues({
        'onboarding.seen_version': 1,
      });
      final container = createContainer();

      // build 비동기 복원 대기 → state=true
      container.read(onboardingProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(onboardingProvider), isTrue);

      // public reset() 호출 (WARNING #8: production 표면)
      await container.read(onboardingProvider.notifier).reset();

      expect(container.read(onboardingProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('onboarding.seen_version'), isNull);
    });

    test(
        'Test 7: markSeen 후 _loadSeenStatus 정상 경로에서 crashlytics 미호출',
        () async {
      // SharedPreferences mock 은 throw 하지 않으므로 happy path 만 검증.
      // Phase 1 D-13 철학상 disk 장애는 fallback 만 되면 OK.
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      await container.read(onboardingProvider.notifier).markSeen();

      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });
  });
}
