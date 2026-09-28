// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 07 — 탈퇴 진행 notifier (WithdrawalDisconnect) 단위 테스트.
//
// fake step 은 run 호출마다 Completer 를 쌓는다 — 테스트가 결과를 직접 완료해
// 상태 전이를 단계별로 관찰한다. 행 상태는 직접 만들지 않고 fake 결과로 도달시킨다
// (5분 창 fixture — `wasDisconnected` 는 Done 을 받은 행만 참이어야 실제 흐름과 같다).
//
//   WN1: 카카오 서버 행 1개 — start → working → Done → allDone → 삭제 1회 · reloginForFreshness true
//   WN2: W5 fixture → 행 순서 facebook · kakao · google · apple · naver · line
//   WN3: password · 미지 id 제외 → 행 [kakao]
//   WN4: start 직후 — 서버 행 working · 첫 재로그인 행 needsSignIn · 나머지 waiting
//   WN5: google 로그인 Done → google done · apple needsSignIn
//   WN6: 로그인 취소 → needsSignIn 복귀 (failed 아님)
//   WN7: 신원 불일치 → mismatch · 현재 행 유지
//   WN8: 끊기 실패 → failed · 현재 행 유지
//   WN9: 서버 행 실패 → retry → Done
//   WN10: skip — 현재 재로그인 행 · 실패 서버 행
//   WN11: user-triggered 진행 중 다른 동작 무시
//   WN12: 자동 행 진행 중에도 로그인 허용
//   WN13: start 뒤 user stream 재방출 → rows 불변 (Pitfall 4)
//   WN14: requestDeletion 가드 · start 1회
//   WN15: 삭제 재인증 거부 뒤 rows 불변
//   WN16: 5분 창 (a) — 마지막 「해제됨」 재로그인 행 재개방 · 재로그인 1회로 재해제 뒤 삭제
//   WN17: 5분 창 (a) 대상 없음 → false · rows 불변
//   WN18: 5분 창 (b) — wasDisconnected 서버 행 재실행 · 끊긴 적 없는 건너뛴 행 불변
//   WN19: 5분 창 (b) — (a) 로 열렸다 건너뛴 재로그인 행 재개방 · 끝나기 전 삭제 0

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_notifier.dart';
import 'package:flutter_starter_kit/features/settings/presentation/withdrawal_disconnect_notifier.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

/// 결과를 테스트가 제어하는 끊기 step — run 호출마다 Completer 1개.
class _FakeStep extends DisconnectStep {
  _FakeStep(this.provider, {this.signInStrategy});

  @override
  final AccountProvider provider;

  @override
  final AuthStrategy? signInStrategy;

  /// run 호출 순서대로 쌓인 결과 Completer.
  final List<Completer<DisconnectOutcome>> calls =
      <Completer<DisconnectOutcome>>[];

  /// run 호출마다 받은 reloginForFreshness 값.
  final List<bool> relogins = <bool>[];

  /// 마지막 run 의 reloginForFreshness 값.
  bool? get lastRelogin => relogins.lastOrNull;

  @override
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  }) {
    relogins.add(reloginForFreshness);
    final completer = Completer<DisconnectOutcome>();
    calls.add(completer);
    return completer.future;
  }
}

/// 레지스트리와 같은 모양의 fake step 6종 — 서버 2 · 재로그인 4.
class _Fakes {
  final _FakeStep kakao = _FakeStep(AccountProvider.kakao);
  final _FakeStep facebook = _FakeStep(AccountProvider.facebook);
  final _FakeStep google = _FakeStep(
    AccountProvider.google,
    signInStrategy: const GoogleAuthStrategy(),
  );
  final _FakeStep apple = _FakeStep(
    AccountProvider.apple,
    signInStrategy: const AppleAuthStrategy(),
  );
  final _FakeStep naver = _FakeStep(
    AccountProvider.naver,
    signInStrategy: const NaverAuthStrategy(),
  );
  final _FakeStep line = _FakeStep(
    AccountProvider.line,
    signInStrategy: const LineAuthStrategy(),
  );

  /// 레지스트리 목록 (등록 순서는 표시 순서와 무관하다).
  List<DisconnectStep> get all => <DisconnectStep>[
    kakao,
    facebook,
    google,
    apple,
    naver,
    line,
  ];
}

/// start() 뒤 user stream 재방출을 흉내 내는 사용자 holder (WN13).
class _UserHolder extends Notifier<User?> {
  @override
  User? build() => null;

