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

  group('OnboardingNotifier (AsyncNotifier<bool> — Issue #10 Plan 10-14)', () {
    // AsyncValue / AsyncLoading / AsyncData 는 flutter_riverpod 에서 재노출.
    test('Test 1: 초기 로드 완료 전 AsyncLoading → 완료 후 AsyncData(false)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();

      // 직후 read 는 AsyncLoading.
      final initial = container.read(onboardingProvider);
      expect(
        initial,
        isA<AsyncLoading<bool>>(),
        reason: 'build() 가 await SharedPreferences 전에는 loading 이어야 한다',
      );

      // .future 로 settle 대기.
      final resolved = await container.read(onboardingProvider.future);
      expect(resolved, isFalse);
      final afterSettle = container.read(onboardingProvider);
      expect(afterSettle, const AsyncData<bool>(false));
    });

    test('Test 2: seen_version=0 → AsyncData(false) (구 버전)', () async {
      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 0});
      final container = createContainer();
      final resolved = await container.read(onboardingProvider.future);
      expect(resolved, isFalse);
    });

    test('Test 3: seen_version=1 → AsyncData(true) (최신)', () async {
      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});
      final container = createContainer();
      final resolved = await container.read(onboardingProvider.future);
      expect(resolved, isTrue);
      expect(container.read(onboardingProvider), const AsyncData<bool>(true));
    });

    test('Test 4: seen_version=2 → AsyncData(true) (미래 버전도 완료로 간주)', () async {
      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 2});
      final container = createContainer();
      final resolved = await container.read(onboardingProvider.future);
      expect(resolved, isTrue);
    });

    test('Test 5: markSeen() → state=AsyncData(true) + prefs 저장', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      // build 완료 대기.
      await container.read(onboardingProvider.future);

      final notifier = container.read(onboardingProvider.notifier);
      await notifier.markSeen();

      expect(container.read(onboardingProvider), const AsyncData<bool>(true));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('onboarding.seen_version'),
        OnboardingNotifier.currentVersion,
      );
    });

    test('Test 6: reset() → state=AsyncData(false) + prefs 키 제거 '
        '(public — WARNING #8)', () async {
      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});
      final container = createContainer();
      final resolved = await container.read(onboardingProvider.future);
      expect(resolved, isTrue);

      await container.read(onboardingProvider.notifier).reset();

      expect(container.read(onboardingProvider), const AsyncData<bool>(false));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('onboarding.seen_version'), isNull);
    });

    test('Test 7: happy path (markSeen / reset) 에서 crashlytics 미호출', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      await container.read(onboardingProvider.future);

      await container.read(onboardingProvider.notifier).markSeen();
      await container.read(onboardingProvider.notifier).reset();

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
