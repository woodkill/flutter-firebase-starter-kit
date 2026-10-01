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
  ProviderContainer container({
    fb.User? user,
    bool initialized = true,
    Locale locale = const Locale('ko'),
  }) {
    final container = ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(initialized),
        authStateProvider.overrideWith((ref) => Stream.value(user)),
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
}
