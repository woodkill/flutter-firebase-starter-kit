// Phase 17 Plan 17-10 — authUserObserver 정식 세션 시작 email mirror 훅 (D-26).
//
// 검증 surface (T-17-MIRROR-03):
// - 정식 사용자 첫 emit → mirror 1회
// - 같은 uid 재emit → 추가 0
// - 익명 첫 emit → 0
// - 익명 → 정식 전이(같은 uid) → 1회
// - 다른 uid 정식 → 1회
// - Firebase 미초기화 → 0
// - 같은 uid 의 emailVerified false → true 전이 → ID token 강제 갱신 뒤 1회 더
//   (리뷰 IN-15 · T-17-MIRROR-03g~i)

import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/features/auth/data/account_email_mirror_client.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_state.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class _MockUser extends Mock implements fb.User {}

class _FakeFirebaseAuth extends Fake implements fb.FirebaseAuth {
  _FakeFirebaseAuth(Stream<fb.User?> stream)
    : _stream = stream.asBroadcastStream();

  /// authUserObserver 와 AuthRefresh 가 같은 스트림을 구독하므로 broadcast.
  final Stream<fb.User?> _stream;

  @override
  Stream<fb.User?> authStateChanges() => _stream;

  @override
  Stream<fb.User?> userChanges() => _stream;
}

/// mirror · reload 를 no-op 으로 대체한 TermsNotifier (본 테스트 범위 밖).
class _NoopTermsNotifier extends TermsNotifier {
  @override
  TermsState build() => TermsState(
    acceptance: TermsAcceptance(
      version: TermsNotifier.currentVersion,
      service: true,
      privacy: true,
      marketing: false,
      acceptedAt: DateTime.utc(2026, 10),
    ),
  );

  @override
  Future<Result<void>> mirrorToFirestore({
    required String uid,
    bool force = false,
  }) async => const Result.success(null);

  @override
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {}
}

/// `mirror()` 호출 횟수와 순서를 기록하는 가짜 client.
class _RecordingMirrorClient extends Fake implements AccountEmailMirrorClient {
  int calls = 0;

  /// mirror · token 갱신 호출 순서 (token 갱신은 [makeUser] 가 기록한다).
  final List<String> events = <String>[];

  @override
  Future<void> mirror() async {
    calls++;
    events.add('mirror');
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  fb.User makeUser({
    required String uid,
    required bool isAnonymous,
    bool emailVerified = false,
    List<String>? events,
    bool isTokenRefreshFailing = false,
  }) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
    when(() => user.email).thenReturn(null);
    when(() => user.emailVerified).thenReturn(emailVerified);
    when(() => user.getIdToken(true)).thenAnswer((_) async {
      events?.add('refreshToken');
      if (isTokenRefreshFailing) {
        throw fb.FirebaseAuthException(code: 'network-request-failed');
      }
      return 'fresh-token';
    });
    return user;
  }

