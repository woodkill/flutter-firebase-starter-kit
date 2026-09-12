import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';

/// 쓰기만 실패하는 SharedPreferences 스토어 (10-REVIEW CR-03 회귀 재현용).
///
/// `setMockInitialValues` 가 설치하는 in-memory 스토어는 쓰기가 항상 성공해서
/// 영속화 실패 경로를 재현할 수 없다. 읽기/삭제는 정상 동작시키고 `setValue`
/// 만 던지게 하여 `markSeen()` 의 catch 분기를 정확히 겨냥한다.
/// `terms_notifier_test.dart` 의 동명 클래스와 같은 형태다.
class _WriteFailingPrefsStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.of(_values);

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    throw StateError('prefs write failed (CR-03 회귀 재현)');
  }
}

/// 삭제만 실패하는 SharedPreferences 스토어 (10-REVIEW CR-03 회귀 재현용).
///
/// 위 `_WriteFailingPrefsStore` 와의 차이: 그쪽은 `setValue` 만 던지므로
/// `prefs.remove` 를 쓰는 `reset()` 의 catch 분기는 아예 발동하지 않는다.
/// 이 스토어는 반대로 **삭제만** 실패시켜 그 분기를 겨냥한다. 던지는 값은
/// Error 계열이어야 한다 — `Exception` 을 던지면 CR-03 확장 이전의
/// `on Exception` 지정자에도 잡혀 회귀가 드러나지 않는다.
/// `terms_notifier_test.dart` 의 동명 클래스와 같은 형태다.
class _RemoveFailingPrefsStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.of(_values);

  @override
  Future<bool> remove(String key) async {
    throw StateError('prefs remove failed (CR-03 회귀 재현)');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _values[key] = value;
    return true;
  }
}

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

    test('O1 (10-REVIEW CR-03): seen_version 이 String 이면 getInt 가 cast '
        'TypeError 를 던지지만 AsyncData(false) 로 graceful 종료', () async {
      // 인위적 mock throw 가 아니라 진짜 cast 실패다 — shared_preferences 의
      // getInt 는 캐시값을 int? 로 캐스팅하므로 다운그레이드/키 재사용으로
      // 타입이 바뀐 저장값에서 Error 계열이 난다.
      SharedPreferences.setMockInitialValues({
        'onboarding.seen_version': 'corrupt',
      });
      final container = createContainer();

      final resolved = await container.read(onboardingProvider.future);
      expect(resolved, isFalse, reason: '손상값은 lossy fallback false 로 흡수되어야 한다');
      expect(container.read(onboardingProvider), const AsyncData<bool>(false));
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'onboarding_load',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
    });

    test('O2 (10-REVIEW IN-08): 손상된 seen_version 을 제거해 재발을 끊는다', () async {
      // 정리하지 않으면 cast 실패가 매 cold start 마다 재발해 같은
      // Crashlytics 리포트가 반복 적재된다 (terms_notifier 와 대칭).
      SharedPreferences.setMockInitialValues({
        'onboarding.seen_version': 'corrupt',
      });
      final container = createContainer();

      await container.read(onboardingProvider.future);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.get('onboarding.seen_version'),
        isNull,
        reason: '손상값이 남아 있으면 다음 cold start 가 같은 실패를 반복한다',
      );
    });

    test('O3 (10-REVIEW CR-03 쓰기 경로): markSeen() 의 prefs 저장이 Error 계열로 '
        '실패해도 throw 없이 AsyncData(true) 를 유지한다', () async {
      // 확장 이전 지정자(`on Exception`)에서는 StateError 가 흡수되지 않고
      // 밖으로 새어 온보딩 완료 처리가 unhandled 로 터졌다.
      SharedPreferences.setMockInitialValues({});
      final originalStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _WriteFailingPrefsStore();
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = originalStore;
        SharedPreferences.resetStatic();
      });

      final container = createContainer();
      await container.read(onboardingProvider.future);
      final notifier = container.read(onboardingProvider.notifier);

      await notifier.markSeen();

      expect(
        container.read(onboardingProvider),
        const AsyncData<bool>(true),
        reason: 'lossy persistence — 디스크 쓰기 실패는 state 를 되돌리지 않는다',
      );
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'onboarding_save',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
    });

    test('O4 (10-REVIEW CR-03 쓰기 경로): reset() 의 prefs 삭제가 Error 계열로 '
        '실패해도 throw 없이 AsyncData(false) 를 유지한다', () async {
      // 확장 이전 지정자(`on Exception`)에서는 StateError 가 흡수되지 않고
      // 밖으로 새어 Dev Tools 초기화가 unhandled 로 터졌다.
      SharedPreferences.setMockInitialValues({});
      final originalStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _RemoveFailingPrefsStore();
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = originalStore;
        SharedPreferences.resetStatic();
      });

      final container = createContainer();
      await container.read(onboardingProvider.future);
      final notifier = container.read(onboardingProvider.notifier);

      // setMockInitialValues 의 초기값은 이 fake 스토어에 반영되지 않으므로
      // seed 는 markSeen() 으로 만든다 (이 스토어는 setValue 가 성공한다).
      await notifier.markSeen();
      expect(container.read(onboardingProvider), const AsyncData<bool>(true));

      await notifier.reset();

      // 삭제 실패 여부를 prefs.get(...) 으로 단언하지 않는다 —
      // SharedPreferences 는 `_store.remove` 호출 전에 캐시를 먼저 비우므로
      // 성공/실패 양쪽에서 null 이 나오는 self-satisfying 단언이 된다.
      expect(container.read(onboardingProvider), const AsyncData<bool>(false));
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'onboarding_reset',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
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
