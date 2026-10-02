// Phase 17 Plan 17-15 — 알림 설정 notifier (T-17-NOTIF).
//
// 「알림 받기」 스위치의 상태 기계를 ProviderContainer 로 검증한다.
// - 스위치 값 = OS 권한 `authorized` ∧ 로컬 opt-in (D-03).
// - 토큰 저장은 정식 사용자만 · 권한 확인 전 getToken 0 (D-02 정정 · Pitfall 3).
// - enable · disable 은 guardAsyncValue 경유 (D-20 ②).
//
// Task 2 — 앱 시작 · 복귀 동기화(D-32) · 언어 변경 갱신(D-31) · expireAt 연장
// (D-33) · onTokenRefresh 교체. 앱 복귀는 test binding 의 lifecycle 전이
// (inactive → resumed)로 흉내 낸다.
//
// 리뷰 fix (Phase 17 code review iteration 1) — WR-03 로그아웃 정리 표식 ·
// 재시도 · 토큰 폐기, WR-05 스위치 처리 중 복귀 보류 · 끄기 opt-in 선행,
// WR-06 stale build 부수효과 차단 (T-17-NOTIF-14~16).
//
// 리뷰 fix (iteration 2) — WR-07 끄기 처리 중 로그아웃 정리가 끝나면 opt-in 을
// 되돌리지 않는다 (T-17-NOTIF-18).
//
// 리뷰 fix (iteration 3) — IN-26 켜기 · 끄기의 첫 await 중 로그아웃 정리가
// 끝나면 opt-in 을 쓰지 않는다 (T-17-NOTIF-19~20).
//
// SDK · Firestore 는 mocktail 로 대체한다 — [MessagingService] ·
// [FcmTokenRepository] · [CrashlyticsService]. SharedPreferences 는
// `setMockInitialValues` 로 채운다. Riverpod 기본 재시도(build 오류 시 타이머)는
// 결정성을 위해 container 에서 끈다.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart';
import 'package:flutter_starter_kit/features/notifications/data/fcm_token_repository.dart';
import 'package:flutter_starter_kit/features/notifications/data/messaging_service.dart';
import 'package:flutter_starter_kit/features/notifications/domain/fcm_token.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMessagingService extends Mock implements MessagingService {}

class _MockFcmTokenRepository extends Mock implements FcmTokenRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockUser extends Mock implements fb.User {}

/// 앱 언어를 고정하는 [LocaleNotifier] — 기기 로케일 · 저장값 복원을 건너뛴다.
class _FixedLocaleNotifier extends LocaleNotifier {
  _FixedLocaleNotifier(this._initial);

  final Locale _initial;

  @override
  Locale build() => _initial;
}

/// 정식 사용자 uid (합성 값).
const String _uid = 'uid-regular-1';

/// 첫 토큰 (합성 값).
const String _token1 = 't1';

/// 테스트 한 건의 협력 객체 묶음.
class _Harness {
  _Harness()
    : messaging = _MockMessagingService(),
      repository = _MockFcmTokenRepository(),
      crashlytics = _MockCrashlyticsService();

  final _MockMessagingService messaging;
  final _MockFcmTokenRepository repository;
  final _MockCrashlyticsService crashlytics;

