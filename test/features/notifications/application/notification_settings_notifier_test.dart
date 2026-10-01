// Phase 17 Plan 17-15 — 알림 설정 notifier (T-17-NOTIF).
//
// 「알림 받기」 스위치의 상태 기계를 ProviderContainer 로 검증한다.
// - 스위치 값 = OS 권한 `authorized` ∧ 로컬 opt-in (D-03).
// - 토큰 저장은 정식 사용자만 · 권한 확인 전 getToken 0 (D-02 정정 · Pitfall 3).
// - enable · disable 은 guardAsyncValue 경유 (D-20 ②).
//
// SDK · Firestore 는 mocktail 로 대체한다 — [MessagingService] ·
// [FcmTokenRepository] · [CrashlyticsService]. SharedPreferences 는
// `setMockInitialValues` 로 채운다. Riverpod 기본 재시도(build 오류 시 타이머)는
// 결정성을 위해 container 에서 끈다.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 현재 state 값 (build 완료 대기).
Future<bool> _settledValue(ProviderContainer container) =>
    container.read(notificationSettingsProvider.future);

void main() {
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
  });
}
