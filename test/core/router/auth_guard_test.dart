import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart'
    show appRouterProvider;
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/core/router/auth_refresh.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_state.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

import '../../helpers/route_tree.dart' show readMatchedLocations;
import '../../helpers/router_harness.dart' show buildRouteTableContainer;

class _MockGoRouterState extends Mock implements GoRouterState {}

class _MockUser extends Mock implements fb.User {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

/// Issue #10 Plan 10-14 GC-04 테스트용 — 영원히 loading 상태를 유지하여
/// AsyncLoading 판단 유보 분기를 재현한다. Task 3 (GC-04-E) 에서 사용.
class _LoadingOnboardingNotifier extends OnboardingNotifier {
  @override
  FutureOr<bool> build() async {
    // 의도적으로 never-resolving future 를 반환하여 AsyncLoading 유지.
    final completer = Completer<bool>();
    return completer.future;
  }
}

/// onboarding/terms Provider 의 build() 가 SharedPreferences 비동기 로드를
/// 시도하므로, 테스트에서는 async stub Notifier 로 교체하여 race 없이 검증한다.
///
/// Issue #10 Plan 10-14: [OnboardingNotifier.build] 가 `FutureOr<bool> async`
/// 로 전환되어 stub 도 동일 시그니처를 준수한다. [_callAuthRedirect] 가
/// `await container.read(onboardingProvider.future)` 로 settle 대기 후
/// resolveAuthRedirect 를 호출하도록 수정됨.
class _StubOnboardingNotifier extends OnboardingNotifier {
  _StubOnboardingNotifier(this._initial);
  final bool _initial;

  @override
  FutureOr<bool> build() async => _initial;
}

/// 정식 user 분기 (5) 시나리오 전용 terms stub.
///
/// Issue #7 (Plan 10-11): 기존 테스트(Test 1~13 / Issue #6 Test A~D /
/// Issue #4 Test A~E) 가 resolveAuthRedirect stale 가드를 통과하도록 기본값을
/// `regularUser` / `anonymousUser` 의 기본 uid 두 후보를 모두 수용하는
/// 방식으로 제공한다. 본 stub 은 분기 (5) 의 stale 가드를 **우회**하는
/// 방향으로만 동작해야 하므로, 'reg-uid' / 'anon-uid' 둘 중 현재 평가
/// 경로와 일치하는 값을 반환하면 되지만 실제로는 resolveAuthRedirect 가 uid 와
/// lastReloadedUid 를 equality 비교하는 단일 분기뿐이므로, 본 테스트들은
/// regularUser 기본 uid 인 'reg-uid' 를 반환해 stale 가드가 항상
/// false(비-stale) 로 평가되도록 한다.
///
/// **Phase 10.2 D-C2 갱신 (iter 2 WR-03):** 위 정당화 마지막 줄
/// ("익명 사용자 경로는 분기 (3) 에서 처리되어 stale 가드를 타지 않으므로
/// uid 불일치가 무해하다") 은 **더 이상 사실이 아니다.** Phase 10.2 D-C2
/// 가 분기 (3) (익명 user 경로) 에도 stale guard 를 도입했기 때문에,
/// 익명 user 시나리오에 본 stub 을 그대로 사용하면 'reg-uid' vs 익명 uid
/// (예: 'anon-uid') mismatch 로 stale guard 가 우연히 발동/우회될 수 있어
/// CR-01 (iter 1) 회귀의 root cause 가 된다. **익명 user 시나리오는 항상
/// [_StubTermsNotifierWithUid] (line 94-104) 의 named `reloadedUid: 'anon-uid'`
/// 를 사용하거나, 명시적 `termsAcceptance: acceptedTerms()` 를 함께 지정하여
/// stale guard 진입 자체를 우회시켜야 한다.** 본 stub (`_StubTermsNotifier`)
/// 의 하드코딩 'reg-uid' 는 정식 user 분기 (5) 시나리오 전용으로만 신규
/// 테스트에 채택할 것.
///
/// **quick 260920-b28:** getter override 대신 불변 state 를 그대로 만든다 —
/// `TermsNotifier` 는 public getter 를 노출하지 않는다.
class _StubTermsNotifier extends TermsNotifier {
  _StubTermsNotifier(this._initial);
  final TermsAcceptance? _initial;

  @override
  TermsState build() =>
      TermsState(acceptance: _initial, lastReloadedUid: 'reg-uid');
}

/// Phase 9.1 D-02-B (Plan 09.1-04) — `socialLinkInProgressProvider` override 용
/// stub. `_initial` 값을 `build()` 에서 직접 반환하여 resolveAuthRedirect 가
/// `ref.read(socialLinkInProgressProvider)` 시 진행 중 여부를 결정한다.
/// 기존 `_StubOnboardingNotifier` / `_StubTermsNotifier` stub 패턴 mirror.
class _StubSocialLinkInProgress extends SocialLinkInProgress {
  _StubSocialLinkInProgress(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;
}

/// Issue #7 (Plan 10-11) stale 가드 테스트용 확장 stub.
///
/// 기존 [_StubTermsNotifier] 는 `lastReloadedUid` 를 'reg-uid' 로 고정한다.
/// 본 서브클래스는 `reloadedUid` 를 주입 가능한 값으로 대체하여
/// resolveAuthRedirect 분기 (5) 가 stale 여부를 판단하는 시나리오를 재현한다.
///
/// 기존 테스트 17~22건은 이 확장 stub 을 사용하지 않으므로 무수정 회귀.
class _StubTermsNotifierWithUid extends TermsNotifier {
  _StubTermsNotifierWithUid({required this.initial, required this.reloadedUid});
  final TermsAcceptance? initial;
  final String? reloadedUid;

  @override
  TermsState build() =>
      TermsState(acceptance: initial, lastReloadedUid: reloadedUid);
}

/// resolveAuthRedirect 호출 헬퍼 (Phase 9.1 IN-03 — DRY 추출).
///
/// 모든 `resolveAuthRedirect 분기` group 에서 공통으로 사용한다. resolveAuthRedirect 는
/// `Ref` 를 첫 번째 파라미터로 받으므로, ProviderContainer 에서 Ref 를 얻기
/// 위해 임시 Provider 안에서 호출한다.
///
/// [awaitSettle]=true (기본) 면 `onboardingProvider.future` 를 [timeout]
/// 내에 await — 정상 settle 경로 (Issue #10 Plan 10-14: AsyncNotifier 전환에
/// 맞춰 settle 대기 후 resolveAuthRedirect 호출). [awaitSettle]=false 면 GC-04-E
/// (AsyncLoading 영구 유지) 처럼 timeout 우회 + loading 상태로 진입을 강제한다.
///
/// [timeout] 기본 50ms 는 GC-04 fail-safe 분기 테스트에서 검증된 값이며,
/// 일반 group (timeout 옵션 미사용) 에서는 stub Notifier 가 즉시 settle 하므로
/// 도달 가능하지 않다 — 안전한 상한.
Future<String?> _callAuthRedirect(
  ProviderContainer container,
  GoRouterState state, {
  bool awaitSettle = true,
  Duration timeout = const Duration(milliseconds: 50),
}) async {
  if (awaitSettle) {
    try {
      await container.read(onboardingProvider.future).timeout(timeout);
    } on TimeoutException {
      // 의도적으로 loading 유지 (예: GC-04-E) — 또는 stub 이 즉시 settle 하지
      // 않는 비정상 상태. 어느 쪽이든 resolveAuthRedirect 진입은 진행한다.
    }
  }
  late FutureOr<String?> result;
  final testProvider = Provider<Object?>((ref) {
    result = resolveAuthRedirect(ref, state);
    return null;
  });
  container.read(testProvider);
  return await result;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registerFallbackValue(StackTrace.empty);
  });

  late _MockGoRouterState mockState;

  setUp(() {
    mockState = _MockGoRouterState();
    // 260916-p8d: guard 가 재인증 표시 판정을 위해 `state.uri` 를 읽는다.
    // mocktail Mock 은 stub 하지 않은 non-nullable `uri` 에서 TypeError 를
    // 내므로, 각 test 가 나중에 stub 한 matchedLocation 을 따라가는 기본값을 둔다.
    when(
      () => mockState.uri,
    ).thenAnswer((_) => Uri(path: mockState.matchedLocation));
  });

  /// 실제 GoRouterState 처럼 matchedLocation 은 path 만, uri 는 query 포함.
  void stubLocation(String location) {
    final uri = Uri.parse(location);
    when(() => mockState.matchedLocation).thenReturn(uri.path);
    when(() => mockState.uri).thenReturn(uri);
  }

