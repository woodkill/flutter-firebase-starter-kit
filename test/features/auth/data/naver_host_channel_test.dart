// Phase 16.5 — see ROADMAP.md (NaverHostChannel unit tests)
//
// NAVER 앱 설치 판정 채널 — 호스트가 넘기는 bool 이 그대로 오고, 호스트 부재 ·
// PlatformException · 반환 타입 불일치는 전부 `false`(= 킷 웹 경로) 로 접힌다
// (D-02 · D-03). 플랫폼 가드가 없으므로(D-01 대칭) Android · iOS 오버라이드
// 양쪽에서 같은 결과여야 한다.
//
// Phase 16.11 — 콜백 도착 기록 조회 · 초기화(T-16.11-NAVER-HOST). 조회 실패는
// 설치 판정과 반대로 `true`(= 계속 대기) 로 접힌다 (RESEARCH Pitfall 5).
//
// **양성 대조군 규율:** `false` 단언 전에 같은 채널이 `true` 를 돌려주는 것을
// 먼저 확인한다 — 「채널이 애초에 안 불렸다」 로 `false` 가 공허하게 참이 되는
// 것을 막는다.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/data/naver_host_channel.dart';

/// 테스트 대상 플랫폼 — D-01 대칭.
const List<TargetPlatform> _platforms = <TargetPlatform>[
  TargetPlatform.android,
  TargetPlatform.iOS,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kNaverHostChannelName);
  const host = NaverHostChannel();
  late List<String> calls;

  /// 호스트 핸들러를 건다 — [respond] 가 `isNaverAppInstalled` 응답을 만든다.
  void mockHost(Object? Function() respond) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call.method);
          if (call.method != kNaverHostMethodIsInstalled) return null;
          return respond();
        });
  }

  /// 호스트 핸들러를 뗀다 (= 채널 미등록 호스트).
  void clearHost() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  setUp(() {
    calls = <String>[];
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    clearHost();
  });

  group('NaverHostChannel.isNaverAppInstalled (T-16.5-NAVER-HOST)', () {
    test('T-16.5-NAVER-HOST-01 호스트 true → true (Android · iOS)', () async {
      for (final platform in _platforms) {
        debugDefaultTargetPlatformOverride = platform;
        calls.clear();
        mockHost(() => true);

        expect(
          await host.isNaverAppInstalled(),
          isTrue,
          reason: '$platform — 플랫폼 가드 없이 채널이 불린다',
        );
        expect(calls, <String>[kNaverHostMethodIsInstalled]);
      }
    });

    test('T-16.5-NAVER-HOST-02 호스트 false → false (양성 대조군 선행)', () async {
      for (final platform in _platforms) {
        debugDefaultTargetPlatformOverride = platform;
        mockHost(() => true);
        expect(await host.isNaverAppInstalled(), isTrue, reason: '대조군');

        mockHost(() => false);
        expect(await host.isNaverAppInstalled(), isFalse, reason: '$platform');
      }
    });

    test('T-16.5-NAVER-HOST-03 호스트 핸들러 부재(MissingPluginException) → '
        'false', () async {
      for (final platform in _platforms) {
        debugDefaultTargetPlatformOverride = platform;
        mockHost(() => true);
        expect(await host.isNaverAppInstalled(), isTrue, reason: '대조군');

        clearHost();
        expect(await host.isNaverAppInstalled(), isFalse, reason: '$platform');
      }
    });

    test('T-16.5-NAVER-HOST-04 PlatformException → false (D-02)', () async {
      for (final platform in _platforms) {
        debugDefaultTargetPlatformOverride = platform;
        mockHost(() => true);
        expect(await host.isNaverAppInstalled(), isTrue, reason: '대조군');

        mockHost(() => throw PlatformException(code: 'boom'));
        expect(await host.isNaverAppInstalled(), isFalse, reason: '$platform');
      }
    });

    test(
      'T-16.5-NAVER-HOST-05 non-bool 반환(int · String) · null → false',
      () async {
        for (final platform in _platforms) {
          debugDefaultTargetPlatformOverride = platform;
          mockHost(() => true);
          expect(await host.isNaverAppInstalled(), isTrue, reason: '대조군');

          for (final raw in const <Object?>[1, 'true', null]) {
            mockHost(() => raw);
            expect(
              await host.isNaverAppInstalled(),
              isFalse,
              reason: '$platform raw=$raw — 타입 불일치 · null 은 false 로 접는다',
            );
          }
        }
      },
    );

    test('T-16.5-NAVER-HOST-06 실패 로그는 예외 타입 이름만 싣는다', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);
      const sentinel = 'HOST-SENTINEL-0ff1ce';

      mockHost(() => throw PlatformException(code: 'boom', message: sentinel));
      expect(await host.isNaverAppInstalled(), isFalse);

      expect(logs, hasLength(1), reason: '대조군 — 실패 줄이 찍혔다');
      expect(logs.single, startsWith('Naver 설치 판정 실패(web 으로 접음): '));
      expect(logs.single, isNot(contains(sentinel)));
    });

    test('T-16.5-NAVER-HOST-07 채널 이름 · 메서드 이름 상수', () {
      expect(
        kNaverHostChannelName,
        'com.slimpumpkin.flutter_starter_kit/naver_host',
      );
      expect(kNaverHostMethodIsInstalled, 'isNaverAppInstalled');
    });
  });

  group('NaverHostChannel 콜백 기록 (T-16.11-NAVER-HOST)', () {
    /// 메서드 이름별로 응답하는 호스트 핸들러를 건다 (Phase 16.11).
    ///
    /// [responders] 에 없는 메서드는 `null` 을 돌려준다. 호출된 메서드 이름은
    /// 전부 `calls` 에 쌓인다.
    void mockHostByMethod(Map<String, Object? Function()> responders) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call.method);
            final respond = responders[call.method];
            return respond?.call();
          });
    }

    test('T-16.11-NAVER-HOST-01 호스트 기록 true → true · false → false', () async {
      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodHasCallbackArrived: () => true,
      });
      expect(
        await host.hasNaverCallbackArrived(),
        isTrue,
        reason: 'D-05: 호스트 기록이 그대로 전달된다 (양성 대조군)',
      );
      expect(calls, <String>['hasNaverCallbackArrived']);

      calls.clear();
      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodHasCallbackArrived: () => false,
      });
      expect(
        await host.hasNaverCallbackArrived(),
        isFalse,
        reason: 'D-05: 「도착 안 함」 기록이 그대로 전달된다',
      );
      expect(calls, <String>['hasNaverCallbackArrived']);
    });

    test('T-16.11-NAVER-HOST-02 조회 실패(부재 · 예외 · 타입 불일치 · null) → '
        'true (Pitfall 5)', () async {
      // 양성 대조군 — `false` 가 그대로 오는 채널에서 시작해야 아래 `true` 가
      // 「안전값으로 접혔다」 는 뜻이 된다.
      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodHasCallbackArrived: () => false,
      });
      expect(await host.hasNaverCallbackArrived(), isFalse, reason: '대조군');

      clearHost();
      expect(
        await host.hasNaverCallbackArrived(),
        isTrue,
        reason: 'Pitfall 5: 판정 불가 = 계속 대기 — 호스트 핸들러 부재',
      );

      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodHasCallbackArrived: () =>
            throw PlatformException(code: 'boom'),
      });
      expect(
        await host.hasNaverCallbackArrived(),
        isTrue,
        reason: 'Pitfall 5: 판정 불가 = 계속 대기 — PlatformException',
      );

      for (final raw in const <Object?>[1, 'true', null]) {
        mockHostByMethod(<String, Object? Function()>{
          kNaverHostMethodHasCallbackArrived: () => raw,
        });
        expect(
          await host.hasNaverCallbackArrived(),
          isTrue,
          reason: 'Pitfall 5: 판정 불가 = 계속 대기 — raw=$raw',
        );
      }
    });

    test('T-16.11-NAVER-HOST-03 초기화는 1회 호출 · 실패해도 throw 없음', () async {
      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodResetCallbackRecord: () => null,
      });
      await host.resetNaverCallbackRecord();
      expect(calls, <String>[
        'resetNaverCallbackRecord',
      ], reason: 'D-05: 초기화 메서드가 정확히 1회 불린다');

      clearHost();
      await expectLater(
        host.resetNaverCallbackRecord(),
        completes,
        reason: 'D-05: 호스트 핸들러 부재에서도 throw 없이 완료',
      );

      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodResetCallbackRecord: () =>
            throw PlatformException(code: 'boom'),
      });
      await expectLater(
        host.resetNaverCallbackRecord(),
        completes,
        reason: 'D-05: PlatformException 에서도 throw 없이 완료',
      );
    });

    test('T-16.11-NAVER-HOST-04 상수 · 실패 로그는 예외 타입 이름만', () async {
      expect(kNaverHostMethodHasCallbackArrived, 'hasNaverCallbackArrived');
      expect(kNaverHostMethodResetCallbackRecord, 'resetNaverCallbackRecord');

      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);
      const sentinel = 'CALLBACK-SENTINEL-0ff1ce';

      mockHostByMethod(<String, Object? Function()>{
        kNaverHostMethodHasCallbackArrived: () =>
            throw PlatformException(code: 'boom', message: sentinel),
        kNaverHostMethodResetCallbackRecord: () =>
            throw PlatformException(code: 'boom', message: sentinel),
      });
      expect(await host.hasNaverCallbackArrived(), isTrue);
      await host.resetNaverCallbackRecord();

      expect(logs, hasLength(2), reason: '대조군 — 실패 줄 2개가 찍혔다');
      expect(logs[0], startsWith('Naver 콜백 기록 조회 실패(계속 대기로 접음): '));
      expect(logs[1], startsWith('Naver 콜백 기록 초기화 실패(무시): '));
      for (final line in logs) {
        expect(
          line,
          isNot(contains(sentinel)),
          reason: 'WR-05 · D-12: 예외 메시지 원문은 로그에 싣지 않는다',
        );
      }
    });
  });
}
