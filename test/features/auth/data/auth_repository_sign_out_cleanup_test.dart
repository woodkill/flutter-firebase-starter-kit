// Phase 17 Plan 17-15 Task 3 — 로그아웃 알림 정리 훅 (T-17-NOTIF-10 · D-30).
//
// `signOutAndResetOnboarding` 이 온보딩 reset · signOut **앞**에서
// `onSignOutCleanup` 콜백(D-A2 주입 관례)을 best-effort 로 부르는지 검증한다.
// - 순서 = cleanup → 온보딩 reset → signOut.
// - cleanup 이 오래 걸리면(오프라인 Firestore delete 의 서버 ack 대기) 3초 뒤
//   진행한다 — fake_async 로 시간을 당긴다.
// - cleanup 이 throw 해도 signOut 은 1회 · 메서드는 throw 0.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/auth_mocks.dart';

/// 로그아웃 경로 협력 객체 · 호출 기록.
class _Harness {
  _Harness() {
    when(auth.signOut).thenAnswer((_) async => calls.add('signOut'));
    when(googleSignIn.signOut).thenAnswer((_) async {});
    when(facebookAuth.logOut).thenAnswer((_) async {});
    when(kakao.logout).thenAnswer((_) async {});
    when(naver.logout).thenAnswer((_) async {});
    when(line.logout).thenAnswer((_) async {});
  }

  final MockFirebaseAuth auth = MockFirebaseAuth();
  final MockGoogleSignIn googleSignIn = MockGoogleSignIn();
  final MockFacebookAuth facebookAuth = MockFacebookAuth();
  final MockKakaoSdkClient kakao = MockKakaoSdkClient();
  final MockNaverSdkClient naver = MockNaverSdkClient();
  final MockLineSdkClient line = MockLineSdkClient();

  /// 호출 순서 기록 — `cleanup` · `reset` · `signOut`.
  final List<String> calls = <String>[];

  /// [cleanup] 을 `onSignOutCleanup` 으로 주입한 repository.
  AuthRepository repository(Future<void> Function() cleanup) =>
      buildAuthRepository(
        auth: auth,
        googleSignIn: googleSignIn,
        facebookAuth: facebookAuth,
        kakaoSdkClient: kakao,
        naverSdkClient: naver,
        lineSdkClient: line,
        onResetOnboarding: () async => calls.add('reset'),
        onSignOutCleanup: cleanup,
      );
}

void main() {
  group('Phase 17 알림 토글 (T-17-NOTIF)', () {
    test('T-17-NOTIF-10: 순서 = cleanup → 온보딩 reset → signOut', () async {
      final h = _Harness();
      final repo = h.repository(() async => h.calls.add('cleanup'));

      await repo.signOutAndResetOnboarding();

      expect(h.calls, <String>['cleanup', 'reset', 'signOut']);
      verify(h.auth.signOut).called(1);
    });

    test('T-17-NOTIF-10: cleanup 이 5초 걸려도 3초 뒤 reset · signOut 진행 '
        '(오프라인 delete 대기 차단)', () {
      fakeAsync((async) {
        final h = _Harness();
        final repo = h.repository(() async {
          h.calls.add('cleanup');
          await Future<void>.delayed(const Duration(seconds: 5));
          h.calls.add('cleanup-done');
        });
        var isDone = false;
        Object? error;
        unawaited(
          repo.signOutAndResetOnboarding().then<void>(
            (_) {
              isDone = true;
            },
            onError: (Object e) {
              error = e;
            },
          ),
        );

        async.elapse(const Duration(milliseconds: 2900));
        expect(h.calls, <String>['cleanup']);
        expect(isDone, isFalse);

        async.elapse(const Duration(milliseconds: 200));
        expect(h.calls, <String>['cleanup', 'reset', 'signOut']);
        expect(isDone, isTrue);
        expect(error, isNull);

        // 늦게 끝난 cleanup 은 로그아웃 결과에 영향이 없다.
        async.elapse(const Duration(seconds: 3));
        expect(h.calls.last, 'cleanup-done');
        verify(h.auth.signOut).called(1);
      });
    });

    test(
      'T-17-NOTIF-10: cleanup 이 throw 해도 signOut 1회 · 메서드 throw 0',
      () async {
        final h = _Harness();
        final repo = h.repository(() async {
          h.calls.add('cleanup');
          throw StateError('simulated cleanup failure');
        });

        await expectLater(repo.signOutAndResetOnboarding(), completes);

        expect(h.calls, <String>['cleanup', 'reset', 'signOut']);
        verify(h.auth.signOut).called(1);
      },
    );

    test('T-17-NOTIF-10: onSignOutCleanup 미주입(기본 no-op)이면 기존 순서 그대로 '
        '— 생성자 호출부 회귀 0', () async {
      final h = _Harness();
      final repo = buildAuthRepository(
        auth: h.auth,
        googleSignIn: h.googleSignIn,
        facebookAuth: h.facebookAuth,
        kakaoSdkClient: h.kakao,
        naverSdkClient: h.naver,
        lineSdkClient: h.line,
        onResetOnboarding: () async => h.calls.add('reset'),
      );

      await repo.signOutAndResetOnboarding();

      expect(h.calls, <String>['reset', 'signOut']);
    });
  });
}
