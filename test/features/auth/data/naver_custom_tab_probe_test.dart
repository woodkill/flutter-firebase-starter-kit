// Phase 16.4 — see ROADMAP.md (레버 2 — 커스텀탭 계수 MethodChannel probe)
//
// 원래의 P-03 근거(「Kotlin 컴파일 실패 · 채널 미등록은 빌드와
// `MissingPluginException` 이 시끄럽게 알린다」)는 16.4 code review WR-01 에서
// 반증됐다 — 구현이 바로 그 신호를 삼키고, Kotlin 리터럴이 바뀌어도 전 테스트가
// green 이다. 그래서 이 파일은 셋을 잠근다:
//   ① Dart 측 graceful 흡수(채널 없음 · 호스트 예외 · 타입 불일치 → 0)와
//      플랫폼 가드,
//   ② Kotlin ↔ Dart 소스 계약(채널명 · 메서드명 리터럴, PROBE-06),
//   ③ production 배선 접합부(`NaverSdkClient()` → probe tear-off, PROBE-07).
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_custom_tab_probe.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

import '../../../helpers/source_text.dart';

/// 호스트 채널 — `MainActivity.kt` 의 `CHANNEL` 상수와 같은 문자열이어야 한다.
const MethodChannel kProbeChannel = MethodChannel(
  'com.slimpumpkin.flutter_starter_kit/naver_custom_tab',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  setUp(() {
    calls = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kProbeChannel, null);
  });

  /// 채널에 fake handler 를 건다 — [getCount] 가 `getCount` 응답값이다.
  ///
  /// [rawGetCount] 를 주면 [getCount] 대신 그 값을 그대로 돌려준다 — 호스트가
  /// `Int` 가 아닌 값을 돌려주는 회귀(WR-03) 를 재현하기 위한 통로다.
  void mockHost({
    int getCount = 0,
    Object? rawGetCount,
    bool throwPlatformException = false,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kProbeChannel, (MethodCall call) async {
          calls.add(call.method);
          if (throwPlatformException) {
            throw PlatformException(code: 'boom');
          }
          return switch (call.method) {
            'getCount' => rawGetCount ?? getCount,
            'resetCount' => null,
            _ => null,
          };
        });
  }

  // `T-16.4-NAVER-DISCRIM-03` 의 probe 측 절반 — 구분 로직의 나머지 절반
  // (호출 순서 reset → login → count) 은 `naver_sdk_client_test.dart` 에 있다.
  group(
    'NaverCustomTabProbe (T-16.4-NAVER-DISCRIM-03 / T-16.4-NAVER-PROBE)',
    () {
      test('T-16.4-NAVER-PROBE-01: 호스트가 2 를 돌려주면 readCount() == 2 이고 '
          'resetCount() 는 resetCount 메서드를 1회 호출한다', () async {
        mockHost(getCount: 2);
        const probe = NaverCustomTabProbe();

        await probe.resetCount();
        expect(
          calls,
          equals(<String>['resetCount']),
          reason: '시도 시작 시 계수를 되돌리지 않으면 직전 시도의 값이 누적된다',
        );

        expect(await probe.readCount(), equals(2));
        expect(calls, equals(<String>['resetCount', 'getCount']));
      });

      test(
        'T-16.4-NAVER-PROBE-02: handler 가 없으면 '
        '(MissingPluginException) readCount() == 0 이고 throw 하지 않는다',
        () async {
          // 양성 대조군 — handler 를 걸면 실제로 채널이 응답한다. 아래 0 단언이
          // 「채널이 애초에 안 불렸다」 로 공허하게 참이 되는 것을 막는다.
          mockHost(getCount: 7);
          const probe = NaverCustomTabProbe();
          expect(await probe.readCount(), equals(7), reason: '대조군 — 채널은 살아 있다');

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(kProbeChannel, null);

          expect(await probe.readCount(), equals(0));
          await probe.resetCount(); // throw 하지 않는다 (T-16.4-13 DoS 완화)
        },
      );

      test('T-16.4-NAVER-PROBE-03: PlatformException 도 삼켜 0 / no-op 으로 '
          '흡수한다', () async {
        mockHost(throwPlatformException: true);
        const probe = NaverCustomTabProbe();

        expect(await probe.readCount(), equals(0));
        await probe.resetCount();
        expect(
          calls,
          equals(<String>['getCount', 'resetCount']),
          reason:
              '대조군 — 두 호출 모두 채널에 실제로 도달했다 (IN-05: '
              '「2건 이상」 은 readCount 2회 · resetCount 0회도 통과시킨다)',
        );
      });

      test('T-16.4-NAVER-PROBE-04: iOS 에서는 채널을 호출조차 하지 않고 0 이다 '
          '(D-06 — 결함은 Android 한정)', () async {
        mockHost(getCount: 5);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const probe = NaverCustomTabProbe();

        expect(await probe.readCount(), equals(0));
        await probe.resetCount();
        expect(
          calls,
          isEmpty,
          reason: 'iOS 는 ASWebAuthenticationSession 경로라 대상이 아니다',
        );
      });

      // WR-03 — 「절대 로그인 흐름을 깨지 않는다」 의 나머지 절반. 호스트 반환
      // 타입이 바뀌면 `invokeMethod<int>` 의 cast 가 `TypeError` 를 던지는데,
      // 이것이 새면 `signIn()` 의 try 를 타고 올라가 **성공한 로그인까지**
      // ServiceUnavailable 로 뒤집는다 (계수 조회는 status 판정 전에 await).
      test('T-16.4-NAVER-PROBE-05 WR-03: 호스트가 Int 가 아닌 값을 돌려줘도 '
          'readCount() == 0 이고 throw 하지 않는다', () async {
        // 양성 대조군 먼저 — 같은 handler 모양이 정상 경로에서는 값을 나른다.
        mockHost(getCount: 3);
        const probe = NaverCustomTabProbe();
        expect(await probe.readCount(), equals(3), reason: '대조군 — 채널은 살아 있다');

        calls.clear();
        mockHost(rawGetCount: 'not-an-int');

        expect(
          await probe.readCount(),
          equals(0),
          reason: 'cast 실패는 「재개방 없음」 과 같은 0 으로 접혀야 한다',
        );
        expect(
          calls,
          equals(<String>['getCount']),
          reason: '대조군 — 0 이 「채널이 안 불렸다」 로 공허하게 참이 된 것이 아니다',
        );
      });
    },
  );

  // WR-01 — `flutter test` 는 Kotlin 을 컴파일하지도 실행하지도 않는다. 채널명 ·
  // 메서드명이 Kotlin · Dart 두 곳에 독립 리터럴로 존재하므로, Kotlin 쪽 문자열이
  // 바뀌면 빌드 · analyze · 전 테스트가 green 인 채로 실기기에서 readCount() 가
  // 영구 0 이 된다(= 이 phase 의 유일한 사용자 가시 산출물이 조용히 소멸).
  // `naver_sdk_client_test.dart` 의 T-16.2-NAVER-SDK-21 과 동형인 소스 계약.
  group('Kotlin ↔ Dart 채널 계약 (T-16.4-NAVER-PROBE-06)', () {
    const String kotlinPath =
        'android/app/src/main/kotlin/com/slimpumpkin/'
        'flutter_starter_kit/MainActivity.kt';
    const String dartPath =
        'lib/features/auth/data/naver_custom_tab_probe.dart';

    test('T-16.4-NAVER-PROBE-06 source-contract: 호스트와 Dart 가 같은 채널명 · '
        '메서드명 리터럴을 쓴다', () {
      // 주석을 걷어낸 뒤 매칭한다 — 설명 주석이 「존재한다」 단언을 오염시키면
      // 코드에서 사라진 토큰도 통과한다 (행 주석 · 블록 주석 모두 제거).
      final String kotlin = stripBlockComments(
        stripSlashComments(readTrackedFile(kotlinPath)),
      );
      final String dart = stripBlockComments(
        stripSlashComments(readTrackedFile(dartPath)),
      );

      // 양성 대조군 — 두 파일이 실제로 읽혔고 주석 제거 후에도 구현이 남아 있다.
      expect(kotlin, contains('NidOAuthCustomTabActivity'));
      expect(dart, contains('MethodChannel('));

      const List<String> tokens = <String>[
        'com.slimpumpkin.flutter_starter_kit/naver_custom_tab',
        'resetCount',
        'getCount',
      ];
      for (final String token in tokens) {
        expect(kotlin, contains(token), reason: 'Kotlin 측 $token 누락');
        expect(dart, contains(token), reason: 'Dart 측 $token 누락');
      }

      // 테스트 자신의 사본도 같은 채널을 가리켜야 위 단언이 의미를 갖는다.
      expect(kProbeChannel.name, equals(tokens.first));
    });
  });

  // IN-02 — 두 절반(probe 단위 · client 단위) 은 각각 테스트되지만 **접합부**
  // (`NaverSdkClient()` production ctor → `_kCustomTabProbe` tear-off) 는 어떤
  // 테스트도 지나가지 않았다. tear-off 를 잘못 배선해도 컴파일이 막아주지 않는
  // 조합이 있어, WR-01 과 합치면 「기능 전체가 production 에서 무력화된 채 100%
  // green」 이 성립한다.
  group('production 배선 접합부 (T-16.4-NAVER-PROBE-07)', () {
    const MethodChannel pluginChannel = MethodChannel('naver_login_flutter');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pluginChannel, null);
    });

    test('T-16.4-NAVER-PROBE-07 IN-02: NaverSdkClient() 의 signIn() 이 실제 '
        'naver_custom_tab 채널로 resetCount → getCount 를 보낸다', () async {
      mockHost(getCount: 2);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pluginChannel, (MethodCall call) async {
            calls.add('plugin:${call.method}');
            return <String, Object?>{'status': 'loggedOut'};
          });

      // production ctor — forTest 가 아니다. 여기서만 tear-off 배선을 지난다.
      final NaverSdkClient client = NaverSdkClient();

      Object? thrown;
      try {
        await client.signIn();
      } on Object catch (e) {
        thrown = e;
      }

      expect(
        calls,
        equals(<String>['resetCount', 'plugin:logIn', 'getCount']),
        reason: 'D-19 순서 계약이 production 배선에서도 실제 채널에 도달해야 한다',
      );
      expect(
        thrown,
        isA<ServiceUnavailable>(),
        reason:
            'getCount 가 2 이므로 재개방으로 승격돼야 한다 — 배선이 끊기면 '
            'null 취소로 조용히 통과한다',
      );
      expect(
        ((thrown! as ServiceUnavailable).cause! as NaverCustomTabReopened)
            .count,
        equals(2),
      );
    });
  });
}