  /// 현재 사용자를 [user] 로 바꾼다.
  void setUser(User? user) => state = user;
}

final _userHolderProvider = NotifierProvider<_UserHolder, User?>(
  _UserHolder.new,
);

User _userWith(List<String> providerIds) => User(
  uid: 'uid-test',
  emailVerified: true,
  createdAt: DateTime(2026),
  providerIds: providerIds,
);

/// 16.8 W5 fixture — 가입 naver · 보유 6종.
const List<String> _w5ProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'line',
  'naver',
];

/// 이벤트 큐를 한 번 비운다 — Completer 완료 뒤 notifier 반영.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockSettingsRepository mockSettingsRepo;
  late _MockAuthRepository mockAuthRepo;
  late _MockCrashlyticsService mockCrashlytics;
  late DisconnectDeps deps;
  late _Fakes fakes;

  setUp(() {
    mockSettingsRepo = _MockSettingsRepository();
    mockAuthRepo = _MockAuthRepository();
    mockCrashlytics = _MockCrashlyticsService();
    when(
      () => mockSettingsRepo.requestAccountDeletion(),
    ).thenAnswer((_) async {});
    when(
      () => mockAuthRepo.signOutAndResetOnboarding(),
    ).thenAnswer((_) async {});
    deps = DisconnectDeps(
      auth: _MockFirebaseAuth(),
      functions: _MockFirebaseFunctions(),
      googleSignIn: _MockGoogleSignIn(),
      lineSdkClient: _MockLineSdkClient(),
      naverSdkClient: _MockNaverSdkClient(),
      platform: TargetPlatform.android,
    );
    fakes = _Fakes();
  });

  /// providerIds [providerIds] 사용자 · [fakes] 레지스트리로 container 를 만든다.
  ///
  /// 진행 notifier · settings notifier 는 auto-dispose 라 listen 으로 붙잡는다.
  ProviderContainer makeContainer(List<String> providerIds) {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => ref.watch(_userHolderProvider),
        ),
        disconnectStepsProvider.overrideWithValue(fakes.all),
        disconnectDepsProvider.overrideWithValue(deps),
        settingsRepositoryProvider.overrideWithValue(mockSettingsRepo),
        authRepositoryProvider.overrideWithValue(mockAuthRepo),
        crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(_userHolderProvider.notifier)
        .setUser(_userWith(providerIds));
    container
      ..listen(withdrawalDisconnectProvider, (_, _) {})
      ..listen(settingsProvider, (_, _) {});
    return container;
  }

  WithdrawalDisconnectState stateOf(ProviderContainer container) =>
      container.read(withdrawalDisconnectProvider);

  DisconnectRowStatus statusOf(
    ProviderContainer container,
    AccountProvider provider,
  ) => stateOf(
    container,
  ).rows.singleWhere((row) => row.provider == provider).status;

  List<DisconnectRowStatus> statusesOf(ProviderContainer container) => [
    for (final row in stateOf(container).rows) row.status,
  ];

  group('Phase 16.10 — WithdrawalDisconnect notifier', () {
    test('WN1: 카카오 서버 행 1개 — start 즉시 해제 중 → Done → allDone → 삭제 1회', () async {
      final container = makeContainer(<String>['kakao']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);

      final started = notifier.start();
      var state = stateOf(container);
      expect(state.rows, hasLength(1));
      expect(state.rows.single.provider, AccountProvider.kakao);
      expect(state.rows.single.kind, DisconnectKind.server);
      expect(state.rows.single.status, DisconnectRowStatus.working);
      expect(state.allDone, isFalse);
      expect(fakes.kakao.calls.length, 1);

      fakes.kakao.calls.last.complete(const DisconnectDone());
      await started;
      state = stateOf(container);
      expect(state.rows.single.status, DisconnectRowStatus.done);
      expect(state.allDone, isTrue);
      verifyNever(() => mockSettingsRepo.requestAccountDeletion());

      await notifier.requestDeletion();
      await _flush();
      verify(() => mockSettingsRepo.requestAccountDeletion()).called(1);
      expect(fakes.kakao.lastRelogin, isTrue);
    });

    test('WN2: W5 fixture — 서버 행 먼저 · 각 묶음은 킷 표준 순서', () {
      final container = makeContainer(_w5ProviderIds);
      unawaited(container.read(withdrawalDisconnectProvider.notifier).start());

      expect(
        [for (final row in stateOf(container).rows) row.provider],
        <AccountProvider>[
          AccountProvider.facebook,
          AccountProvider.kakao,
          AccountProvider.google,
          AccountProvider.apple,
          AccountProvider.naver,
          AccountProvider.line,
        ],
      );
      // 라벨 입력은 providerIds 원소 그대로다.
      expect(stateOf(container).rows.first.providerId, 'facebook.com');
    });

    test('WN3: password · 미지 id 는 행이 아니다 → 행 [kakao]', () {
      final container = makeContainer(<String>[
        'password',
        'kakao',
        'twitter.com',
      ]);
      unawaited(container.read(withdrawalDisconnectProvider.notifier).start());

      expect(
        [for (final row in stateOf(container).rows) row.provider],
        <AccountProvider>[AccountProvider.kakao],
      );
    });

    test('WN4: start 직후 — 서버 행 해제 중 · 첫 재로그인 행만 로그인 대기', () {
      final container = makeContainer(_w5ProviderIds);
      unawaited(container.read(withdrawalDisconnectProvider.notifier).start());

      expect(statusesOf(container), <DisconnectRowStatus>[
        DisconnectRowStatus.working,
        DisconnectRowStatus.working,
        DisconnectRowStatus.needsSignIn,
        DisconnectRowStatus.waiting,
        DisconnectRowStatus.waiting,
        DisconnectRowStatus.waiting,
      ]);
      expect(fakes.facebook.calls.length, 1);
      expect(fakes.kakao.calls.length, 1);
      expect(fakes.google.calls, isEmpty);
      expect(
        stateOf(container).currentReloginRow?.provider,
        AccountProvider.google,
      );
      // 자동 행 실행은 사용자 트리거 잠금이 아니다.
      expect(stateOf(container).actionsLocked, isFalse);
    });

    test('WN5: google 로그인 Done → google 해제됨 · apple 로그인 대기', () async {
      final container = makeContainer(<String>['google.com', 'apple.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      await notifier.start();

      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.working,
      );
      expect(stateOf(container).userTriggered, AccountProvider.google);
      fakes.google.calls.last.complete(const DisconnectDone());
      await signIn;

      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.done,
      );
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.needsSignIn,
      );
      expect(stateOf(container).actionsLocked, isFalse);
      expect(fakes.google.lastRelogin, isTrue);
    });

    test('WN6: 로그인 취소 → 로그인 대기 복귀 (실패 아님)', () async {
      final container = makeContainer(<String>['google.com', 'apple.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      await notifier.start();

      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      fakes.google.calls.last.complete(const DisconnectCancelled());
      await signIn;

      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.needsSignIn,
      );
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.waiting,
      );
      expect(stateOf(container).actionsLocked, isFalse);
    });

    test('WN7: 신원 불일치 → mismatch · 현재 행 유지 · 다음 행 대기', () async {
      final container = makeContainer(<String>['google.com', 'apple.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      await notifier.start();

      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      fakes.google.calls.last.complete(const DisconnectIdentityMismatch());
      await signIn;

      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.mismatch,
      );
      expect(
        stateOf(container).currentReloginRow?.provider,
        AccountProvider.google,
      );
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.waiting,
      );

      // 불일치 행은 다시 로그인할 수 있다.
      unawaited(notifier.signInAndDisconnect(AccountProvider.google));
      expect(fakes.google.calls.length, 2);
    });

    test('WN8: 끊기 실패 → failed · 현재 행 유지', () async {
      final container = makeContainer(<String>['google.com', 'apple.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      await notifier.start();

      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      fakes.google.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await signIn;

      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.failed,
      );
      expect(
        stateOf(container).currentReloginRow?.provider,
        AccountProvider.google,
      );
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.waiting,
      );
    });

    test('WN9: 서버 행 실패 → retry → Done', () async {
      final container = makeContainer(<String>['kakao']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(NoInternetConnection()),
      );
      await started;
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.failed,
      );

      final retried = notifier.retry(AccountProvider.kakao);
      expect(fakes.kakao.calls.length, 2);
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.working,
      );
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await retried;
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.done,
      );
    });

    test('WN10: skip — 현재 재로그인 행 · 실패 서버 행', () async {
      final container = makeContainer(<String>[
        'google.com',
        'apple.com',
        'kakao',
      ]);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await started;

      notifier.skip(AccountProvider.google);
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.skipped,
      );
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.needsSignIn,
      );

      notifier.skip(AccountProvider.kakao);
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.skipped,
      );
      expect(fakes.google.calls, isEmpty);
    });

    test('WN11: 사용자 트리거 진행 중 — 로그인 · 건너뛰기 · 재시도 재호출 무시', () async {
      final container = makeContainer(<String>[
        'google.com',
        'apple.com',
        'kakao',
      ]);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await started;

      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      expect(stateOf(container).actionsLocked, isTrue);

      unawaited(notifier.signInAndDisconnect(AccountProvider.google));
      notifier
        ..skip(AccountProvider.apple)
        ..skip(AccountProvider.kakao);
      unawaited(notifier.retry(AccountProvider.kakao));

      expect(fakes.google.calls.length, 1);
      expect(fakes.kakao.calls.length, 1);
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.waiting,
      );
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.failed,
      );

      fakes.google.calls.last.complete(const DisconnectDone());
      await signIn;
      expect(stateOf(container).actionsLocked, isFalse);
    });

    test('WN12: 자동 행 진행 중에도 현재 재로그인 행 로그인 허용', () {
      final container = makeContainer(<String>['kakao', 'google.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      unawaited(notifier.start());
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.working,
      );

      unawaited(notifier.signInAndDisconnect(AccountProvider.google));
      expect(fakes.google.calls.length, 1);
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.working,
      );
    });

    test('WN13: start 뒤 user stream 재방출 — 행 목록 · 상태 불변', () async {
      final container = makeContainer(<String>['kakao', 'google.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      unawaited(notifier.start());
      final before = statusesOf(container);

      // 재로그인(signInWithCustomToken 등)이 user 를 재방출한 상황.
      container
          .read(_userHolderProvider.notifier)
          .setUser(_userWith(<String>['naver']));
      await _flush();

      expect(
        [for (final row in stateOf(container).rows) row.provider],
        <AccountProvider>[AccountProvider.kakao, AccountProvider.google],
      );
      expect(statusesOf(container), before);
    });

    test(
      'WN14: requestDeletion — 미완료면 삭제 0 · start 2회여도 서버 행 1회 · 모두 끝나면 1',
      () async {
        final container = makeContainer(<String>['kakao', 'google.com']);
        final notifier = container.read(withdrawalDisconnectProvider.notifier);
        final started = notifier.start();
        unawaited(notifier.start());
        expect(fakes.kakao.calls.length, 1);

        await notifier.requestDeletion();
        verifyNever(() => mockSettingsRepo.requestAccountDeletion());

        fakes.kakao.calls.last.complete(const DisconnectDone());
        await started;
        await notifier.requestDeletion();
        verifyNever(() => mockSettingsRepo.requestAccountDeletion());

        notifier.skip(AccountProvider.google);
        expect(stateOf(container).allDone, isTrue);
        await notifier.requestDeletion();
        verify(() => mockSettingsRepo.requestAccountDeletion()).called(1);
      },
    );

    test('WN15: 삭제 재인증 거부 직후 — notifier 는 rows 를 스스로 바꾸지 않는다', () async {
      when(
        () => mockSettingsRepo.requestAccountDeletion(),
      ).thenThrow(const ReauthenticationRequiredException());
      final container = makeContainer(<String>['kakao', 'google.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await started;
      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      fakes.google.calls.last.complete(const DisconnectDone());
      await signIn;
      final before = statusesOf(container);

      await notifier.requestDeletion();
      verify(() => mockSettingsRepo.requestAccountDeletion()).called(1);
      expect(
        container.read(settingsProvider).error,
        isA<ReauthenticationRequiredException>(),
      );
      expect(statusesOf(container), before);
    });

    test('WN16: 5분 창 (a) — 마지막 「해제됨」 재로그인 행 재개방 → 그 행 재로그인 뒤에만 삭제', () async {
      var deleteCalls = 0;
      when(() => mockSettingsRepo.requestAccountDeletion()).thenAnswer((
        _,
      ) async {
        deleteCalls++;
        if (deleteCalls == 1) {
          throw const ReauthenticationRequiredException();
        }
      });
      final container = makeContainer(<String>[
        'kakao',
        'google.com',
        'apple.com',
      ]);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await started;
      final googleSignIn = notifier.signInAndDisconnect(AccountProvider.google);
      fakes.google.calls.last.complete(const DisconnectDone());
      await googleSignIn;
      final appleSignIn = notifier.signInAndDisconnect(AccountProvider.apple);
      fakes.apple.calls.last.complete(const DisconnectDone());
      await appleSignIn;

      await notifier.requestDeletion();
      expect(deleteCalls, 1);

      expect(notifier.reopenRowForFreshness(), isTrue);
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.needsSignIn,
      );
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.done,
      );
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.done,
      );
      await notifier.requestDeletion();
      expect(deleteCalls, 1);

      final reSignIn = notifier.signInAndDisconnect(AccountProvider.apple);
      expect(fakes.apple.calls.length, 2);
      expect(fakes.apple.lastRelogin, isTrue);
      await notifier.requestDeletion();
      expect(deleteCalls, 1);
      fakes.apple.calls.last.complete(const DisconnectDone());
      await reSignIn;

      expect(stateOf(container).allDone, isTrue);
      await notifier.requestDeletion();
      expect(deleteCalls, 2);
    });

    test('WN17: 5분 창 (a) — 「해제됨」 재로그인 행이 없으면 false · rows 불변', () async {
      final container = makeContainer(<String>[
        'kakao',
        'facebook.com',
        'apple.com',
      ]);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(const DisconnectDone());
      fakes.facebook.calls.last.complete(const DisconnectDone());
      await started;
      notifier.skip(AccountProvider.apple);
      final before = statusesOf(container);

      expect(notifier.reopenRowForFreshness(), isFalse);
      expect(statusesOf(container), before);
      expect(
        statusOf(container, AccountProvider.apple),
        DisconnectRowStatus.skipped,
      );
    });

    test(
      'WN18: 5분 창 (b) — 해제됐던 서버 행 재실행 · 끊긴 적 없는 건너뛴 행 불변 · 재해제 전 삭제 0',
      () async {
        final container = makeContainer(<String>[
          'kakao',
          'facebook.com',
          'apple.com',
        ]);
        final notifier = container.read(withdrawalDisconnectProvider.notifier);
        final started = notifier.start();
        fakes.kakao.calls.last.complete(const DisconnectDone());
        fakes.facebook.calls.last.complete(const DisconnectDone());
        await started;
        notifier.skip(AccountProvider.apple);
        expect(notifier.reopenRowForFreshness(), isFalse);

        final redisconnect = notifier.redisconnectAfterReauth();
        expect(fakes.kakao.calls.length, 2);
        expect(fakes.facebook.calls.length, 2);
        expect(
          statusOf(container, AccountProvider.kakao),
          DisconnectRowStatus.working,
        );
        expect(
          statusOf(container, AccountProvider.facebook),
          DisconnectRowStatus.working,
        );
        expect(
          statusOf(container, AccountProvider.apple),
          DisconnectRowStatus.skipped,
        );
        expect(fakes.apple.calls, isEmpty);

        await notifier.requestDeletion();
        verifyNever(() => mockSettingsRepo.requestAccountDeletion());

        fakes.kakao.calls.last.complete(const DisconnectDone());
        fakes.facebook.calls.last.complete(const DisconnectDone());
        await redisconnect;
        expect(stateOf(container).allDone, isTrue);
        await notifier.requestDeletion();
        verify(() => mockSettingsRepo.requestAccountDeletion()).called(1);
      },
    );

    test('WN19: 5분 창 (b) — (a) 로 열렸다 건너뛴 재로그인 행은 재인증 뒤 다시 로그인 대기', () async {
      final container = makeContainer(<String>['kakao', 'google.com']);
      final notifier = container.read(withdrawalDisconnectProvider.notifier);
      final started = notifier.start();
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await started;
      final signIn = notifier.signInAndDisconnect(AccountProvider.google);
      fakes.google.calls.last.complete(const DisconnectDone());
      await signIn;

      expect(notifier.reopenRowForFreshness(), isTrue);
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.needsSignIn,
      );
      notifier.skip(AccountProvider.google);
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.skipped,
      );

      final redisconnect = notifier.redisconnectAfterReauth();
      expect(
        statusOf(container, AccountProvider.google),
        DisconnectRowStatus.needsSignIn,
      );
      expect(
        stateOf(container).currentReloginRow?.provider,
        AccountProvider.google,
      );
      expect(fakes.kakao.calls.length, 2);

      fakes.kakao.calls.last.complete(const DisconnectDone());
      await redisconnect;
      expect(
        statusOf(container, AccountProvider.kakao),
        DisconnectRowStatus.done,
      );
      expect(stateOf(container).allDone, isFalse);
      await notifier.requestDeletion();
      verifyNever(() => mockSettingsRepo.requestAccountDeletion());
    });
  });
}