  /// 기본 stub — 권한 [status] · 토큰 [_token1] · 쓰기 성공 · 갱신 스트림 empty.
  void stubDefaults({
    AuthorizationStatus status = AuthorizationStatus.notDetermined,
    AuthorizationStatus requestResult = AuthorizationStatus.authorized,
  }) {
    when(
      () => messaging.getAuthorizationStatus(),
    ).thenAnswer((_) async => status);
    when(
      () => messaging.requestPermission(),
    ).thenAnswer((_) async => requestResult);
    when(() => messaging.getToken()).thenAnswer((_) async => _token1);
    when(() => messaging.deleteToken()).thenAnswer((_) async => true);
    when(
      () => messaging.onTokenRefresh,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(
      () => repository.upsert(
        uid: any(named: 'uid'),
        token: any(named: 'token'),
      ),
    ).thenAnswer((_) async => const Result<void>.success(null));
    when(
      () => repository.delete(
        uid: any(named: 'uid'),
        token: any(named: 'token'),
      ),
    ).thenAnswer((_) async => const Result<void>.success(null));
    when(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  }

  /// [user] (null = 미로그인) · [initialized] · [locale] 로 container 를 만든다.
  ///
  /// [authStream] 을 주면 [user] 대신 그 스트림이 로그인 상태를 흘린다
  /// (계정 전환 시나리오).
  ProviderContainer container({
    fb.User? user,
    bool initialized = true,
    Locale locale = const Locale('ko'),
    Stream<fb.User?>? authStream,
  }) {
    final container = ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(initialized),
        authStateProvider.overrideWith(
          (ref) => authStream ?? Stream.value(user),
        ),
        messagingServiceProvider.overrideWithValue(messaging),
        fcmTokenRepositoryProvider.overrideWithValue(repository),
        crashlyticsServiceProvider.overrideWithValue(crashlytics),
        localeProvider.overrideWith(() => _FixedLocaleNotifier(locale)),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    // keepAlive 이지만 listen 으로 build 를 즉시 시작한다.
    container.listen(notificationSettingsProvider, (previous, next) {});
    return container;
  }
}

/// 정식(비익명) 사용자 mock.
fb.User _regularUser() {
  final user = _MockUser();
  when(() => user.uid).thenReturn(_uid);
  when(() => user.isAnonymous).thenReturn(false);
  return user;
}

/// 익명 사용자 mock.
fb.User _anonymousUser() {
  final user = _MockUser();
  when(() => user.uid).thenReturn('uid-anon-1');
  when(() => user.isAnonymous).thenReturn(true);
  return user;
}

/// 앱 복귀를 흉내 낸다 — inactive → resumed 전이 (AppLifecycleListener
/// onResume 조건).
void _simulateResume() {
  final binding = TestWidgetsFlutterBinding.instance
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

/// [repository] 에 upsert 된 토큰 문서를 호출 순서대로 돌려준다 (기록 소비).
List<FcmToken> _capturedUpserts(_MockFcmTokenRepository repository) => verify(
  () => repository.upsert(
    uid: _uid,
    token: captureAny(named: 'token'),
  ),
).captured.cast<FcmToken>();

/// 현재 state 값 (build 완료 대기).
Future<bool> _settledValue(ProviderContainer container) =>
    container.read(notificationSettingsProvider.future);

/// SharedPreferences 의 `getInstance()` 캐시만 비운다 — 저장된 값은 그대로다.
///
/// `setMockInitialValues` 가 legacy 구현의 `_completer` 를 null 로 되돌린다.
/// 캐시가 빈 채로 두 호출이 겹치면 첫 호출자는 저장소 읽기를 await 하고, 두
/// 번째 호출자는 `_completer!.future` 에 먼저 listener 를 걸어 첫 호출자보다
/// 먼저 재개된다(shared_preferences 2.5.5 `shared_preferences_legacy.dart`
/// `getInstance`). 그래야 토글이 첫 await 에 머무는 동안 로그아웃 정리가 끝까지
/// 실행된다 — 캐시가 차 있으면 토글이 먼저 재개되어 이 순서가 생기지 않는다.
Future<void> _resetPrefsCache() async {
  final prefs = await SharedPreferences.getInstance();
  SharedPreferences.setMockInitialValues(<String, Object>{
    for (final key in prefs.getKeys()) key: prefs.get(key)!,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      FcmToken.forDevice(
        token: 'fallback',
        platform: 'android',
        locale: 'en',
        now: DateTime.utc(2026),
      ),
    );
    registerFallbackValue(StackTrace.empty);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Phase 17 알림 토글 (T-17-NOTIF)', () {
    test('T-17-NOTIF-01: 관통 — 정식 사용자 · 권한 notDetermined · opt-in 없음 → '
        'false · enable() = 권한 요청 → authorized → getToken → upsert '
        '(uid · token · platform · locale ko · expireAt = now+30d) → opt-in · '
        '등록 토큰 저장 → true · enabled', () async {
      final h = _Harness()..stubDefaults();
      final container = h.container(user: _regularUser());

      expect(await _settledValue(container), isFalse);
      verifyNever(() => h.messaging.requestPermission());
      verifyNever(() => h.messaging.getToken());

      final before = DateTime.now();
      final result = await container
          .read(notificationSettingsProvider.notifier)
          .enable();
      final after = DateTime.now();

      expect(result, NotificationToggleResult.enabled);
      verify(() => h.messaging.requestPermission()).called(1);
      verify(() => h.messaging.getToken()).called(1);
      final captured = verify(
        () => h.repository.upsert(
          uid: _uid,
          token: captureAny(named: 'token'),
        ),
      ).captured;
      expect(captured, hasLength(1));
      final saved = captured.single as FcmToken;
      expect(saved.token, _token1);
      expect(saved.platform, 'android');
      expect(saved.locale, 'ko');
      expect(saved.expireAt.difference(saved.updatedAt), kFcmTokenTtl);
      expect(
        saved.updatedAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        saved.updatedAt.isAfter(after.add(const Duration(seconds: 1))),
        isFalse,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isTrue);
      expect(prefs.getString(kNotificationsRegisteredTokenKey), _token1);
      expect(container.read(notificationSettingsProvider).value, isTrue);
    });

    test('T-17-NOTIF-02: 권한 거부 → getToken 0 · upsert 0 · false · '
        'permissionDenied · opt-in 은 true 로 남는다', () async {
      final h = _Harness()
        ..stubDefaults(requestResult: AuthorizationStatus.denied);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .enable();

      expect(result, NotificationToggleResult.permissionDenied);
      verify(() => h.messaging.requestPermission()).called(1);
      verifyNever(() => h.messaging.getToken());
      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isTrue);
      expect(prefs.getString(kNotificationsRegisteredTokenKey), isNull);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });

    test('T-17-NOTIF-03: 켜진 상태 disable() → 등록 토큰 delete 1회 · opt-in '
        'false · 등록 키 제거 · false · disabled', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .disable();

      expect(result, NotificationToggleResult.disabled);
      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isFalse);
      expect(prefs.getString(kNotificationsRegisteredTokenKey), isNull);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });

    test('T-17-NOTIF-03: delete 가 Failure 면 켜짐 유지 · failed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => const Result<void>.failure(UnknownException()));
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .disable();

      expect(result, NotificationToggleResult.failed);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isTrue);
      expect(prefs.getString(kNotificationsRegisteredTokenKey), _token1);
      expect(container.read(notificationSettingsProvider).value, isTrue);
    });

    for (final (label, user) in <(String, fb.User? Function())>[
      ('익명', _anonymousUser),
      ('미로그인', () => null),
    ]) {
      test('T-17-NOTIF-04: $label → false · enable() = failed · SDK · '
          'repository 호출 0 (D-02 정정)', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          kNotificationsOptInKey: true,
        });
        final h = _Harness()
          ..stubDefaults(status: AuthorizationStatus.authorized);
        final container = h.container(user: user());
        expect(await _settledValue(container), isFalse);

        final result = await container
            .read(notificationSettingsProvider.notifier)
            .enable();

        expect(result, NotificationToggleResult.failed);
        verifyNever(() => h.messaging.getAuthorizationStatus());
        verifyNever(() => h.messaging.requestPermission());
        verifyNever(() => h.messaging.getToken());
        verifyZeroInteractions(h.repository);
        expect(container.read(notificationSettingsProvider).value, isFalse);
      });
    }

    test('T-17-NOTIF-13: requestPermission 이 PlatformException throw → '
        'failed · state 이전 값(false) · recordError 1회 '
        '(reason notification_settings_enable)', () async {
      final h = _Harness()..stubDefaults();
      when(
        () => h.messaging.requestPermission(),
      ).thenThrow(PlatformException(code: 'boom'));
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .enable();

      expect(result, NotificationToggleResult.failed);
      expect(container.read(notificationSettingsProvider).value, isFalse);
      verify(
        () => h.crashlytics.recordError(
          any(that: isA<PlatformException>()),
          any(),
          reason: 'notification_settings_enable',
          fatal: false,
        ),
      ).called(1);
      verifyNever(() => h.messaging.getToken());
    });

    test('T-17-NOTIF-13: disable() 의 delete Failure(AppException) → failed · '
        'recordError 0 (D-20 ① 과 중복 0)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => const Result<void>.failure(UnknownException()));
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .disable();

      expect(result, NotificationToggleResult.failed);
      verifyNever(
        () => h.crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });
    test('T-17-NOTIF-06: 앱 시작 — opt-in ∧ authorized 면 getToken → upsert '
        '(expireAt = now+30d) · true. 복귀 때 권한 denied 면 등록 토큰 delete · '
        'false · opt-in 유지, 다시 authorized 로 복귀하면 재등록 · true (D-32 · '
        'D-33)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());

      final before = DateTime.now();
      expect(await _settledValue(container), isTrue);
      verify(() => h.messaging.getToken()).called(1);
      final first = _capturedUpserts(h.repository);
      expect(first, hasLength(1));
      expect(first.single.token, _token1);
      expect(
        first.single.expireAt.difference(first.single.updatedAt),
        kFcmTokenTtl,
      );
      expect(
        first.single.updatedAt.isBefore(
          before.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      // 같은 토큰 재등록 — 옛 문서 delete 0.
      verifyNever(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      verifyNever(() => h.messaging.requestPermission());

      // 앱 밖에서 권한 off → 복귀.
      when(
        () => h.messaging.getAuthorizationStatus(),
      ).thenAnswer((_) async => AuthorizationStatus.denied);
      _simulateResume();
      expect(await _settledValue(container), isFalse);
      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      verifyNever(() => h.messaging.getToken());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isTrue);
      expect(prefs.getString(kNotificationsRegisteredTokenKey), isNull);

      // 다시 권한 on → 복귀 — 조용히 재등록.
      when(
        () => h.messaging.getAuthorizationStatus(),
      ).thenAnswer((_) async => AuthorizationStatus.authorized);
      _simulateResume();
      expect(await _settledValue(container), isTrue);
      expect(_capturedUpserts(h.repository), hasLength(1));
      expect(prefs.getString(kNotificationsRegisteredTokenKey), _token1);
      verifyNever(() => h.messaging.requestPermission());
    });

    test('T-17-NOTIF-06: 등록 실패(upsert Failure)는 false 가 아니라 '
        'AsyncError(NotificationSettingsUpdateException) — 섹션 오류 배너', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => const Result<void>.failure(UnknownException()));
      final container = h.container(user: _regularUser());

      await expectLater(
        _settledValue(container),
        throwsA(isA<NotificationSettingsUpdateException>()),
      );
      expect(container.read(notificationSettingsProvider).hasError, isTrue);
    });

    test('T-17-NOTIF-07: 켜진 상태에서 앱 언어를 ja 로 바꾸면 upsert 1회 '
        '(locale ja) (D-31)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      expect(_capturedUpserts(h.repository).single.locale, 'ko');

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('ja'));
      expect(await _settledValue(container), isTrue);

      final afterChange = _capturedUpserts(h.repository);
      expect(afterChange, hasLength(1));
      expect(afterChange.single.locale, 'ja');
      expect(afterChange.single.token, _token1);
    });

    test('T-17-NOTIF-08: onTokenRefresh 가 t2 를 내면 t2 upsert 1회 + t1 delete '
        '1회 · 등록 키 = t2 (D-33 · 토큰 교체)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final refresh = StreamController<String>.broadcast();
      addTearDown(refresh.close);
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(() => h.messaging.onTokenRefresh).thenAnswer((_) => refresh.stream);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      expect(_capturedUpserts(h.repository).single.token, _token1);

      refresh.add('t2');
      await pumpEventQueue();

      final refreshed = _capturedUpserts(h.repository);
      expect(refreshed, hasLength(1));
      expect(refreshed.single.token, 't2');
      expect(refreshed.single.locale, 'ko');
      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      verifyNever(() => h.repository.delete(uid: _uid, token: 't2'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kNotificationsRegisteredTokenKey), 't2');
    });

    test('T-17-NOTIF-08: 끈 뒤에 온 토큰 갱신은 등록하지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final refresh = StreamController<String>.broadcast();
      addTearDown(refresh.close);
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(() => h.messaging.onTokenRefresh).thenAnswer((_) => refresh.stream);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      clearInteractions(h.repository);

      expect(
        await container.read(notificationSettingsProvider.notifier).disable(),
        NotificationToggleResult.disabled,
      );
      refresh.add('t2');
      await pumpEventQueue();

      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
    });

    for (final (label, initialized, user)
        in <(String, bool, fb.User? Function())>[
          ('Firebase 미초기화', false, _regularUser),
          ('익명', true, _anonymousUser),
        ]) {
      test('T-17-NOTIF-09: $label → 앱 복귀에도 MessagingService · repository '
          '호출 0', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          kNotificationsOptInKey: true,
          kNotificationsRegisteredTokenKey: _token1,
        });
        final h = _Harness()
          ..stubDefaults(status: AuthorizationStatus.authorized);
        final container = h.container(user: user(), initialized: initialized);
        expect(await _settledValue(container), isFalse);

        _simulateResume();
        expect(await _settledValue(container), isFalse);

        verifyZeroInteractions(h.messaging);
        verifyZeroInteractions(h.repository);
      });
    }

    testWidgets('T-17-NOTIF-09: App 위젯(Firebase 미초기화) — 알림 notifier 가 '
        '앱 시작 때 활성화되고 throw 0 · 값 false', (tester) async {
      SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
      addTearDown(() => SplashConfig.overrideMinDuration = null);
      final h = _Harness()..stubDefaults();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isFirebaseInitializedProvider.overrideWithValue(false),
            messagingServiceProvider.overrideWithValue(h.messaging),
            fcmTokenRepositoryProvider.overrideWithValue(h.repository),
          ],
          child: const App(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(App)),
      );
      expect(container.exists(notificationSettingsProvider), isTrue);
      expect(container.read(notificationSettingsProvider).value, isFalse);

      _simulateResume();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      verifyZeroInteractions(h.messaging);
      verifyZeroInteractions(h.repository);
    });
    test('T-17-NOTIF-11: clearForSignOut() → 등록 토큰 delete 1회(현 사용자 uid) '
        '· opt-in · 등록 키 제거 · false (D-30)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);

      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();

      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });

    test('T-17-NOTIF-11: 등록 토큰이 없으면 delete 0 · opt-in 제거 · false', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
      });
      final h = _Harness()..stubDefaults();
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);

      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();

      verifyNever(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });

    test('T-17-NOTIF-11: delete 가 Failure 여도 키 제거 · false · throw 0', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => const Result<void>.failure(UnknownException()));
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);

      await expectLater(
        container.read(notificationSettingsProvider.notifier).clearForSignOut(),
        completes,
      );

      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });

    test('T-17-NOTIF-11: delete 가 끝나지 않아도(오프라인) 로컬 키는 먼저 '
        '지워진다 — 다음 계정은 꺼짐으로 시작', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final pendingDelete = Completer<Result<void>>();
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) => pendingDelete.future);

      final clearing = container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);

      pendingDelete.complete(const Result<void>.success(null));
      await clearing;
    });
  });

  group('Phase 17 리뷰 WR-03 — 로그아웃 정리 표식 · 재시도 · 토큰 폐기', () {
    test('T-17-NOTIF-14: 오프라인 로그아웃(삭제 미완료) → 삭제 대기 기록 · '
        '폐기 표식은 네트워크 전에 남고 등록 키 · opt-in 은 지워진다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      // 오프라인 — 삭제가 서버 ack 를 받지 못한다(바깥 3초 상한이 끊는 상황).
      final pendingDelete = Completer<Result<void>>();
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) => pendingDelete.future);

      unawaited(
        container.read(notificationSettingsProvider.notifier).clearForSignOut(),
      );
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kNotificationsPendingTokenDeletionKey), [
        _uid,
        _token1,
      ]);
      expect(prefs.getBool(kNotificationsTokenRevokePendingKey), isTrue);
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      // 삭제가 끝나지 않았으므로 폐기 단계에도 아직 가지 않았다.
      verifyNever(() => h.messaging.deleteToken());
    });

    test('T-17-NOTIF-14: 정상 로그아웃(삭제 확정) → 삭제 대기 기록 · 폐기 '
        '표식 모두 소거 · 토큰 폐기 0', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);

      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsPendingTokenDeletionKey), isFalse);
      expect(prefs.containsKey(kNotificationsTokenRevokePendingKey), isFalse);
      verifyNever(() => h.messaging.deleteToken());
    });

    test('T-17-NOTIF-14: 삭제 실패 → 토큰 폐기를 바로 시도 · 확정되면 폐기 '
        '표식만 지우고 같은 uid 재시도 기록은 남긴다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => const Result<void>.failure(UnknownException()));

      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();

      verify(() => h.messaging.deleteToken()).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsTokenRevokePendingKey), isFalse);
      expect(prefs.getStringList(kNotificationsPendingTokenDeletionKey), [
        _uid,
        _token1,
      ]);
    });

    test('T-17-NOTIF-15: 같은 uid 재로그인 → build 가 문서 삭제를 재시도 · '
        '성공하면 기록 · 폐기 표식 소거 · 토큰 폐기 0', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsPendingTokenDeletionKey: <String>[_uid, _token1],
        kNotificationsTokenRevokePendingKey: true,
      });
      final h = _Harness()..stubDefaults();
      final container = h.container(user: _regularUser());

      expect(await _settledValue(container), isFalse);
      await pumpEventQueue();

      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsPendingTokenDeletionKey), isFalse);
      expect(prefs.containsKey(kNotificationsTokenRevokePendingKey), isFalse);
      verifyNever(() => h.messaging.deleteToken());
    });

    test('T-17-NOTIF-15: 다른 uid 가 켤 때 → deleteToken 이 getToken 보다 먼저 · '
        '폐기 확정 뒤 이전 계정 기록은 버린다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsPendingTokenDeletionKey: <String>['uid-previous', 't0'],
        kNotificationsTokenRevokePendingKey: true,
      });
      final h = _Harness()..stubDefaults();
      final sdkCalls = <String>[];
      // build 의 기회성 폐기는 실패(오프라인)하고, 켤 때의 폐기는 성공한다.
      final revokeResults = <bool>[false, true];
      when(() => h.messaging.deleteToken()).thenAnswer((_) async {
        sdkCalls.add('deleteToken');
        return revokeResults.removeAt(0);
      });
      when(() => h.messaging.getToken()).thenAnswer((_) async {
        sdkCalls.add('getToken');
        return _token1;
      });
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);
      await pumpEventQueue();

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .enable();

      expect(result, NotificationToggleResult.enabled);
      expect(sdkCalls, ['deleteToken', 'deleteToken', 'getToken']);
      // rules 상 지울 수 없는 다른 계정 문서 — 무효 토큰이 되어 버린다.
      verifyNever(() => h.repository.delete(uid: 'uid-previous', token: 't0'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsTokenRevokePendingKey), isFalse);
      expect(prefs.containsKey(kNotificationsPendingTokenDeletionKey), isFalse);
      expect(_capturedUpserts(h.repository).single.token, _token1);
    });

    test('T-17-NOTIF-15: 토큰 폐기 실패 → enable failed · getToken · upsert 0 '
        '(이전 토큰으로 새 계정을 등록하지 않는다)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsPendingTokenDeletionKey: <String>['uid-previous', 't0'],
        kNotificationsTokenRevokePendingKey: true,
      });
      final h = _Harness()..stubDefaults();
      when(() => h.messaging.deleteToken()).thenAnswer((_) async => false);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);
      await pumpEventQueue();

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .enable();

      expect(result, NotificationToggleResult.failed);
      verifyNever(() => h.messaging.getToken());
      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsTokenRevokePendingKey), isTrue);
      expect(prefs.getStringList(kNotificationsPendingTokenDeletionKey), [
        'uid-previous',
        't0',
      ]);
    });
  });

  group('Phase 17 리뷰 WR-05 — 스위치 처리 중 앱 복귀', () {
    test('T-17-NOTIF-16: disable() 의 삭제 대기 중 복귀 → 재빌드 보류 · '
        'upsert 0 · 최종 꺼짐', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      clearInteractions(h.repository);
      clearInteractions(h.messaging);
      final pendingDelete = Completer<Result<void>>();
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) => pendingDelete.future);

      final disabling = container
          .read(notificationSettingsProvider.notifier)
          .disable();
      await pumpEventQueue();
      _simulateResume();
      await pumpEventQueue();
      pendingDelete.complete(const Result<void>.success(null));

      expect(await disabling, NotificationToggleResult.disabled);
      expect(await _settledValue(container), isFalse);
      verifyNever(() => h.messaging.getAuthorizationStatus());
      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isFalse);
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
    });

    test('T-17-NOTIF-16: disable() 은 삭제 대기 중에 opt-in 을 이미 false 로 '
        '둔다 — 진행 중인 재동기화가 같은 토큰을 다시 등록하지 않게', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      final pendingDelete = Completer<Result<void>>();
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) => pendingDelete.future);

      final disabling = container
          .read(notificationSettingsProvider.notifier)
          .disable();
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kNotificationsOptInKey), isFalse);

      pendingDelete.complete(const Result<void>.success(null));
      expect(await disabling, NotificationToggleResult.disabled);
    });

    test('T-17-NOTIF-16: enable() 중 권한 다이얼로그가 일으킨 복귀 → '
        'getToken · upsert 각 1회 (등록 2중 실행 0)', () async {
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      when(() => h.messaging.requestPermission()).thenAnswer((_) async {
        // Android 13+ — OS 다이얼로그가 닫히며 inactive → resumed.
        _simulateResume();
        await pumpEventQueue();
        return AuthorizationStatus.authorized;
      });
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);

      final result = await container
          .read(notificationSettingsProvider.notifier)
          .enable();
      expect(await _settledValue(container), isTrue);
      await pumpEventQueue();

      expect(result, NotificationToggleResult.enabled);
      verify(() => h.messaging.getToken()).called(1);
      expect(_capturedUpserts(h.repository), hasLength(1));
    });
  });

  group('Phase 17 리뷰 WR-06 — stale build 부수효과 차단', () {
    test('T-17-NOTIF-17: build 의 권한 조회 대기 중 복귀 재빌드 → 이전 build 는 '
        'upsert 하지 않는다 (upsert 1회 = 새 build 몫)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final firstStatus = Completer<AuthorizationStatus>();
      var statusCalls = 0;
      when(() => h.messaging.getAuthorizationStatus()).thenAnswer((_) {
        statusCalls++;
        return statusCalls == 1
            ? firstStatus.future
            : Future.value(AuthorizationStatus.authorized);
      });
      final container = h.container(user: _regularUser());
      await pumpEventQueue();
      expect(statusCalls, 1);

      _simulateResume();
      expect(await _settledValue(container), isTrue);
      firstStatus.complete(AuthorizationStatus.authorized);
      await pumpEventQueue();

      expect(_capturedUpserts(h.repository), hasLength(1));
      verify(() => h.messaging.getToken()).called(1);
    });

    test('T-17-NOTIF-17: build 대기 중 계정이 바뀌면(로그아웃) 이전 uid 로 '
        'upsert 0 · 등록 키 미기록', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final firstStatus = Completer<AuthorizationStatus>();
      when(
        () => h.messaging.getAuthorizationStatus(),
      ).thenAnswer((_) => firstStatus.future);
      final auth = StreamController<fb.User?>();
      addTearDown(auth.close);
      final container = h.container(authStream: auth.stream);
      auth.add(_regularUser());
      await pumpEventQueue();

      auth.add(null);
      expect(await _settledValue(container), isFalse);
      firstStatus.complete(AuthorizationStatus.authorized);
      await pumpEventQueue();

      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
    });

    test('T-17-NOTIF-17: build 가 토큰을 받는 중 clearForSignOut → 이전 build '
        '는 정리된 토큰 문서를 다시 쓰지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      // opt-in 확인을 지난 뒤(_register 의 getToken)에서 멈춘다.
      final firstToken = Completer<String?>();
      when(() => h.messaging.getToken()).thenAnswer((_) => firstToken.future);
      final container = h.container(user: _regularUser());
      await pumpEventQueue();
      verify(() => h.messaging.getToken()).called(1);

      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();
      firstToken.complete(_token1);
      await pumpEventQueue();

      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });

    test('T-17-NOTIF-17: 첫 등록(enable)의 upsert 대기 중 clearForSignOut → '
        '정리가 새 토큰 문서도 지운다 · enable 은 failed', () async {
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final pendingUpsert = Completer<Result<void>>();
      when(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) => pendingUpsert.future);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);

      final enabling = container
          .read(notificationSettingsProvider.notifier)
          .enable();
      await pumpEventQueue();
      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();
      pendingUpsert.complete(const Result<void>.success(null));

      expect(await enabling, NotificationToggleResult.failed);
      // 등록 키를 upsert 전에 써 두었으므로 정리가 지울 토큰을 알았다.
      verify(() => h.repository.delete(uid: _uid, token: _token1)).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);
    });
  });

  group('Phase 17 리뷰 WR-07 — 끄기 처리 중 로그아웃 정리', () {
    test('T-17-NOTIF-18: disable() 의 삭제 대기 중 clearForSignOut 이 끝난 뒤 '
        '삭제가 실패해도 opt-in 을 되살리지 않는다 · 다음 계정은 꺼짐', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
        kNotificationsRegisteredTokenKey: _token1,
      });
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isTrue);
      // 첫 삭제(끄기)만 오프라인으로 멈추고, 정리의 삭제는 확정된다.
      final pendingDelete = Completer<Result<void>>();
      final deleteResults = <Future<Result<void>>>[
        pendingDelete.future,
        Future.value(const Result<void>.success(null)),
      ];
      when(
        () => h.repository.delete(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) => deleteResults.removeAt(0));

      final disabling = container
          .read(notificationSettingsProvider.notifier)
          .disable();
      await pumpEventQueue();
      await container
          .read(notificationSettingsProvider.notifier)
          .clearForSignOut();
      pendingDelete.complete(const Result<void>.failure(UnknownException()));

      expect(await disabling, NotificationToggleResult.failed);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      expect(container.read(notificationSettingsProvider).value, isFalse);

      // 같은 기기에 다른 계정(B)이 로그인 — 켠 적이 없으니 꺼짐 · 등록 0.
      clearInteractions(h.repository);
      clearInteractions(h.messaging);
      final userB = _MockUser();
      when(() => userB.uid).thenReturn('uid-regular-2');
      when(() => userB.isAnonymous).thenReturn(false);
      final containerB = h.container(user: userB);
      expect(await _settledValue(containerB), isFalse);
      await pumpEventQueue();
      verifyNever(() => h.messaging.getToken());
      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
    });
  });

  group('Phase 17 리뷰 IN-26 — 토글 첫 await 중 로그아웃 정리', () {
    test('T-17-NOTIF-19: enable() 의 첫 await 중 clearForSignOut 이 끝나면 '
        'opt-in 을 쓰지 않는다 · failed · 다음 계정은 꺼짐', () async {
      final h = _Harness()
        ..stubDefaults(status: AuthorizationStatus.authorized);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);
      await pumpEventQueue();
      await _resetPrefsCache();

      final notifier = container.read(notificationSettingsProvider.notifier);
      final enabling = notifier.enable();
      await notifier.clearForSignOut();

      expect(await enabling, NotificationToggleResult.failed);
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);

      // 같은 기기에 다른 계정(B)이 로그인 — 켠 적이 없으니 꺼짐 · 등록 0.
      clearInteractions(h.repository);
      clearInteractions(h.messaging);
      final userB = _MockUser();
      when(() => userB.uid).thenReturn('uid-regular-2');
      when(() => userB.isAnonymous).thenReturn(false);
      final containerB = h.container(user: userB);
      expect(await _settledValue(containerB), isFalse);
      await pumpEventQueue();
      verifyNever(() => h.messaging.getToken());
      verifyNever(
        () => h.repository.upsert(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
        ),
      );
    });

    test('T-17-NOTIF-20: disable() 의 첫 await 중 clearForSignOut 이 끝나면 '
        '(등록 토큰 없음) opt-in 을 쓰지 않는다 · failed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kNotificationsOptInKey: true,
      });
      final h = _Harness()..stubDefaults(status: AuthorizationStatus.denied);
      final container = h.container(user: _regularUser());
      expect(await _settledValue(container), isFalse);
      await pumpEventQueue();
      await _resetPrefsCache();

      final notifier = container.read(notificationSettingsProvider.notifier);
      final disabling = notifier.disable();
      await notifier.clearForSignOut();

      expect(await disabling, NotificationToggleResult.failed);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kNotificationsOptInKey), isFalse);
      expect(prefs.containsKey(kNotificationsRegisteredTokenKey), isFalse);
    });
  });
}