  ({
    StreamController<fb.User?> controller,
    _RecordingMirrorClient client,
    ProviderContainer container,
  })
  setUpObserver({bool isFirebaseInitialized = true}) {
    final controller = StreamController<fb.User?>();
    // 미초기화 케이스는 observer 가 구독하지 않아 close() future 가 끝나지
    // 않는다 — 기다리지 않고 닫는다.
    addTearDown(() => unawaited(controller.close()));
    final analytics = _MockFirebaseAnalytics();
    when(
      () => analytics.setUserProperty(
        name: any(named: 'name'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => analytics.setUserId(id: any(named: 'id')),
    ).thenAnswer((_) async {});
    final crashlytics = _MockFirebaseCrashlytics();
    when(() => crashlytics.setUserIdentifier(any())).thenAnswer((_) async {});
    when(
      () => crashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
    final client = _RecordingMirrorClient();
    final container = ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isFirebaseInitialized),
        firebaseAuthProvider.overrideWithValue(
          _FakeFirebaseAuth(controller.stream),
        ),
        analyticsServiceProvider.overrideWith(
          (ref) => AnalyticsService(analytics, isEnabled: true),
        ),
        crashlyticsServiceProvider.overrideWith(
          (ref) => CrashlyticsService(crashlytics, isEnabled: true),
        ),
        termsProvider.overrideWith(_NoopTermsNotifier.new),
        accountEmailMirrorClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(authUserObserverProvider, (_, _) {});
    addTearDown(sub.close);
    return (controller: controller, client: client, container: container);
  }

  Future<void> emit(
    StreamController<fb.User?> controller,
    fb.User? user,
  ) async {
    controller.add(user);
    await pumpEventQueue();
  }

  group('Phase 17 email mirror (T-17-MIRROR)', () {
    test('T-17-MIRROR-03a: 정식 사용자 첫 emit → mirror 1회', () async {
      final h = setUpObserver();

      await emit(h.controller, makeUser(uid: 'reg-1', isAnonymous: false));

      expect(h.client.calls, 1);
    });

    test('T-17-MIRROR-03b: 같은 uid 정식 재emit → 추가 호출 0', () async {
      final h = setUpObserver();

      await emit(h.controller, makeUser(uid: 'reg-1', isAnonymous: false));
      await emit(h.controller, makeUser(uid: 'reg-1', isAnonymous: false));
      await emit(h.controller, makeUser(uid: 'reg-1', isAnonymous: false));

      expect(h.client.calls, 1);
    });

    test('T-17-MIRROR-03c: 익명 첫 emit → 호출 0', () async {
      final h = setUpObserver();

      await emit(h.controller, makeUser(uid: 'anon-1', isAnonymous: true));
      await emit(h.controller, makeUser(uid: 'anon-1', isAnonymous: true));

      expect(h.client.calls, 0);
    });

    test('T-17-MIRROR-03d: 익명 → 정식 전이(같은 uid · link 승격) → 1회', () async {
      final h = setUpObserver();

      await emit(h.controller, makeUser(uid: 'u-1', isAnonymous: true));
      expect(h.client.calls, 0);
      await emit(h.controller, makeUser(uid: 'u-1', isAnonymous: false));

      expect(h.client.calls, 1);
    });

    test('T-17-MIRROR-03e: 다른 uid 정식 사용자 → 새 세션마다 1회', () async {
      final h = setUpObserver();

      await emit(h.controller, makeUser(uid: 'reg-1', isAnonymous: false));
      await emit(h.controller, null);
      await emit(h.controller, makeUser(uid: 'reg-2', isAnonymous: false));

      expect(h.client.calls, 2);
    });

    test('T-17-MIRROR-03g: 같은 uid 의 emailVerified false → true → ID token '
        '강제 갱신 뒤 mirror 1회 더 (리뷰 IN-15)', () async {
      final h = setUpObserver();
      final events = h.client.events;

      await emit(
        h.controller,
        makeUser(uid: 'reg-1', isAnonymous: false, events: events),
      );
      await emit(
        h.controller,
        makeUser(uid: 'reg-1', isAnonymous: false, events: events),
      );
      expect(events, ['mirror']);

      await emit(
        h.controller,
        makeUser(
          uid: 'reg-1',
          isAnonymous: false,
          emailVerified: true,
          events: events,
        ),
      );
      // token 갱신이 mirror 보다 먼저다 — 서버는 token 클레임을 읽는다.
      expect(events, ['mirror', 'refreshToken', 'mirror']);

      // 이미 true 인 재emit(token 갱신이 일으킨 emit 포함)은 추가 0.
      await emit(
        h.controller,
        makeUser(
          uid: 'reg-1',
          isAnonymous: false,
          emailVerified: true,
          events: events,
        ),
      );
      expect(events, ['mirror', 'refreshToken', 'mirror']);
    });

    test('T-17-MIRROR-03h: 첫 emit 이 이미 인증됨 → 세션 시작 1회뿐 · token '
        '강제 갱신 0', () async {
      final h = setUpObserver();
      final events = h.client.events;

      await emit(
        h.controller,
        makeUser(
          uid: 'reg-1',
          isAnonymous: false,
          emailVerified: true,
          events: events,
        ),
      );

      expect(events, ['mirror']);
    });

    test('T-17-MIRROR-03i: token 강제 갱신 실패 → 그 전이의 mirror 생략 · '
        'observer 는 계속', () async {
      final h = setUpObserver();
      final events = h.client.events;

      await emit(
        h.controller,
        makeUser(uid: 'reg-1', isAnonymous: false, events: events),
      );
      await emit(
        h.controller,
        makeUser(
          uid: 'reg-1',
          isAnonymous: false,
          emailVerified: true,
          events: events,
          isTokenRefreshFailing: true,
        ),
      );
      expect(events, ['mirror', 'refreshToken']);

      // 다음 세션(다른 uid)은 그대로 mirror 한다.
      await emit(
        h.controller,
        makeUser(uid: 'reg-2', isAnonymous: false, events: events),
      );
      expect(events, ['mirror', 'refreshToken', 'mirror']);
    });

    test('T-17-MIRROR-03f: Firebase 미초기화 → 호출 0', () async {
      final h = setUpObserver(isFirebaseInitialized: false);

      await emit(h.controller, makeUser(uid: 'reg-1', isAnonymous: false));

      expect(h.client.calls, 0);
    });
  });
}