  /// 기본 crashlytics mock — setCustomKey / recordError / setUserId 등
  /// 모든 메서드를 noop 으로 stub 하여 fail-safe 분기의 observability
  /// 호출 경로에서 throw 하지 않도록 한다 (Plan 10-14).
  _MockCrashlytics defaultCrashlytics() {
    final mock = _MockCrashlytics();
    when(
      () => mock.setCustomKey(any(), any<Object>()),
    ).thenAnswer((_) async {});
    when(
      () => mock.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
    when(() => mock.setUserId(any())).thenAnswer((_) async {});
    return mock;
  }

  /// 인증 상태 + onboarding/terms 상태를 시뮬레이션하는 컨테이너 빌더.
  ///
  /// [user] 가 null 이면 미인증, non-null 이면 인증 (mock isAnonymous 활용).
  /// [onboardingSeen] 기본 false (첫 실행 가정).
  /// [termsAcceptance] null 이면 약관 미동의.
  ///
  /// Issue #10 Plan 10-14: [crashlytics] (optional) / [onboardingOverride]
  /// (optional) 파라미터 추가 — GC-04 fail-safe 분기의 Crashlytics
  /// observability 주입 + AsyncLoading 유지 stub 주입을 지원한다. 기본
  /// crashlytics 는 [defaultCrashlytics] (모든 메서드 noop stub) — 기존
  /// 22+ 테스트가 fail-safe 분기에 의도치 않게 진입해도 throw 하지 않는다.
  ProviderContainer makeContainer({
    required bool isInitialized,
    fb.User? user,
    bool onboardingSeen = false,
    TermsAcceptance? termsAcceptance,
    CrashlyticsService? crashlytics,
    OnboardingNotifier Function()? onboardingNotifierFactory,
  }) {
    final mockAuth = _MockFirebaseAuth();
    when(() => mockAuth.currentUser).thenReturn(user);
    return ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isInitialized),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        onboardingProvider.overrideWith(
          onboardingNotifierFactory ??
              () => _StubOnboardingNotifier(onboardingSeen),
        ),
        termsProvider.overrideWith(() => _StubTermsNotifier(termsAcceptance)),
        crashlyticsServiceProvider.overrideWithValue(
          crashlytics ?? defaultCrashlytics(),
        ),
      ],
    );
  }

  TermsAcceptance acceptedTerms() => TermsAcceptance(
    version: TermsNotifier.currentVersion,
    service: true,
    privacy: true,
    marketing: false,
    acceptedAt: DateTime.utc(2026, 4, 14),
  );

  /// 정식(비익명) 사용자 mock.
  ///
  /// [email] 기본값이 non-empty 인 이유 (코드 리뷰 05 CR-02): resolveAuthRedirect 의
  /// 이메일 검증 게이트(분기 4)는 "검증 가능한 email 보유" 를 전제로 하므로,
  /// 일반 정식 사용자 시나리오는 email 을 반드시 갖고 있어야 한다. email 이
  /// 없는 정식 사용자(Facebook 권한 거부 등)는 `email: ''` 로 명시 지정한다.
  fb.User regularUser({
    String uid = 'reg-uid',
    bool emailVerified = true,
    String email = 'reg@example.com',
  }) {
    final mockUser = _MockUser();
    when(() => mockUser.uid).thenReturn(uid);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.emailVerified).thenReturn(emailVerified);
    when(() => mockUser.email).thenReturn(email);
    return mockUser;
  }

  fb.User anonymousUser({String uid = 'anon-uid'}) {
    final mockUser = _MockUser();
    when(() => mockUser.uid).thenReturn(uid);
    when(() => mockUser.isAnonymous).thenReturn(true);
    when(() => mockUser.emailVerified).thenReturn(false);
    when(() => mockUser.email).thenReturn(null);
    return mockUser;
  }

  group(
    'resolveAuthRedirect (Phase 10 D-14 / BLOCKER #3 / BLOCKER #7 / WARNING #19)',
    () {
      // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).
      test('Test 1: Firebase 미초기화 시 null', () async {
        final container = makeContainer(isInitialized: false);
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, isNull);
      });

      test(
        'Test 2: 미인증 + onboardingSeen=false + home -> /onboarding (D-14)',
        () async {
          final container = makeContainer(isInitialized: true);
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, AppRoutes.onboarding);
        },
      );

      test('Test 3: 미인증 + onboardingSeen=true + home -> /splash '
          '(Issue #10 Plan 10-14 GC-04 fail-safe — 기존 null 기대 갱신)', () async {
        // Plan 10-14 GC-04 fail-safe 도입 전에는 Splash 가 signInAnonymously
        // 를 책임지고 resolveAuthRedirect 는 null 을 반환했다. Plan 10-14 는
        // race 가 재발해도 silent 미인증 Home 랜딩을 차단하기 위해 이
        // 조합에서 /splash 로 복귀시킨다 (2차 방어벽).
        final container = makeContainer(
          isInitialized: true,
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, AppRoutes.splash);
      });

      test(
        'Test 4: 인증(정식) + emailVerified=false + home -> /verify-email',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: regularUser(emailVerified: false),
          );
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, AppRoutes.verifyEmail);
        },
      );

      test('Test 5: 익명 사용자 + /login -> null (unauth 허용, 승격 가능)', () async {
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, isNull);
      });

      test('Test 5-1 (Phase 16.1 D-01): 익명 사용자 + /login/email -> null '
          '(unauth 화이트리스트 1줄 추가로 통과)', () async {
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.emailLogin);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason: '/login/email 은 완전 일치 화이트리스트 원소이므로 익명 사용자가 머문다',
        );
      });

      test(
        'Test 6: 인증 + emailVerified + termsAccepted + /login -> /home',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: regularUser(),
            termsAcceptance: acceptedTerms(),
          );
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, AppRoutes.home);
        },
      );

      test(
        'Test 7 (BLOCKER #3 / #7): 인증 + emailVerified + termsAccepted=null + '
        '/home -> /onboarding (이메일 바이패스 차단)',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: regularUser(),
            // termsAcceptance: null (약관 미동의 — 이메일 직접 가입 후 Home 시도)
          );
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

          final result = await _callAuthRedirect(container, mockState);
          expect(
            result,
            AppRoutes.onboarding,
            reason:
                'BLOCKER #3 D-14 emailVerified+!termsAccepted -> /onboarding',
          );
        },
      );

      test(
        'Test 8: 완료된 사용자(termsAccepted) + /onboarding -> /home (재진입 차단)',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: regularUser(),
            termsAcceptance: acceptedTerms(),
          );
          addTearDown(container.dispose);
          when(
            () => mockState.matchedLocation,
          ).thenReturn(AppRoutes.onboarding);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, AppRoutes.home);
        },
      );

      test('Test 9 (WARNING #19 / AUTH-13 자동 검증): 인증 + emailVerified + '
          'termsAccepted + matchedLocation=/ -> null (Home 랜딩 완료)', () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason: 'AUTH-13 자동 검증 — 인증 완료 사용자가 Home 랜딩 시 redirect 없음',
        );
      });

      test(
        'Test 10: 미인증 + onboardingSeen=false + /terms/service -> null (공개 경로)',
        () async {
          final container = makeContainer(isInitialized: true);
          addTearDown(container.dispose);
          when(
            () => mockState.matchedLocation,
          ).thenReturn(AppRoutes.termsService);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, isNull);
        },
      );

      test(
        'Test 11: 미인증 + onboardingSeen=true + /signup -> null (정식 가입 진입)',
        () async {
          // /signup 은 unauth 화이트리스트 — 미인증이어도 접근 가능.
          final container = makeContainer(
            isInitialized: true,
            onboardingSeen: true,
          );
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.signup);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, isNull);
        },
      );

      test('Test 12: 익명 사용자 + /verify-email -> /home (정식 사용자 전용 차단)', () async {
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.verifyEmail);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, AppRoutes.home);
      });

      // Phase 17.1 D-07 — 게스트에게는 계정 화면이 없다. 온보딩 · 약관을 마친
      // 게스트(D-C1 게이트 통과 상태)로 두어 결과가 새 분기에서만 나오게 한다.
      test(
        'T-171-ROUTER-04: 익명 + /settings/account -> /settings (Phase 17.1 D-07)',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: anonymousUser(),
            onboardingSeen: true,
            termsAcceptance: acceptedTerms(),
          );
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.account);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, AppRoutes.settings);
        },
      );

      test(
        'T-171-ROUTER-05: 정식 + /settings/account -> null (대조군 · 계정 화면 허용)',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: regularUser(),
            onboardingSeen: true,
            termsAcceptance: acceptedTerms(),
          );
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.account);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, isNull);
        },
      );

      test(
        'T-171-ROUTER-06: 익명 + /settings/developer -> null (대조군 · D-15 데모 게스트 허용)',
        () async {
          final container = makeContainer(
            isInitialized: true,
            user: anonymousUser(),
            onboardingSeen: true,
            termsAcceptance: acceptedTerms(),
          );
          addTearDown(container.dispose);
          when(
            () => mockState.matchedLocation,
          ).thenReturn(AppRoutes.developerDemo);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, isNull);
        },
      );

      test('T-172-GUARD-01: 익명 + 알림 계정 경로 → /settings → production 트리 결과 스택 '
          '[/, /settings] (I8 ④ · 대조군 정식 3장)', () async {
        // production route 표 — guard 결과 경로가 중첩 트리에서 어떤 스택이
        // 되는지 본다 (Firebase 미초기화 · 빈 인증 스트림 · 위젯 없음).
        final tableContainer = buildRouteTableContainer();
        addTearDown(tableContainer.dispose);
        final RouteConfiguration configuration = tableContainer
            .read(appRouterProvider)
            .configuration;

        /// [location] 을 열었을 때의 스택(match 의 matchedLocation 목록).
        List<String> readStackAt(String location) =>
            readMatchedLocations(configuration.findMatch(Uri.parse(location)));

        // 익명 — guard 가 계정 경로를 설정으로 돌린다 (17.1 D-07).
        final anonymousContainer = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
          onboardingSeen: true,
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(anonymousContainer.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.account);
        final String? anonymousResult = await _callAuthRedirect(
          anonymousContainer,
          mockState,
        );
        expect(
          anonymousResult,
          AppRoutes.settings,
          reason: '게스트에게 알림 경로로 계정 정보 화면을 보이지 않는다 (17.1 D-07)',
        );
        expect(readStackAt(anonymousResult!), <String>[
          '/',
          AppRoutes.settings,
        ], reason: '게스트 결과 스택 = 홈 · 설정 2장 (I8 ④ 위젯 수준 대체 · D-06)');

        // 대조군 — 정식 사용자는 계정 경로 그대로 3장.
        final regularContainer = makeContainer(
          isInitialized: true,
          user: regularUser(),
          onboardingSeen: true,
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(regularContainer.dispose);
        final String? regularResult = await _callAuthRedirect(
          regularContainer,
          mockState,
        );
        expect(regularResult, isNull, reason: '정식 사용자는 계정 화면 허용');
        expect(readStackAt(AppRoutes.account), <String>[
          '/',
          AppRoutes.settings,
          AppRoutes.account,
        ], reason: '정식 결과 스택 = 홈 · 설정 · 계정 3장');
      });

      test(
        'Test 13: 미인증 + onboardingSeen=false + /splash -> null (스플래시 진입 허용)',
        () async {
          // 앱 시작 직후 splash 경로에서 redirect 발동을 막는다.
          final container = makeContainer(isInitialized: true);
          addTearDown(container.dispose);
          when(() => mockState.matchedLocation).thenReturn(AppRoutes.splash);

          final result = await _callAuthRedirect(container, mockState);
          expect(result, isNull);
        },
      );
    },
  );

  group('분기 (6.4)/(6.5) 조건 동치성 — 코드 리뷰 05 WR-07 회귀 가드', () {
    // 두 분기는 동일한 조건 묶음(`isUnprotectedLanding`)을 공유하며
    // socialLinkInProgress 여부로만 갈린다. DRY 추출 전에는 5개 항의 논리곱이
    // 두 곳에 그대로 중복되어 한쪽만 수정되는 drift 위험이 있었다.

    /// [socialLinkInProgress] 값으로 [location] 을 평가한다.
    Future<String?> evaluate({
      required String location,
      required bool socialLinkInProgress,
      required bool onboardingSeen,
      fb.User? user,
    }) async {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(user);
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          onboardingProvider.overrideWith(
            () => _StubOnboardingNotifier(onboardingSeen),
          ),
          termsProvider.overrideWith(() => _StubTermsNotifier(null)),
          crashlyticsServiceProvider.overrideWithValue(defaultCrashlytics()),
          socialLinkInProgressProvider.overrideWith(
            () => _StubSocialLinkInProgress(socialLinkInProgress),
          ),
        ],
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(location);
      return _callAuthRedirect(container, mockState);
    }

    test('WR-07: 두 분기는 정확히 같은 전제에서만 발동한다 (전제 매트릭스)', () async {
      // (조건, 발동 기대) — 발동 시 6.4 는 null, 6.5 는 /splash 를 반환한다.
      final cases = <({String location, bool onboardingSeen, bool trips})>[
        // 보호되지 않은 랜딩: 두 분기 모두 발동.
        (location: AppRoutes.home, onboardingSeen: true, trips: true),
        (location: AppRoutes.settings, onboardingSeen: true, trips: true),
        // splash 는 자기 복귀 무한루프 방지로 제외.
        (location: AppRoutes.splash, onboardingSeen: true, trips: false),
        // 공개 경로(진입 화면 + 상시 문서)는 제외.
        (location: AppRoutes.login, onboardingSeen: true, trips: false),
        (location: AppRoutes.termsService, onboardingSeen: true, trips: false),
        // onboardingSeen=false 는 분기 (2) 가 먼저 가로챈다.
        (location: AppRoutes.home, onboardingSeen: false, trips: false),
      ];

      for (final c in cases) {
        final withLink = await evaluate(
          location: c.location,
          socialLinkInProgress: true,
          onboardingSeen: c.onboardingSeen,
        );
        final withoutLink = await evaluate(
          location: c.location,
          socialLinkInProgress: false,
          onboardingSeen: c.onboardingSeen,
        );

        if (c.trips) {
          expect(
            withLink,
            isNull,
            reason: '${c.location}: 분기 (6.4) 는 보류(null) 해야 한다',
          );
          expect(
            withoutLink,
            AppRoutes.splash,
            reason: '${c.location}: 분기 (6.5) 는 /splash 로 복귀해야 한다',
          );
        } else {
          expect(
            withLink,
            withoutLink,
            reason:
                '${c.location} (onboardingSeen=${c.onboardingSeen}): 두 분기가 '
                '모두 미발동이면 socialLinkInProgress 는 결과에 영향을 주지 않아야 한다',
          );
          expect(
            withoutLink,
            isNot(AppRoutes.splash),
            reason: '${c.location}: fail-safe 가 발동해서는 안 되는 전제다',
          );
        }
      }
    });

    test('WR-07: 인증된 사용자는 두 분기 모두 발동하지 않는다 (!isAuthenticated 항 보존)', () async {
      final result = await evaluate(
        location: AppRoutes.home,
        socialLinkInProgress: true,
        onboardingSeen: true,
        user: regularUser(),
      );
      expect(
        result,
        AppRoutes.onboarding,
        reason: '정식 사용자는 약관 미동의로 분기 (5) 에서 처리되어야 한다',
      );
    });
  });

  group('authRefreshProvider 생명주기 — 코드 리뷰 05 WR-04 회귀 가드', () {
    /// 초기화 성공 경로의 컨테이너를 만들고 provider 를 초기화한다.
    ///
    /// 옛 구조는 초기화 실패 분기에서만 `ref.onDispose` 를 빠뜨려
    /// ChangeNotifier 가 누수됐다. 새 구조는 "어느 스트림을 구독할지" 만
    /// 분기하고 구독 · 정리는 한 경로로 합쳤으므로, 두 경로 모두 같은 파기
    /// 계약을 만족해야 한다.
    ProviderContainer makeRefreshContainer({
      required bool isInitialized,
      required StreamController<fb.User?> controller,
    }) {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.userChanges()).thenAnswer((_) => controller.stream);
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(isInitialized),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      // 구독이 실제로 열리도록 provider 를 초기화한다.
      expect(container.read(authRefreshProvider), initialAuthRefreshState);
      return container;
    }

    test('WR-04: Firebase 미초기화 경로에서도 컨테이너 파기가 예외 없이 끝난다', () {
      // 미초기화 경로는 빈 스트림을 구독하므로 userChanges 를 아예 만지지
      // 않는다 — StreamController 를 쥐어 줘도 붙잡을 것이 없다.
      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.userChanges(),
      ).thenAnswer((_) => const Stream<fb.User?>.empty());
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      expect(container.read(authRefreshProvider), initialAuthRefreshState);
      verifyNever(() => mockAuth.userChanges());

      expect(container.dispose, returnsNormally);

      expect(
        () => container.read(authRefreshProvider),
        throwsStateError,
        reason: '파기된 컨테이너는 provider 를 다시 읽을 수 없다 — notifier 가 살아 있지 않다',
      );
    });

    test('WR-04: 초기화 성공 경로에서 컨테이너 파기 시 userChanges 구독이 취소된다', () async {
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final container = makeRefreshContainer(
        isInitialized: true,
        controller: controller,
      );
      expect(
        controller.hasListener,
        isTrue,
        reason: '구독이 실제로 열려 있어야 취소 단언이 유효하다',
      );

      expect(container.dispose, returnsNormally);

      expect(
        controller.hasListener,
        isFalse,
        reason:
            'ref.onDispose 가 구독을 취소하지 않으면 파기된 notifier 가 계속 emit 을 '
            '받아 state 대입에서 throw 한다 (zone uncaught error)',
      );
      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('AuthRefresh distinct 가드 — Phase 9 UAT Gap 2', () {
    // Phase 9 UAT Gap 2: userChanges() 는 ID 토큰 갱신(약 1시간 주기 + 각종
    // reload)마다 인증 스냅샷이 전혀 바뀌지 않은 emit 을 흘린다. 가드가 없으면
    // GoRouter refreshListenable 이 매번 깨어나 동일한 입력으로
    // resolveAuthRedirect 를 재평가한다 (실 단말 로그 flood).
    //
    // 아래 8건은 "억제해야 할 것" 과 "절대 삼키면 안 되는 것" 을 동시에 고정한다.

    /// 네 필드(uid / email / emailVerified / isAnonymous)를 모두 명시 stub 한
    /// 사용자 mock 을 만든다.
    ///
    /// 기존 `regularUser` / `anonymousUser` 헬퍼는 두 필드 이상이 동시에
    /// 달라지므로 "단일 필드만 다른 두 스냅샷" 델타를 만들 수 없다.
    fb.User snapshotUser({
      String uid = 'snap-uid',
      String? email = 'snap@example.com',
      bool emailVerified = false,
      bool isAnonymous = false,
    }) {
      final mockUser = _MockUser();
      when(() => mockUser.uid).thenReturn(uid);
      when(() => mockUser.email).thenReturn(email);
      when(() => mockUser.emailVerified).thenReturn(emailVerified);
      when(() => mockUser.isAnonymous).thenReturn(isAnonymous);
      return mockUser;
    }

    /// 스트림 컨트롤러 + authRefresh 구독 + 통지 카운터를 묶어 생성하고
    /// tearDown 까지 등록한다.
    ///
    /// 통지 횟수는 `container.listen(authRefreshProvider, …)` 가 센다 — 중복
    /// 흡수 책임이 손으로 짠 sentinel 이 아니라 Riverpod 의 기본
    /// `updateShouldNotify`(state `!=`) 로 옮겨졌기 때문에, 구독자가 실제로
    /// 몇 번 깨어나는지가 곧 계약이다.
    ({
      StreamController<fb.User?> controller,
      ProviderContainer container,
      int Function() count,
    })
    makeNotifier() {
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.userChanges()).thenAnswer((_) => controller.stream);
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);
      var notifyCount = 0;
      final sub = container.listen(
        authRefreshProvider,
        (_, _) => notifyCount++,
      );
      addTearDown(sub.close);
      return (
        controller: controller,
        container: container,
        count: () => notifyCount,
      );
    }

    /// 스트림 이벤트가 listener 까지 전달되도록 microtask 큐를 2회 펌프한다.
    Future<void> pump() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('G2-A: 동일 스냅샷의 서로 다른 인스턴스를 3회 emit 하면 1회만 통지한다', () async {
      final h = makeNotifier();

      // 인스턴스 identity 가 아니라 "값" 으로 비교됨을 증명하기 위해 매번
      // 새 mock 인스턴스를 만든다 (토큰 갱신 emit 재현).
      for (var i = 0; i < 3; i++) {
        h.controller.add(snapshotUser());
        await pump();
      }

      expect(
        h.count(),
        1,
        reason:
            '토큰 갱신처럼 (uid, email, emailVerified, isAnonymous) 가 모두 동일한 '
            'emit 은 GoRouter redirect 재평가를 유발하면 안 된다 (Gap 2 flood)',
      );
    });

    test('G2-B: 최초 emit 이 null 하나뿐이어도 통지한다', () async {
      final h = makeNotifier();

      h.controller.add(null);
      await pump();

      expect(
        h.count(),
        1,
        reason:
            'sentinel 회귀 가드 — "아직 한 번도 통지 안 함" 과 "직전 값이 null" 을 '
            '구분하지 못하면 앱 기동 직후 첫 redirect 평가가 통째로 죽는다',
      );
    });

    test(
      'G2-B2 (GAP2-FIRST-NULL): 초기 state 와 최초 null emit 결과가 값으로 다르다',
      () async {
        // 신규 구조 전용 가드 (quick 260920-b28). 통지 여부는 Riverpod 의
        // `updateShouldNotify`(state `!=`) 가 결정하므로, "아직 한 번도 emit
        // 안 함" 과 "최초 emit 이 null" 이 **같은 값**이면 G2-B 가 조용히
        // 죽는다. 옛 구조의 `_hasNotified` sentinel 을 대체하는 것이
        // AuthRefreshState.hasEmitted 임을 값 수준에서 못박는다.
        final h = makeNotifier();

        expect(
          h.container.read(authRefreshProvider),
          initialAuthRefreshState,
          reason: '구독 직후에는 아직 emit 이 없다',
        );

        h.controller.add(null);
        await pump();

        expect(
          h.container.read(authRefreshProvider),
          isNot(initialAuthRefreshState),
          reason:
              'hasEmitted 가 없으면 최초 null emit 이 초기값과 동일해져 통지가 삼켜지고 '
              '앱 기동 직후 첫 redirect 평가가 통째로 사라진다',
        );
        expect(h.container.read(authRefreshProvider).snapshot, isNull);
        expect(h.container.read(authRefreshProvider).hasEmitted, isTrue);
      },
    );

    test('G2-C: uid 만 다른 두 사용자를 순차 emit 하면 2회 통지한다', () async {
      final h = makeNotifier();

      h.controller.add(snapshotUser(uid: 'uid-a'));
      await pump();
      h.controller.add(snapshotUser(uid: 'uid-b'));
      await pump();

      expect(
        h.count(),
        2,
        reason: '계정 전환(uid 변경)은 resolveAuthRedirect 재평가를 반드시 유발해야 한다',
      );
    });

    test('G2-D: emailVerified 만 다른 두 사용자를 순차 emit 하면 2회 통지한다', () async {
      final h = makeNotifier();

      h.controller.add(snapshotUser(emailVerified: false));
      await pump();
      h.controller.add(snapshotUser(emailVerified: true));
      await pump();

      expect(
        h.count(),
        2,
        reason:
            '이메일 검증 완료는 resolveAuthRedirect 분기 (4) 의 /verify-email '
            '게이트를 해제하는 전이다',
      );
    });

    test('G2-E: isAnonymous 만 다른 두 사용자를 순차 emit 하면 2회 통지한다', () async {
      final h = makeNotifier();

      h.controller.add(snapshotUser(isAnonymous: true));
      await pump();
      h.controller.add(snapshotUser(isAnonymous: false));
      await pump();

      expect(
        h.count(),
        2,
        reason: '익명 → 정식 승격(credential linking)은 redirect 재평가를 유발해야 한다',
      );
    });

    test('G2-F: email 만 다른 두 사용자를 순차 emit 하면 2회 통지한다', () async {
      final h = makeNotifier();

      // email 없는 정식 사용자(Facebook email 권한 거부 등) → 이후 이메일 연결.
      h.controller.add(snapshotUser(email: null));
      await pump();
      h.controller.add(snapshotUser(email: 'linked@example.com'));
      await pump();

      expect(
        h.count(),
        2,
        reason:
            'resolveAuthRedirect 는 hasVerifiableEmail(currentUser.email) 로 '
            '분기 (4) 검증 게이트의 적용 여부를 판정한다. email 을 스냅샷에서 빼면 '
            'uid/emailVerified/isAnonymous 가 그대로인 이 전이가 통째로 삼켜져 '
            '/verify-email 게이트가 발동하지 않는다',
      );
    });

    test('G2-G: 가드가 트립된 뒤에도 triggerRedirect() 는 통지한다', () async {
      final h = makeNotifier();

      for (var i = 0; i < 3; i++) {
        h.controller.add(snapshotUser());
        await pump();
      }
      h.container.read(authRefreshProvider.notifier).triggerRedirect();

      expect(
        h.count(),
        2,
        reason:
            'emit 1회 + 강제 1회 — triggerRedirect() 는 reload() 후 emailVerified '
            '변경을 emit 하지 않는 FlutterFire Issue #8777 우회 경로이므로 distinct '
            '가드를 항상 우회해야 한다',
      );
    });

    test('G2-H: null → 사용자 → null → null 4회 emit 시 3회만 통지한다', () async {
      final h = makeNotifier();

      h.controller.add(null);
      await pump();
      h.controller.add(snapshotUser());
      await pump();
      h.controller.add(null);
      await pump();
      h.controller.add(null);
      await pump();

      expect(
        h.count(),
        3,
        reason:
            '로그아웃 후 반복되는 null 재emit 만 흡수되고, 최초 null · 로그인 · '
            '로그아웃 전이는 모두 통지되어야 한다',
      );
    });
  });

  group('상시 공개 문서 경로 — 코드 리뷰 05 WR-02 회귀 가드', () {
    // 하나의 Set 이 "미인증자가 들어와도 되는 경로" 와 "완료 사용자가 있으면
    // 안 되는 진입 화면" 두 의미로 과적재되어, 분기 (6) 이 완료 사용자를
    // /terms/* 에서 홈으로 튕겨냈다. 설정 화면에 약관 링크를 추가하는 순간
    // 조용히 죽는 잠복 회귀다.

    /// 정식 + emailVerified + 약관 동의 완료 사용자의 [location] 평가 결과.
    Future<String?> redirectForCompletedUser(String location) async {
      final container = makeContainer(
        isInitialized: true,
        user: regularUser(),
        onboardingSeen: true,
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(location);
      return _callAuthRedirect(container, mockState);
    }

    test('WR-02-A: 완료 사용자가 /terms/* 를 열람할 수 있다 (홈으로 튕기지 않음)', () async {
      expect(
        await redirectForCompletedUser(AppRoutes.termsService),
        isNull,
        reason: '이용약관은 인증 상태와 무관하게 상시 열람 가능해야 한다',
      );
      expect(
        await redirectForCompletedUser(AppRoutes.termsPrivacy),
        isNull,
        reason: '개인정보처리방침은 인증 상태와 무관하게 상시 열람 가능해야 한다',
      );
    });

    test('WR-02-B: 완료 사용자가 진입 화면에 오면 기존대로 /home 으로 되돌린다', () async {
      for (final location in <String>[
        AppRoutes.login,
        AppRoutes.emailLogin,
        AppRoutes.signup,
        AppRoutes.forgotPassword,
        AppRoutes.onboarding,
        AppRoutes.verifyEmail,
      ]) {
        expect(
          await redirectForCompletedUser(location),
          AppRoutes.home,
          reason: '$location 은 진입 화면이므로 완료 사용자 바운스 대상이다',
        );
      }
    });

    test('WR-02-C: 미인증 race guard 는 /terms/* 를 여전히 공개 경로로 취급한다 '
        '(isOnUnauthRoute 합집합 유지)', () async {
      // 분기 (6.5) fail-safe 는 미인증 + onboardingSeen=true + 비공개 경로에서
      // /splash 로 복귀시킨다. /terms/* 가 합집합에서 빠지면 약관 열람 중
      // 미인증 사용자가 splash 로 튕긴다.
      final container = makeContainer(
        isInitialized: true,
        onboardingSeen: true,
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.termsService);

      expect(await _callAuthRedirect(container, mockState), isNull);
    });
  });

  group('_unauthRoutes 적용 범위 계약 — 코드 리뷰 05 WR-01 문서 정합성 가드', () {
    // `_unauthRoutes` docstring 이 단언하는 "적용 범위" 를 실제 동작으로
    // 고정한다. 분기 (2) 는 `isOnUnauthRoute` 를 참조하지 않고 좁은 예외
    // 목록 (onboarding / terms/* / splash) 만 허용하므로, Set 의 원소여도
    // 온보딩 미시청 상태에서는 /onboarding 으로 이동한다.

    /// 미인증 + `onboardingSeen=false` 조합에서 [location] 평가 결과.
    Future<String?> redirectForFreshInstall(String location) async {
      final container = makeContainer(isInitialized: true);
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(location);
      return _callAuthRedirect(container, mockState);
    }

    test('WR-01-A: _unauthRoutes 원소여도 분기 (2) 는 /onboarding 으로 보낸다', () async {
      // /forgot-password 와 /login/email 은 _unauthRoutes 원소지만
      // 분기 (2) 의 예외 목록에는 없다.
      expect(
        await redirectForFreshInstall(AppRoutes.forgotPassword),
        AppRoutes.onboarding,
      );
      expect(
        await redirectForFreshInstall(AppRoutes.emailLogin),
        AppRoutes.onboarding,
      );
      expect(
        await redirectForFreshInstall(AppRoutes.login),
        AppRoutes.onboarding,
      );
    });

    test('WR-01-B: 분기 (2) 의 좁은 예외 목록만 온보딩 미시청 상태에서 머문다', () async {
      for (final location in <String>[
        AppRoutes.onboarding,
        AppRoutes.termsService,
        AppRoutes.termsPrivacy,
        AppRoutes.splash,
      ]) {
        expect(
          await redirectForFreshInstall(location),
          isNull,
          reason: '$location 은 분기 (2) 의 명시적 예외여야 한다',
        );
      }
    });
  });

  group(
    'resolveAuthRedirect 재인증 표시 예외 — R_EXTRA_G3_REAUTH_LOGIN_BOUNCE 회귀 가드 (260916-p8d)',
    () {
      // 실기기 스택 [홈 → 설정 → 홈]: 완료 사용자가 재인증을 위해 push 한
      // 로그인 화면이 분기 (6) 에서 홈으로 튕겼다. 재인증 표시가 있는 로그인
      // 흐름 4개 경로만 예외이며, 다른 경로와 게이트 (3)(4)(5) 는 그대로다.

      /// 정식 + emailVerified + 약관 동의 완료 사용자의 [location] 평가 결과.
      Future<String?> redirectForCompletedUser(String location) async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          onboardingSeen: true,
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        stubLocation(location);
        return _callAuthRedirect(container, mockState);
      }

      test('RB-1: 완료 사용자의 재인증 표시 /login 은 튕기지 않는다', () async {
        expect(
          await redirectForCompletedUser(
            AppRoutes.buildReauthLocation(AppRoutes.login),
          ),
          isNull,
          reason: '재인증 목적 push 로 연 로그인 화면은 스택 맨 위에 남아야 한다',
        );
      });

      test('RB-2: 이메일 로그인 · 가입 · 비밀번호 찾기의 재인증 표시도 튕기지 않는다', () async {
        for (final path in <String>[
          AppRoutes.emailLogin,
          AppRoutes.signup,
          AppRoutes.forgotPassword,
        ]) {
          expect(
            await redirectForCompletedUser(AppRoutes.buildReauthLocation(path)),
            isNull,
            reason: '$path 는 재인증 흐름에서 이어 push 되는 로그인 흐름 경로다',
          );
        }
      });

      test('RB-3: 표시 없는 /login 은 기존대로 홈으로 되돌린다', () async {
        expect(
          await redirectForCompletedUser(AppRoutes.login),
          AppRoutes.home,
          reason: 'go 진입 튕김 (Phase 10 D-18 invariant) 은 유지되어야 한다',
        );
      });

      test('RB-4: /onboarding 에 표시가 붙어도 홈으로 되돌린다', () async {
        expect(
          await redirectForCompletedUser(
            AppRoutes.buildReauthLocation(AppRoutes.onboarding),
          ),
          AppRoutes.home,
          reason: '재인증 예외는 로그인 흐름 4개 경로에만 적용된다',
        );
      });

      test('RB-5: /verify-email 에 표시가 붙어도 홈으로 되돌린다', () async {
        expect(
          await redirectForCompletedUser(
            AppRoutes.buildReauthLocation(AppRoutes.verifyEmail),
          ),
          AppRoutes.home,
          reason: '재인증 예외는 로그인 흐름 4개 경로에만 적용된다',
        );
      });

      test('RB-6: 이메일 미검증 정식 사용자는 표시가 있어도 /verify-email 로 간다', () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(emailVerified: false),
          onboardingSeen: true,
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        stubLocation(AppRoutes.buildReauthLocation(AppRoutes.login));

        expect(
          await _callAuthRedirect(container, mockState),
          AppRoutes.verifyEmail,
          reason: '표시는 분기 (4) 이메일 검증 게이트를 우회하지 못한다',
        );
      });

      test('RB-7: 약관 미동의 정식 사용자는 표시가 있어도 /onboarding 으로 간다', () async {
        // _StubTermsNotifier.lastReloadedUid = 'reg-uid' 라 reload 완료 상태다.
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        stubLocation(AppRoutes.buildReauthLocation(AppRoutes.login));

        expect(
          await _callAuthRedirect(container, mockState),
          AppRoutes.onboarding,
          reason: '표시는 분기 (5) 약관 동의 게이트를 우회하지 못한다',
        );
      });

      test('RB-8: 익명 사용자의 표시 없는 /login 은 그대로 허용한다', () async {
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
          onboardingSeen: true,
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        stubLocation(AppRoutes.login);

        expect(
          await _callAuthRedirect(container, mockState),
          isNull,
          reason:
              '홈(home_screen) · 설정(settings_screen) 의 익명 전용 로그인 push 경로는 불변이어야 한다',
        );
      });
    },
  );

  group('resolveAuthRedirect 익명 · 미인증 재인증 표시 정규화 (260924-phz)', () {
    // 조작된 딥링크(/login?reauth=1 등)로 익명 · 미인증 사용자가 재인증 선택
    // 화면에 들어오면 「연결 수단 0」 배너만 있고 루트 진입이라 뒤로가기도 없는
    // 막힌 화면이 된다. 분기 (2.5) 는 정식 사용자가 아닌 사람에게 온 재인증
    // 표시를 같은 경로의 표시 없는 location 으로 redirect 해 제거한다.

    /// [user] · 온보딩 · 약관 상태에서 [location] 을 평가한 guard 결과.
    ///
    /// [user] 가 null 이면 미인증이다. 같은 상태로 정규화 결과를 재평가해
    /// redirect loop 가 없는지 확인하는 데도 쓴다.
    Future<String?> redirectFor(
      String location, {
      required fb.User? user,
      bool onboardingSeen = true,
      TermsAcceptance? termsAcceptance,
    }) async {
      final container = makeContainer(
        isInitialized: true,
        user: user,
        onboardingSeen: onboardingSeen,
        termsAcceptance: termsAcceptance,
      );
      addTearDown(container.dispose);
      stubLocation(location);
      return _callAuthRedirect(container, mockState);
    }

    test('RN-1: 익명 사용자의 재인증 표시 /login 은 표시 없는 /login 으로 간다', () async {
      expect(
        await redirectFor(
          AppRoutes.buildReauthLocation(AppRoutes.login),
          user: anonymousUser(),
          termsAcceptance: acceptedTerms(),
        ),
        AppRoutes.login,
        reason: '익명 사용자에게 재인증 선택 화면(수단 0 배너)을 열면 안 된다',
      );
      expect(
        await redirectFor(
          AppRoutes.login,
          user: anonymousUser(),
          termsAcceptance: acceptedTerms(),
        ),
        isNull,
        reason: '정규화 결과를 재평가하면 그대로 허용되어야 한다 — redirect loop 없음',
      );
    });

    test('RN-2: 익명 사용자의 이메일 로그인 · 가입 · 비밀번호 찾기 표시도 제거한다', () async {
      for (final path in <String>[
        AppRoutes.emailLogin,
        AppRoutes.signup,
        AppRoutes.forgotPassword,
      ]) {
        expect(
          await redirectFor(
            AppRoutes.buildReauthLocation(path),
            user: anonymousUser(),
            termsAcceptance: acceptedTerms(),
          ),
          path,
          reason: '$path 도 로그인 흐름 경로라 표시 없는 같은 경로로 가야 한다',
        );
        expect(
          await redirectFor(
            path,
            user: anonymousUser(),
            termsAcceptance: acceptedTerms(),
          ),
          isNull,
          reason: '$path 정규화 결과 재평가는 null 이어야 한다 — redirect loop 없음',
        );
      }
    });

    test('RN-3: 약관 미동의 익명 사용자도 표시를 제거한다', () async {
      expect(
        await redirectFor(
          AppRoutes.buildReauthLocation(AppRoutes.login),
          user: anonymousUser(),
        ),
        AppRoutes.login,
        reason: '정규화는 분기 (3) D-C1 gate 상태와 무관해야 한다',
      );
      expect(
        await redirectFor(AppRoutes.login, user: anonymousUser()),
        isNull,
        reason: '약관 미동의 익명도 로그인 흐름 경로는 머물 수 있다 — redirect loop 없음',
      );
    });

    test('RN-4: 미인증 + 온보딩 미시청 + 표시는 기존대로 /onboarding 으로 간다', () async {
      expect(
        await redirectFor(
          AppRoutes.buildReauthLocation(AppRoutes.login),
          user: null,
          onboardingSeen: false,
        ),
        AppRoutes.onboarding,
        reason: '미인증 + 온보딩 미시청은 분기 (2) 가 먼저 처리한다 — 중복 분기 없음',
      );
    });

    test('RN-5: 미인증 + 온보딩 시청 + 표시는 표시 없는 /login 으로 간다', () async {
      expect(
        await redirectFor(
          AppRoutes.buildReauthLocation(AppRoutes.login),
          user: null,
        ),
        AppRoutes.login,
        reason: '미인증 사용자에게도 재인증 선택 화면을 열면 안 된다',
      );
      expect(
        await redirectFor(AppRoutes.login, user: null),
        isNull,
        reason: '정규화 결과 재평가는 null 이어야 한다 — redirect loop 없음',
      );
    });

    test('RN-6: 표시가 아닌 값이나 로그인 흐름 밖 경로는 정규화하지 않는다', () async {
      expect(
        await redirectFor(
          Uri(
            path: AppRoutes.login,
            queryParameters: <String, String>{AppRoutes.reauthQueryKey: '0'},
          ).toString(),
          user: anonymousUser(),
          termsAcceptance: acceptedTerms(),
        ),
        isNull,
        reason: 'reauth=0 은 표시가 아니다 (strict equality)',
      );
      expect(
        await redirectFor(
          AppRoutes.buildReauthLocation(AppRoutes.onboarding),
          user: anonymousUser(),
          termsAcceptance: acceptedTerms(),
        ),
        isNull,
        reason: '온보딩 화면은 표시를 읽지 않으므로 정규화 대상이 아니다',
      );
    });
  });

  group('GoRouter push end-to-end — 재인증 표시 (260916-p8d)', () {
    // 실제 resolveAuthRedirect 를 GoRouter redirect 로 연결해 push 시점 평가를
    // 재현한다. E2E-2 는 대조군이다 — 표시 없는 push 가 홈으로 튕기지 않으면
    // harness 가 분기 (6) 에 도달하지 못한 것이므로 E2E-1 의 통과도 믿을 수 없다.
    const homeText = 'home-stub';
    const loginText = 'login-stub';
    const reauthModeText = 'reauth-mode-stub';

    /// guard 연결 GoRouter 를 pump 하고 router 를 반환한다.
    ///
    /// [user] 기본값은 완료 정식 사용자다. 온보딩 · 약관은 항상 완료 상태라
    /// 익명 사용자를 넘겨도 분기 (3) D-C1 gate 를 통과한다 (260924-phz).
    Future<GoRouter> pumpGuardedRouter(
      WidgetTester tester, {
      fb.User? user,
    }) async {
      final container = makeContainer(
        isInitialized: true,
        user: user ?? regularUser(),
        onboardingSeen: true,
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      final routerProvider = Provider<GoRouter>(
        (ref) => GoRouter(
          initialLocation: AppRoutes.home,
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const Scaffold(body: Text(homeText)),
            ),
            GoRoute(
              path: AppRoutes.login,
              // production app_router.dart builder 가 화면 모드를 정하는 식과
              // 같은 식(hasReauthMarker(state.uri))으로 재인증 모드 표지를 그린다.
              builder: (context, state) => Scaffold(
                body: Column(
                  children: <Widget>[
                    const Text(loginText),
                    if (AppRoutes.hasReauthMarker(state.uri))
                      const Text(reauthModeText),
                  ],
                ),
              ),
            ),
          ],
          redirect: (context, state) => resolveAuthRedirect(ref, state),
        ),
      );
      final router = container.read(routerProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      if (!container.read(onboardingProvider).hasValue) {
        await tester.runAsync(() => container.read(onboardingProvider.future));
      }
      expect(
        container.read(onboardingProvider).hasValue,
        isTrue,
        reason: 'loading 이면 guard 가 판단을 유보(null)해 E2E 가 거짓 통과한다',
      );
      return router;
    }

    testWidgets('E2E-1: 재인증 표시 push 는 로그인 화면을 스택 맨 위에 남긴다', (tester) async {
      final router = await pumpGuardedRouter(tester);

      unawaited(router.push(AppRoutes.buildReauthLocation(AppRoutes.login)));
      await tester.pumpAndSettle();

      expect(
        router.state.matchedLocation,
        AppRoutes.login,
        reason: '재인증 push 는 분기 (6) 에서 홈으로 튕기지 않아야 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isTrue,
        reason: 'push 한 location 의 표시가 router state 에 남아야 한다',
      );
      expect(find.text(loginText), findsOneWidget, reason: '로그인 화면이 보여야 한다');
      expect(
        find.text(reauthModeText),
        findsOneWidget,
        reason: '양성 대조: 재인증 모드 표지가 표시에 반응해야 E2E-3 의 부재가 의미를 갖는다',
      );
    });

    testWidgets('E2E-3: 익명 사용자의 재인증 표시 go 는 표시 없는 /login 에 안착한다 (260924-phz)', (
      tester,
    ) async {
      final router = await pumpGuardedRouter(tester, user: anonymousUser());

      router.go(AppRoutes.buildReauthLocation(AppRoutes.login));
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        AppRoutes.login,
        reason: '분기 (2.5) 가 표시를 제거한 /login(물음표 꼬리 없음)에 안착해야 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isFalse,
        reason: '익명 사용자의 router state 에 재인증 표시가 남으면 안 된다',
      );
      expect(find.text(loginText), findsOneWidget, reason: '로그인 화면이 보여야 한다');
      expect(
        find.text(reauthModeText),
        findsNothing,
        reason: '익명 사용자에게 재인증 모드 화면이 열리면 막힌 화면이 된다',
      );
    });

    testWidgets('E2E-2 (대조군): 표시 없는 push 는 홈으로 튕긴다', (tester) async {
      final router = await pumpGuardedRouter(tester);

      unawaited(router.push(AppRoutes.login));
      await tester.pumpAndSettle();

      expect(
        router.state.matchedLocation,
        AppRoutes.home,
        reason: '실기기 [홈 → 설정 → 홈] 적층 메커니즘이 재현되어야 한다',
      );
      expect(find.text(loginText), findsNothing, reason: '로그인 화면이 쌓이면 안 된다');
    });
  });

  group('resolveAuthRedirect 이메일 게이트 — 코드 리뷰 05 CR-02 회귀 가드', () {
    // 배경: Facebook 등은 email 권한 거부 / 전화번호 가입 계정에서 email 이
    // 없는 정식 사용자를 만든다. 분기 (4) 가 "정식 사용자는 언제나 이메일
    // 검증으로 탈출 가능" 을 전제하면 이 사용자는 /verify-email 에서 영구
    // lockout 된다. 동시에 분기 (5)(6) 의 완화를 빠뜨리면 약관 게이트가
    // 함께 우회되므로, 두 성질을 한 group 에서 같이 잠근다.

    test(
      'CR-02-A: email 미보유 정식 사용자는 /verify-email 로 보내지 않는다 (lockout 차단)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(emailVerified: false, email: ''),
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason: '검증 가능한 email 이 없으면 검증 게이트는 탈출구 없는 dead-end 이므로 적용하지 않는다',
        );
      },
    );

    test('CR-02-B: email 미보유 + 약관 미동의 정식 사용자는 홈이 아니라 /onboarding 으로 간다 '
        '(분기 (5) 완화 누락 시 약관 게이트 동반 우회)', () async {
      // 이 테스트가 CR-02 수정의 결합 지점이다. 분기 (4) 에만
      // hasVerifiableEmail 을 적용하고 분기 (5) 를 그대로 두면,
      // email 없는 사용자는 (4)(5)(6) 어디에도 걸리지 않아 홈에 진입한다.
      final container = makeContainer(
        isInitialized: true,
        user: regularUser(emailVerified: false, email: ''),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        AppRoutes.onboarding,
        reason: '약관 동의는 법적 invariant 이므로 email 유무와 무관하게 강제되어야 한다',
      );
    });

    test('CR-02-C: email 미보유 + 약관 동의 완료 사용자가 /verify-email 에 있으면 /home 으로 '
        '되돌린다 (분기 (6) 완화)', () async {
      final container = makeContainer(
        isInitialized: true,
        user: regularUser(emailVerified: false, email: ''),
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.verifyEmail);

      final result = await _callAuthRedirect(container, mockState);
      expect(result, AppRoutes.home);
    });

    test('CR-02-D: email 보유 + emailVerified=false 는 기존대로 /verify-email 로 간다 '
        '(게이트 무력화 방지)', () async {
      final container = makeContainer(
        isInitialized: true,
        user: regularUser(emailVerified: false, email: 'user@example.com'),
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(result, AppRoutes.verifyEmail);
    });
  });

  group('resolveAuthRedirect 분기 (5) — Issue #6 회귀 가드 (Plan 10-09)', () {
    // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).
    test('Issue #6 Test A: 정식 사용자 + emailVerified=true + termsProvider=null '
        '(reload 후 stale 평가) -> /onboarding (분기 (5) 발동)', () async {
      // Issue #6 핵심 회귀 가드: Firestore termsAccepted 가 비어 있는 정식
      // 사용자가 로그인한 직후, authUserObserver 가 reloadForUser 호출 후
      // termsProvider state 가 null 로 평가되면 분기 (5) 가 발동되어야 한다.
      final container = makeContainer(
        isInitialized: true,
        user: regularUser(),
        // termsAcceptance: null (Firestore reload 결과 필드 부재)
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        AppRoutes.onboarding,
        reason:
            'Issue #6 — termsProvider 가 사용자 단위로 평가되어 reload 후 '
            'null 이면 분기 (5) 가 /onboarding 으로 강제 리다이렉트',
      );
    });

    test('Issue #6 Test B: 정식 사용자 + termsProvider=null + '
        'matchedLocation=/onboarding -> null (이미 onboarding 화면 — '
        '공개 경로 허용)', () async {
      final container = makeContainer(isInitialized: true, user: regularUser());
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.onboarding);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        isNull,
        reason: '분기 (5) 가 /onboarding / /terms/* 공개 경로는 허용',
      );
    });

    test('Issue #6 Test C: 정식 사용자 + termsProvider=valid (reload 후 정상 복원) '
        '-> null (false-positive 방어)', () async {
      // Issue #6 fix 가 정상 사용자에게도 분기 (5) 를 발동시키지 않는지 확인.
      final container = makeContainer(
        isInitialized: true,
        user: regularUser(),
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        isNull,
        reason:
            'termsProvider 가 valid TermsAcceptance 면 분기 (5) 미발동 → '
            '분기 (7) null (Home 랜딩 허용)',
      );
    });

    test('Issue #6 Test D: 정식 사용자 + termsProvider=null + '
        'matchedLocation=/terms/service -> null (공개 약관 경로 허용)', () async {
      final container = makeContainer(isInitialized: true, user: regularUser());
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.termsService);

      final result = await _callAuthRedirect(container, mockState);
      expect(result, isNull);
    });
  });

  group('resolveAuthRedirect 분기 (5) Issue #7 stale 가드 (Plan 10-11)', () {
    /// Issue #7 (Plan 10-11) 전용 컨테이너 빌더 — [reloadedUid] 를 주입하여
    /// termsProvider.lastReloadedUid 가 현재 UID 와 불일치하는 stale 상태를
    /// 재현한다. 기존 [makeContainer] 는 `_StubTermsNotifier` 만 사용하므로
    /// stale 가드 시나리오를 표현할 수 없어 본 빌더가 필요하다.
    ProviderContainer makeContainerWithReloadedUid({
      required bool isInitialized,
      fb.User? user,
      bool onboardingSeen = false,
      TermsAcceptance? termsAcceptance,
      String? reloadedUid,
    }) {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(user);
      return ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(isInitialized),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          onboardingProvider.overrideWith(
            () => _StubOnboardingNotifier(onboardingSeen),
          ),
          termsProvider.overrideWith(
            () => _StubTermsNotifierWithUid(
              initial: termsAcceptance,
              reloadedUid: reloadedUid,
            ),
          ),
        ],
      );
    }

    // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).
    test('Issue #7 Test A: 정식 + emailVerified + termsAcceptance=null + '
        'lastReloadedUid != currentUser.uid (stale) + home -> null '
        '(stale 가드 발동 — reload 완료 대기)', () async {
      // 핵심 시나리오: AuthRefresh subscription #1 이 먼저 발동하여
      // resolveAuthRedirect 가 실행되는 시점에 authUserObserver 의 reloadForUser 가
      // 아직 완료되지 않아 lastReloadedUid 가 직전 익명 uid 에 머물러 있음.
      final container = makeContainerWithReloadedUid(
        isInitialized: true,
        user: regularUser(uid: 'FULL-CURRENT'),
        reloadedUid: 'OTHER-UID',
        // termsAcceptance: null
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        isNull,
        reason:
            'Issue #7 C-2 — stale 가드 발동 시 null 반환하여 현재 location '
            '유지, authUserObserver.triggerRedirect 완료 후 재평가',
      );
    });

    test('Issue #7 Test B: 정식 + emailVerified + termsAcceptance=null + '
        'lastReloadedUid == currentUser.uid (reload 완료) + home -> '
        '/onboarding (legitimate 분기 (5) 발동)', () async {
      // reloadForUser 가 완료되어 lastReloadedUid 가 현재 UID 와 일치한 뒤
      // termsAccepted=false 이면 정상적으로 /onboarding 으로 보내야 한다.
      final container = makeContainerWithReloadedUid(
        isInitialized: true,
        user: regularUser(uid: 'FULL-CURRENT'),
        reloadedUid: 'FULL-CURRENT',
        // termsAcceptance: null
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        AppRoutes.onboarding,
        reason:
            '재로그인 후 Firestore 에 termsAccepted 가 없는 정식 신규 사용자는 '
            '분기 (5) 가 정상 발동되어 /onboarding 으로 가야 한다',
      );
    });

    test('Issue #7 Test C: 정식 + emailVerified + termsAcceptance=valid + '
        'lastReloadedUid == currentUser.uid + matchedLocation=/login -> '
        '/home (분기 (6) 정상 경로 회귀)', () async {
      // stale 가드 도입이 분기 (6) 정상 경로를 침범하지 않음을 확인한다
      // (Issue #7 재검증의 정상 흐름 회귀 방어).
      final container = makeContainerWithReloadedUid(
        isInitialized: true,
        user: regularUser(uid: 'FULL-CURRENT'),
        reloadedUid: 'FULL-CURRENT',
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

      final result = await _callAuthRedirect(container, mockState);
      expect(result, AppRoutes.home);
    });
  });

  group('resolveAuthRedirect 분기 (3) — Issue #4 회귀 가드 (Plan 10-10)', () {
    // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).
    test('Issue #4 Test A: 익명 사용자 + onboardingSeen=false + home '
        '-> /onboarding (Dev Tools 온보딩 리셋 후 cold restart 재진입)', () async {
      // Scenario 6-(1): Dev Tools "온보딩 다시 보기" 탭 → SharedPreferences
      // onboarding.seen_version 제거 → 앱 cold restart → 익명 세션 복원
      // (isAuthenticated=true, isAnonymous=true) → resolveAuthRedirect 가
      // /onboarding 으로 강제 리다이렉트해야 한다.
      final container = makeContainer(
        isInitialized: true,
        user: anonymousUser(),
        // onboardingSeen: false (reset 후 상태)
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        AppRoutes.onboarding,
        reason:
            'Issue #4 — 익명 세션 복원 + 온보딩 미시청은 분기 (3) 에서 '
            '/onboarding 으로 리다이렉트해야 한다 (D-33 Dev Tools 완결성)',
      );
    });

    test('Issue #4 Test B: 익명 사용자 + onboardingSeen=false + '
        'matchedLocation=/onboarding -> null (공개 경로 예외 — 무한 루프 차단)', () async {
      final container = makeContainer(
        isInitialized: true,
        user: anonymousUser(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.onboarding);

      final result = await _callAuthRedirect(container, mockState);
      expect(result, isNull, reason: '이미 /onboarding 화면이면 재리다이렉트 금지 (루프 차단)');
    });

    test('Issue #4 Test C: 익명 사용자 + onboardingSeen=false + '
        'matchedLocation=/terms/service -> null (공개 약관 경로 허용)', () async {
      final container = makeContainer(
        isInitialized: true,
        user: anonymousUser(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.termsService);

      final result = await _callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('Issue #4 Test D: 익명 사용자 + onboardingSeen=true + '
        'termsAcceptance=완료 + home -> null '
        '(Phase 10.2 I1 — 완전한 익명 user 정상 진입)', () async {
      // Scenario 2 (정상 케이스): 익명 세션 복원 + 온보딩 시청 완료 +
      // 약관 동의 완료 → Home 직접 진입 허용. Phase 10.2 D-C1 단일 gate
      // 도입 후, 익명 user 가 /home 에 도달하려면 onboardingSeen 과
      // termsAccepted 가 모두 true 여야 한다 (I1 invariant). 본 테스트는
      // 완전한 익명 user 의 정상 경로가 분기 (3) 에 의해 차단되지 않음을
      // 회귀 검증한다.
      //
      // Phase 10.2 review CR-01 정정: 이전 버전은 termsAcceptance 를
      // 명시하지 않아 _StubTermsNotifier.lastReloadedUid 의 'reg-uid'
      // 하드코딩 + D-C2 stale guard 우연 발동으로 통과했다 (잘못된 green).
      // termsAcceptance: acceptedTerms() 명시로 I1 invariant 와 일치하는
      // 정상 통과 경로를 직접 검증한다.
      final container = makeContainer(
        isInitialized: true,
        user: anonymousUser(),
        onboardingSeen: true,
        termsAcceptance: acceptedTerms(),
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);
      expect(
        result,
        isNull,
        reason:
            'Phase 10.2 I1: onboardingSeen + termsAccepted 모두 완료한 '
            '익명 user 는 Home 통과',
      );
    });

    test(
      'Issue #4 Test E: 익명 사용자 + onboardingSeen=false + '
      'matchedLocation=/splash -> null (Splash initializer 동작 중 예외)',
      () async {
        // 분기 (2) 와 동일 정책 — splash 진입 중에는 redirect 미발동.
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.splash);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );
  });

  group(
    'resolveAuthRedirect 분기 (5) Issue #8 multi-user invariant (Plan 10-12)',
    () {
      // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).

      /// Issue #8 Test 21 전용 container — Issue #7 의
      /// [_StubTermsNotifierWithUid] 를 재사용하여 lastReloadedUid 를 주입한다.
      ProviderContainer makeIssue8Container({
        required fb.User user,
        required TermsAcceptance? termsAcceptance,
        required String? reloadedUid,
        bool onboardingSeen = true,
      }) {
        final mockAuth = _MockFirebaseAuth();
        when(() => mockAuth.currentUser).thenReturn(user);
        return ProviderContainer(
          overrides: [
            isFirebaseInitializedProvider.overrideWithValue(true),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            onboardingProvider.overrideWith(
              () => _StubOnboardingNotifier(onboardingSeen),
            ),
            termsProvider.overrideWith(
              () => _StubTermsNotifierWithUid(
                initial: termsAcceptance,
                reloadedUid: reloadedUid,
              ),
            ),
          ],
        );
      }

      test('Issue #8 Test 21: 정식 사용자 A + emailVerified + '
          'termsAcceptance=null (Firestore A 에 termsAccepted 필드 부재 — '
          'mirror skip 후 reload 가 null 로드) + lastReloadedUid=A.uid '
          '(reload 완료) + matchedLocation=/ -> /onboarding '
          '(multi-user invariant — device-local 동의값 승계 차단)', () async {
        // UAT Scenario 21 재현: Firestore 에 A 의 기존 문서가 존재하나
        // termsAccepted 필드가 삭제된 상태 → mirrorToFirestore(A) 가 Plan
        // 10-12 Option B 에 의해 skip → reloadForUser(A) 가 null 을 로드.
        // resolveAuthRedirect 분기 (5) 는 lastReloadedUid=A.uid 이므로 stale 가드
        // 통과 + !termsAccepted 조건으로 /onboarding 리다이렉트.
        final userA = regularUser(uid: 'A-UID');
        final container = makeIssue8Container(
          user: userA,
          termsAcceptance: null,
          reloadedUid: 'A-UID',
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);

        expect(
          result,
          AppRoutes.onboarding,
          reason:
              'Issue #8 multi-user invariant — 기존 사용자 A 의 Firestore '
              'termsAccepted 필드 부재 시 device-local 동의값이 승계되지 '
              '않고 /onboarding 으로 재동의 요구해야 한다 (Test 21 기대)',
        );
      });

      test('Issue #8 Test 21b: 동일 조건 + matchedLocation=/onboarding -> null '
          '(이미 onboarding 화면 — 리다이렉트 루프 차단 회귀 방어)', () async {
        final userA = regularUser(uid: 'A-UID');
        final container = makeIssue8Container(
          user: userA,
          termsAcceptance: null,
          reloadedUid: 'A-UID',
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.onboarding);

        final result = await _callAuthRedirect(container, mockState);

        expect(
          result,
          isNull,
          reason:
              '이미 /onboarding 화면이면 재리다이렉트 금지 (분기 (5) 공개 '
              '경로 화이트리스트 회귀 방어)',
        );
      });
    },
  );

  group(
    'resolveAuthRedirect fail-safe race guard — Issue #10 Plan 10-14 GC-04',
    () {
      // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).
      // 본 group 의 GC-04-E 테스트는 `awaitSettle: false` 로 호출하여
      // AsyncLoading 영구 유지 분기를 검증한다.

      test('Test GC-04-A: 미인증 + onboardingSeen=true + matchedLocation=/ '
          '-> /splash (fail-safe 발동)', () async {
        final mockCrashlytics = _MockCrashlytics();
        when(
          () => mockCrashlytics.setCustomKey(any(), any<Object>()),
        ).thenAnswer((_) async {});

        final container = makeContainer(
          isInitialized: true,
          onboardingSeen: true,
          crashlytics: mockCrashlytics,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          AppRoutes.splash,
          reason: 'GC-04: 미인증 + onboardingSeen=true + Home → /splash 복귀',
        );
      });

      test('Test GC-04-B: 미인증 + onboardingSeen=false + matchedLocation=/ '
          '-> /onboarding (기존 분기 2 우선, fail-safe 미발동)', () async {
        final container = makeContainer(isInitialized: true);
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          AppRoutes.onboarding,
          reason: '분기 (2) 가 먼저 처리되어 fail-safe 가 발동하지 않아야 함',
        );
      });

      test('Test GC-04-C: 미인증 + onboardingSeen=true + matchedLocation=/login '
          '-> null (공개 경로, fail-safe 미발동)', () async {
        final container = makeContainer(
          isInitialized: true,
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, isNull, reason: 'unauth 화이트리스트 경로는 fail-safe 미발동');
      });

      test(
        'Test GC-04-C-1 (Phase 16.1 D-01): 미인증 + onboardingSeen=true + '
        'matchedLocation=/login/email -> null (공개 경로, fail-safe 미발동)',
        () async {
          final container = makeContainer(
            isInitialized: true,
            onboardingSeen: true,
          );
          addTearDown(container.dispose);
          when(
            () => mockState.matchedLocation,
          ).thenReturn(AppRoutes.emailLogin);

          final result = await _callAuthRedirect(container, mockState);
          expect(
            result,
            isNull,
            reason: '/login/email 도 unauth 화이트리스트이므로 분기 (6.5) fail-safe 가 미발동',
          );
        },
      );

      test('Test GC-04-D: 미인증 + onboardingSeen=true + matchedLocation=/splash '
          '-> null (무한루프 방지)', () async {
        final container = makeContainer(
          isInitialized: true,
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.splash);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, isNull, reason: '/splash → /splash 자기 자신 복귀 방지');
      });

      test('Test GC-04-E: AsyncLoading 유지 상태 + matchedLocation=/ '
          '-> null (판단 유보)', () async {
        final container = makeContainer(
          isInitialized: true,
          onboardingNotifierFactory: _LoadingOnboardingNotifier.new,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        // 주의: awaitSettle=false — Future 가 영원히 resolve 안 되므로
        // timeout 우회.
        final result = await _callAuthRedirect(
          container,
          mockState,
          awaitSettle: false,
        );
        expect(
          result,
          isNull,
          reason:
              'onboardingProvider AsyncLoading 시 resolveAuthRedirect 는 판단 유보',
        );
      });

      test('Test GC-04-F (observability): fail-safe 발동 시 Crashlytics '
          'setCustomKey(race_guard_triggered) 가 1회 호출', () async {
        final mockCrashlytics = _MockCrashlytics();
        when(
          () => mockCrashlytics.setCustomKey(any(), any<Object>()),
        ).thenAnswer((_) async {});

        final container = makeContainer(
          isInitialized: true,
          onboardingSeen: true,
          crashlytics: mockCrashlytics,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(result, AppRoutes.splash);

        // unawaited 로 호출되므로 microtask 1틱 대기.
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockCrashlytics.setCustomKey(
            'race_guard_triggered',
            'onboarding_race_v1',
          ),
        ).called(1);
      });
    },
  );

  /// Phase 9.1 D-02-B (Plan 09.1-04) — resolveAuthRedirect 분기 (6.4)
  /// `socialLinkInProgress` 가드 회귀 테스트.
  ///
  /// AuthRepository 의 social sign-in 메서드(`signInWith{Google,Apple,Facebook}`)
  /// 가 진행 중이면 GC-04 fail-safe 직전에 분기 (6.4) 가 발동되어 redirect 자체를
  /// 보류 (`null` 반환) 해야 한다. Crashlytics 신호는 `social_link_v1` 로 기록되어
  /// 기존 `onboarding_race_v1` (Plan 10-14) 과 forensic 구분된다
  /// (`09-UAT.md` Gap test 6 root_cause).
  group('resolveAuthRedirect socialLinkInProgress 가드 — Phase 9.1 D-02-B', () {
    // Phase 9.1 IN-03: 공통 `_callAuthRedirect` 로 추출 (file top-level).

    test('Test SLP-G1: socialLinkInProgress=true + 미인증 + onboardingSeen=true + '
        'matchedLocation=/ -> null (보류) + social_link_v1 Crashlytics 기록 + '
        'onboarding_race_v1 미기록 (분기 6.4 가 6.5 보다 먼저 매칭)', () async {
      final mockCrashlytics = _MockCrashlytics();
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          onboardingProvider.overrideWith(() => _StubOnboardingNotifier(true)),
          termsProvider.overrideWith(() => _StubTermsNotifier(null)),
          crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
          // Phase 9.1 D-02-B: socialLinkInProgress=true.
          socialLinkInProgressProvider.overrideWith(
            () => _StubSocialLinkInProgress(true),
          ),
        ],
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);

      // Assert — null 반환 (보류).
      expect(result, isNull, reason: '6.4 D-02-B: 진행 중이면 GC-04 보류, null 반환');

      // unawaited 호출이므로 microtask 1틱 대기.
      await Future<void>.delayed(Duration.zero);

      // social_link_v1 Crashlytics 기록 검증.
      verify(
        () => mockCrashlytics.setCustomKey(
          'race_guard_triggered',
          'social_link_v1',
        ),
      ).called(1);
      // 핵심 검증: onboarding_race_v1 신호는 기록되지 않아야 함 (6.4 가
      // 먼저 매칭되어 6.5 GC-04 분기에 도달하지 않음).
      verifyNever(
        () => mockCrashlytics.setCustomKey(
          'race_guard_triggered',
          'onboarding_race_v1',
        ),
      );
    });

    test('Test SLP-G2: socialLinkInProgress=false + 동일 GC-04 매칭 조건 -> '
        '/splash + onboarding_race_v1 (기존 GC-04 회귀 가드)', () async {
      final mockCrashlytics = _MockCrashlytics();
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          onboardingProvider.overrideWith(() => _StubOnboardingNotifier(true)),
          termsProvider.overrideWith(() => _StubTermsNotifier(null)),
          crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
          // socialLinkInProgress=false (기본값 — override 생략 가능하지만
          // 명시적으로 negative path 의도를 표현).
          socialLinkInProgressProvider.overrideWith(
            () => _StubSocialLinkInProgress(false),
          ),
        ],
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);

      // Assert — /splash 반환 (기존 GC-04) + onboarding_race_v1 기록.
      expect(result, AppRoutes.splash, reason: '6.4 미발동 시 6.5 GC-04 정상 동작');

      await Future<void>.delayed(Duration.zero);

      verify(
        () => mockCrashlytics.setCustomKey(
          'race_guard_triggered',
          'onboarding_race_v1',
        ),
      ).called(1);
      verifyNever(
        () => mockCrashlytics.setCustomKey(
          'race_guard_triggered',
          'social_link_v1',
        ),
      );
    });

    test('Test SLP-G3: 정식 인증 사용자 + termsAccepted + '
        'socialLinkInProgress=true -> 6.4 가드 미발동 (정상 인증 흐름 보존)', () async {
      final mockCrashlytics = _MockCrashlytics();
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      final user = regularUser();
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(user);

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          onboardingProvider.overrideWith(() => _StubOnboardingNotifier(true)),
          // termsAccepted 가 있는 정상 사용자.
          termsProvider.overrideWith(() => _StubTermsNotifier(acceptedTerms())),
          crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
          socialLinkInProgressProvider.overrideWith(
            () => _StubSocialLinkInProgress(true),
          ),
        ],
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await _callAuthRedirect(container, mockState);

      // Assert — 정상 Home 랜딩 (분기 (7) null) + 어떤 race_guard 신호도
      // 기록되지 않음. 6.4 가드는 `!isAuthenticated` 조건이므로 정식 사용자
      // 에게는 발동하지 않는다.
      expect(result, isNull, reason: '인증 + termsAccepted 사용자는 6.4/6.5 미진입');

      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => mockCrashlytics.setCustomKey(
          'race_guard_triggered',
          'social_link_v1',
        ),
      );
      verifyNever(
        () => mockCrashlytics.setCustomKey(
          'race_guard_triggered',
          'onboarding_race_v1',
        ),
      );
    });
  });

  // Phase 10.2 D-C1/C2 — Plan 02 land 시 production code 가 분기 (3) 정정 +
  // stale guard 확장으로 GREEN 전환. 현재 RED (Plan 02 land 전) 는
  // Wave 0 의 의도된 acceptance signal — 분기 (3) production code 가
  // (!onboardingSeen || !termsAccepted) 단일 gate 로 통합되어야 (a)(b) 케이스
  // 가 /onboarding 으로, (c) 가 null 로, (d) stale guard 발동 시 null 로,
  // (e) /login 화이트리스트가 null 로 평가된다 (Pitfall 4 회귀 가드).
  group(
    'resolveAuthRedirect 분기 (3) — 익명 user 단일 gate (Phase 10.2 D-C1/C2)',
    () {
      /// Phase 10.2 D-C1/C2 — Issue #7 분기 (5) 의 `makeContainerWithReloadedUid`
      /// 패턴을 익명 분기 (3) stale 가드 검증용으로 그대로 차용한다.
      ProviderContainer makeContainerWithReloadedUid({
        required bool isInitialized,
        fb.User? user,
        bool onboardingSeen = false,
        TermsAcceptance? termsAcceptance,
        String? reloadedUid,
      }) {
        final mockAuth = _MockFirebaseAuth();
        when(() => mockAuth.currentUser).thenReturn(user);
        return ProviderContainer(
          overrides: [
            isFirebaseInitializedProvider.overrideWithValue(isInitialized),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            onboardingProvider.overrideWith(
              () => _StubOnboardingNotifier(onboardingSeen),
            ),
            termsProvider.overrideWith(
              () => _StubTermsNotifierWithUid(
                initial: termsAcceptance,
                reloadedUid: reloadedUid,
              ),
            ),
          ],
        );
      }

      test('(a) 익명 + !onboardingSeen + termsAccepted + home -> /onboarding '
          '(D-C1: !onboardingSeen 단일 gate trip)', () async {
        final container = makeContainerWithReloadedUid(
          isInitialized: true,
          user: anonymousUser(),
          // onboardingSeen: false (default)
          termsAcceptance: acceptedTerms(),
          reloadedUid: 'anon-uid', // 비-stale
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          AppRoutes.onboarding,
          reason: 'D-C1: !onboardingSeen 단일 gate trip',
        );
      });

      test('(b) 익명 + onboardingSeen + !termsAccepted (비-stale) + home '
          '-> /onboarding (D-C1: !termsAccepted 단일 gate trip)', () async {
        final container = makeContainerWithReloadedUid(
          isInitialized: true,
          user: anonymousUser(),
          onboardingSeen: true,
          // termsAcceptance: null (!termsAccepted)
          reloadedUid: 'anon-uid', // 비-stale
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          AppRoutes.onboarding,
          reason: 'D-C1: !termsAccepted 단일 gate trip',
        );
      });

      test('(c) 익명 + onboardingSeen + termsAccepted (완전) + home -> null '
          '(I1: 완전한 익명 user 는 /home 통과)', () async {
        final container = makeContainerWithReloadedUid(
          isInitialized: true,
          user: anonymousUser(),
          onboardingSeen: true,
          termsAcceptance: acceptedTerms(),
          reloadedUid: 'anon-uid',
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason:
              'I1: onboardingSeen + termsAccepted 모두 완료한 익명 user '
              '는 /home 통과',
        );
      });

      test('(d) 익명 + onboardingSeen + !termsAccepted + stale lastReloadedUid + '
          'home -> null (D-C2: stale guard 발동 → reload 완료 대기)', () async {
        final container = makeContainerWithReloadedUid(
          isInitialized: true,
          user: anonymousUser(), // uid = 'anon-uid'
          onboardingSeen: true,
          // termsAcceptance: null
          reloadedUid: 'OTHER-UID', // stale lastReloadedUid
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason:
              'D-C2: termsProvider stale lastReloadedUid 면 reload 완료 '
              '대기 (분기 (5) 패턴 익명 확장 — Plan 10-11 Issue #7 C-2)',
        );
      });

      test('(e — Pitfall 4 회귀 가드) 익명 + !onboardingSeen + '
          'matchedLocation=/login -> null (정식 승격 경로 보존)', () async {
        // Pitfall 4: `!isOnUnauthRoute` 가드 누락 시 /login + 익명 user 가
        // 무한 redirect loop 회귀. 익명 user 의 정식 승격 경로 보존 보장.
        final container = makeContainerWithReloadedUid(
          isInitialized: true,
          user: anonymousUser(),
          onboardingSeen: false,
          reloadedUid: 'anon-uid',
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

        final result = await _callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason:
              'Pitfall 4: 익명 user 의 /login 진입은 정식 승격 경로 '
              '이므로 onboarding 강제 redirect 금지',
        );
      });
    },
  );
}
