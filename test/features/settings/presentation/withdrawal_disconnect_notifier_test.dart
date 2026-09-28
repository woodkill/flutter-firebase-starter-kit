// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 07 — 탈퇴 진행 notifier (WithdrawalDisconnect) 단위 테스트.
//
// fake step 은 run 호출마다 Completer 를 쌓는다 — 테스트가 결과를 직접 완료해
// 상태 전이를 단계별로 관찰한다. 행 상태는 직접 만들지 않고 fake 결과로 도달시킨다.
//
//   WN1: 카카오 서버 행 1개 — start → working → Done → allDone → 삭제 1회 · reloginForFreshness true

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
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
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
  _FakeStep(this.provider);

  @override
  final AccountProvider provider;

  @override
  AuthStrategy? get signInStrategy => null;

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

/// 이벤트 큐를 한 번 비운다 — Completer 완료 뒤 notifier 반영.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockSettingsRepository mockSettingsRepo;
  late _MockAuthRepository mockAuthRepo;
  late _MockCrashlyticsService mockCrashlytics;
  late DisconnectDeps deps;

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
  });

  /// fake step [steps] 와 providerIds [providerIds] 사용자로 container 를 만든다.
  ///
  /// 진행 notifier · settings notifier 는 auto-dispose 라 listen 으로 붙잡는다.
  ProviderContainer makeContainer({
    required List<String> providerIds,
    required List<DisconnectStep> steps,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => ref.watch(_userHolderProvider),
        ),
        disconnectStepsProvider.overrideWithValue(steps),
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

  group('Phase 16.10 — WithdrawalDisconnect notifier', () {
    test('WN1: 카카오 서버 행 1개 — start 즉시 해제 중 → Done → allDone → 삭제 1회', () async {
      final kakao = _FakeStep(AccountProvider.kakao);
      final container = makeContainer(
        providerIds: <String>['kakao'],
        steps: <DisconnectStep>[kakao],
      );
      final notifier = container.read(withdrawalDisconnectProvider.notifier);

      final started = notifier.start();
      var state = container.read(withdrawalDisconnectProvider);
      expect(state.rows, hasLength(1));
      expect(state.rows.single.provider, AccountProvider.kakao);
      expect(state.rows.single.kind, DisconnectKind.server);
      expect(state.rows.single.status, DisconnectRowStatus.working);
      expect(state.allDone, isFalse);
      expect(kakao.calls.length, 1);

      kakao.calls.last.complete(const DisconnectDone());
      await started;
      state = container.read(withdrawalDisconnectProvider);
      expect(state.rows.single.status, DisconnectRowStatus.done);
      expect(state.allDone, isTrue);
      verifyNever(() => mockSettingsRepo.requestAccountDeletion());

      await notifier.requestDeletion();
      await _flush();
      verify(() => mockSettingsRepo.requestAccountDeletion()).called(1);
      expect(kakao.lastRelogin, isTrue);
    });
  });
}
