// Phase 13 — see ROADMAP.md (T-13-NAVER-NOTIFIER + R7 회귀 가드)
// Phase 16.4 — see ROADMAP.md (레버 5 판정용 lifecycle 임시 로그 회귀 가드)

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/naver_sign_in_notifier.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// `flutter/lifecycle` 채널로 [next] 전이를 주입한다 (Phase 16.4).
///
/// `WidgetsBinding.handleAppLifecycleStateChanged` 는 `SchedulerBinding` 에서
/// `@protected` `@mustCallSuper` 라 테스트가 직접 부르면
/// `invalid_use_of_protected_member` 진단이 난다 — 채널 주입이 analyze 0 진단을
/// 유지하는 경로다.
///
/// 주의: `ServicesBinding` 이 인접하지 않은 전이 사이를 스스로 채우므로
/// (`_generateStateTransitions`) 주입 1회가 전이 1회와 같지 않다.
Future<void> pushLifecycle(AppLifecycleState next) async {
  await TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage('AppLifecycleState.${next.name}'),
        (_) {},
      );
}

void main() {
  // Phase 16.4 — `AppLifecycleListener` 생성자가 `WidgetsBinding.instance` 를
  // 요구한다. 이 줄이 없으면 lifecycle 로그가 붙은 뒤 기존 4 테스트도 생성자에서
  // 깨진다.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('NaverSignInNotifier.signInWithNaver (T-13-NAVER-NOTIFIER)', () {
    test('T-13-NAVER-NOTIFIER-02: 성공 → AsyncData<void>(null)', () async {
      // Custom Token 흐름: emailVerified=true 자동 부여 (D-46/D-47).
      final user = User(
        uid: 'naver-uid-001',
        email: 'test@naver.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 5),
        providerIds: const <String>['naver'],
      );
      when(
        () => mockRepo.signInWithNaver(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);

      await notifier.signInWithNaver();

      final state = container.read(naverSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('T-13-NAVER-NOTIFIER-03: 실패 → AsyncError', () async {
      when(() => mockRepo.signInWithNaver()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);

      await notifier.signInWithNaver();

      final state = container.read(naverSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test(
      'T-13-NAVER-NOTIFIER-04: cancel (null) → AsyncData<void>(null) (D-45)',
      () async {
        when(() => mockRepo.signInWithNaver()).thenAnswer((_) async => null);

        final container = makeContainer();
        final notifier = container.read(naverSignInProvider.notifier);

        await notifier.signInWithNaver();

        final state = container.read(naverSignInProvider);
        expect(state, isA<AsyncData<void>>());
        expect(state.hasError, isFalse);
      },
    );

    test('T-13-NAVER-NOTIFIER-05: dispose 후 signInWithNaver 완료 시 '
        'state 미갱신 (ref.mounted 가드)', () async {
      final completer = Completer<Result<User>?>();
      when(
        () => mockRepo.signInWithNaver(),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);

      final future = notifier.signInWithNaver();

      // container dispose 로 ref.mounted = false 유도.
      container.dispose();

      final user = User(
        uid: 'naver-uid-002',
        email: 'late@naver.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 5),
      );
      completer.complete(Result<User>.success(user));

      // 예외 없이 완료되어야 한다 (ref.mounted 가드가 state 업데이트를 차단).
      await future;
    });
  });

  group('NaverSignInNotifier.build '
      '(R7 회귀 가드 — D-42 재정의 / Phase 13 — see ROADMAP.md)', () {
    test('T-13-NAVER-NOTIFIER-R7-01: 초기 state == AsyncData<void>(null) — '
        'R7 회귀 가드 (await/Future.value 추가 시 RED)', () {
      // R7 contract: `FutureOr<void> build()` 가 async work 없이 즉시
      // AsyncData<void>(null) 을 반환해야 한다. 향후 contributor 가 build 본문에
      // await 또는 `return Future.value();` 를 추가하면 build 가 Future 를 반환
      // → 초기 state 가 AsyncLoading 으로 변경 → 본 테스트가 RED 로 전환되어
      // PR review 단계에서 차단된다.
      //
      // Note: Riverpod 3.x 의 build inference 규칙상 `void build()` 로 변경 시
      // generator 가 sync $Notifier<void> 가족으로 강등 — AsyncNotifier 가족
      // 보존을 위해 `FutureOr<void>` 시그니처 유지 (Phase 12.1 Plan 11 SUMMARY
      // Rule 4 참조).
      final container = makeContainer();
      final state = container.read(naverSignInProvider);
      expect(state, const AsyncData<void>(null));
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
    });
  });

  // Phase 16.4 — RESEARCH §2 레버 5(순수 Dart lifecycle 왕복 카운팅)의 성립
  // 여부를 다음 실기기 실행에서 공짜로 판정하기 위한 임시 로그. 존치/제거는
  // plan 06 이 정한다.
  group('NaverSignInNotifier lifecycle 임시 로그 '
      '(T-16.4-NAVER-LIFECYCLE / Phase 16.4 — see ROADMAP.md)', () {
    /// 캡처된 로그에서 전이 줄만 고른다.
    List<String> transitionLines(List<String> logs) =>
        logs.where((line) => line.startsWith('Naver lifecycle 전이: ')).toList();

    /// 캡처된 로그에서 요약 줄만 고른다.
    List<String> summaryLines(List<String> logs) =>
        logs.where((line) => line.startsWith('Naver lifecycle 요약: ')).toList();

    /// [debugPrint] 를 가로채 [logs] 에 쌓는다 (16.2 선례와 동형).
    void captureLogs(List<String> logs) {
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);
    }

    test('T-16.4-NAVER-LIFECYCLE-01: 진행 중 전이가 seq 순서로 찍히고 '
        '완료 시 요약 1줄이 남는다', () async {
      final logs = <String>[];
      captureLogs(logs);

      // 앞선 테스트가 남긴 binding lifecycleState 에 의존하지 않도록 기준점을
      // 잡는다 — 리스너 부착 전이라 로그는 남지 않는다.
      await pushLifecycle(AppLifecycleState.resumed);

      final completer = Completer<Result<User>?>();
      when(
        () => mockRepo.signInWithNaver(),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);
      final future = notifier.signInWithNaver();

      await pushLifecycle(AppLifecycleState.inactive);
      await pushLifecycle(AppLifecycleState.paused);
      await pushLifecycle(AppLifecycleState.resumed);

      // `ServicesBinding._generateStateTransitions` 가 인접하지 않은 전이
      // 사이를 채운다 — 실기기에서도 같은 프레임워크 코드가 돌므로 레버 5 가
      // 보는 신호는 이 전량이다 (주입 3회 ≠ 전이 3회).
      final expectedStates = <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ];

      expect(
        transitionLines(logs),
        equals(<String>[
          for (var i = 0; i < expectedStates.length; i++)
            'Naver lifecycle 전이: state=${expectedStates[i].name} '
                'seq=${i + 1}',
        ]),
        reason: '진행 중 전이는 순서와 seq 를 그대로 남겨야 왕복을 셀 수 있다',
      );

      expect(
        summaryLines(logs),
        isEmpty,
        reason: '요약은 repository 호출이 돌아온 뒤에만 나온다',
      );

      completer.complete(
        Result<User>.success(
          User(
            uid: 'naver-uid-lifecycle',
            email: 'lifecycle@naver.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026, 9, 22),
            providerIds: const <String>['naver'],
          ),
        ),
      );
      await future;

      expect(
        summaryLines(logs),
        equals(<String>[
          'Naver lifecycle 요약: resumed=1 '
              'transitions=${expectedStates.length}',
        ]),
        reason: 'resumed 왕복 수가 레버 5 의 판정 입력이다 — 요약은 정확히 1줄',
      );
    });

    test('T-16.4-NAVER-LIFECYCLE-02: 완료 후 전이는 기록되지 않는다 '
        '(취소 · 실패 두 경로 모두 리스너 해제)', () async {
      final logs = <String>[];
      captureLogs(logs);

      Future<void> runOnce(Result<User>? outcome, String label) async {
        logs.clear();
        await pushLifecycle(AppLifecycleState.resumed);

        final completer = Completer<Result<User>?>();
        when(
          () => mockRepo.signInWithNaver(),
        ).thenAnswer((_) => completer.future);

        final container = makeContainer();
        final notifier = container.read(naverSignInProvider.notifier);
        final future = notifier.signInWithNaver();

        await pushLifecycle(AppLifecycleState.inactive);

        // ① 양성 대조군 먼저 — 0 건이면 아래 「늘지 않는다」 가 자동 참이 되어
        // 해제 회귀를 통째로 놓친다.
        expect(
          transitionLines(logs).length,
          greaterThanOrEqualTo(1),
          reason: '$label 대조군 — 진행 중 전이는 실제로 찍힌다',
        );
        final duringCount = transitionLines(logs).length;

        completer.complete(outcome);
        await future;

        // ② 완료 후 같은 방식으로 밀어 넣어도 늘지 않는다 (finally dispose).
        await pushLifecycle(AppLifecycleState.resumed);
        await pushLifecycle(AppLifecycleState.inactive);

        expect(
          transitionLines(logs).length,
          equals(duringCount),
          reason: '$label: 리스너를 떼지 않으면 다음 로그인까지 누수가 이어진다',
        );
      }

      await runOnce(null, '취소(null)');
      await runOnce(const Result<User>.failure(ServiceUnavailable()), '실패');
    });
  });
}
